import {Router, type Request} from "express";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {z} from "zod";
import {authenticate, requireRoles} from "./auth.js";
import {ApiError} from "./errors.js";
import {db} from "./firebase.js";
import {documentJson} from "./firestore-json.js";
import {createPaymentCode, getPaymentCode, MONIME_MOMO_PROVIDERS, type MonimeMomoProviderKey} from "./monime-client.js";
import {createOrder as createPaypalOrder, captureOrder as capturePaypalOrder, PayPalAlreadyCapturedError} from "./paypal-client.js";
import {confirmPickupAfterPayment} from "./pickup-routes.js";
import {publishNotificationEvent} from "./push-events.js";
import {createCheckoutSession, constructWebhookEvent} from "./stripe-client.js";

const router = Router();
const users = ["household", "business", "institution", "collector", "driver", "collectionCentreOperator", "repairTechnician", "recycler", "environmentalOfficer", "administrator", "superAdministrator"] as const;
const finance = ["administrator", "superAdministrator"] as const;
function id(value: string | string[]) { return Array.isArray(value) ? value[0] : value; }
function number(value: unknown) { return Number(value ?? 0); }
async function transactionRecord(transactionId: string) { const ref = db.collection("paymentTransactions").doc(transactionId); const snapshot = await ref.get(); if (!snapshot.exists) throw new ApiError(404, "Payment transaction not found.", "not_found"); return {ref, snapshot}; }
function access(data: FirebaseFirestore.DocumentData, uid: string, role: string) { return ["administrator", "superAdministrator"].includes(role) || data.payerId === uid || data.payeeId === uid; }

router.post("/payments/fees/calculate", authenticate, requireRoles(...users), async (request, response) => { const input = z.object({type: z.enum(["pickup", "marketplace", "partnerService", "other"]), quantity: z.number().positive(), weightKg: z.number().nonnegative().default(0), subtotal: z.number().nonnegative().default(0), urgent: z.boolean().default(false), serviceArea: z.string().trim().max(200).default("")}).parse(request.body); const settings = await db.collection("systemSettings").doc("billing").get(); const pickupBase = number(settings.get("pickupBaseFee") || 2); const weightRate = number(settings.get("pickupWeightRate") || 0.75); const urgentFee = input.urgent ? number(settings.get("urgentPickupFee") || 15) : 0; const serviceChargeRate = number(settings.get("serviceChargeRate") || 0.05); const taxRate = number(settings.get("taxRate") || 0.15); const serviceFee = input.type === "pickup" ? pickupBase * input.quantity + weightRate * input.weightKg + urgentFee : input.subtotal * serviceChargeRate; const taxable = input.subtotal + serviceFee; const tax = taxable * taxRate; response.json({data: {currency: "SLE", subtotal: input.subtotal, serviceFee, tax, total: taxable + tax, taxRate, serviceChargeRate}}); });

// Re-derives the authoritative SLE amount for a payment purpose from its
// source record (throwing if the reference doesn't exist, isn't owned by
// this user, or -- for pickups -- isn't currently awaiting payment), rather
// than trusting a client-supplied figure. Used both to validate a
// client-supplied amount (verifiedIntentAmount, below) and, for gateways
// that don't collect an amount from the client at all (Stripe/PayPal), as
// the figure to convert into that gateway's settlement currency.
export async function authoritativeSleAmount(purpose: string, referenceId: string, uid: string): Promise<number> {
  if (purpose === "pickupFee") {
    const pickup = await db.collection("pickupRequests").doc(referenceId).get();
    if (!pickup.exists) throw new ApiError(404, "Referenced pickup request not found.", "not_found");
    if (pickup.get("userId") !== uid) throw new ApiError(403, "You cannot pay for another user's pickup.", "forbidden");
    if (pickup.get("status") !== "draft") throw new ApiError(409, "This pickup request is not awaiting payment.", "not_awaiting_payment");
    return number(pickup.get("estimatedFee"));
  }
  if (purpose === "marketplaceOrder") {
    const order = await db.collection("marketplaceOrders").doc(referenceId).get();
    if (!order.exists) throw new ApiError(404, "Referenced marketplace order not found.", "not_found");
    if (order.get("buyerId") !== uid) throw new ApiError(403, "You cannot pay for another user's order.", "forbidden");
    return number(order.get("total"));
  }
  throw new ApiError(400, "This payment purpose does not have a verifiable server-side amount.", "unverifiable_purpose");
}

// Amounts for purposes with a known server-computed source of truth are
// verified against that source rather than trusted from the client, so a
// payer cannot under-report what they owe before a finance admin confirms it.
export async function verifiedIntentAmount(purpose: string, referenceId: string, uid: string, amount: number): Promise<void> {
  if (purpose !== "pickupFee" && purpose !== "marketplaceOrder") return;
  const expected = await authoritativeSleAmount(purpose, referenceId, uid);
  if (Math.abs(expected - amount) > 0.01) {
    throw new ApiError(409, purpose === "pickupFee"
      ? "The payment amount does not match the pickup's calculated fee."
      : "The payment amount does not match the order total.", "amount_mismatch");
  }
}

// A placeholder rate -- an administrator must calibrate systemSettings/billing
// .sleToUsdRate to a current market rate before Stripe/PayPal payments are
// accepted for real. The rate and resulting USD figure are frozen onto the
// transaction doc at checkout-creation time so a later rate change can't
// retroactively mismatch what was actually charged.
const DEFAULT_SLE_TO_USD_RATE = 20;

async function sleToUsdCents(sleAmount: number): Promise<{usdCents: number; fxRate: number}> {
  const settings = await db.collection("systemSettings").doc("billing").get();
  const fxRate = number(settings.get("sleToUsdRate")) || DEFAULT_SLE_TO_USD_RATE;
  return {usdCents: Math.round((sleAmount / fxRate) * 100), fxRate};
}

type DuplicateOutcome =
  | {kind: "blocked"}
  | {kind: "reuse"; doc: FirebaseFirestore.QueryDocumentSnapshot}
  | {kind: "clear"};

// A payer retrying a duplicate button press (or a page reload mid-checkout)
// should never spawn a second gateway session/order for the same reference:
// an already-confirmed payment is blocked outright, an in-flight one is
// handed back so the caller can reuse its existing checkout artifact, and
// only a genuinely failed prior attempt clears the way for a fresh one.
async function checkDuplicateTransaction(uid: string, referenceId: string, purpose: string): Promise<DuplicateOutcome> {
  const duplicate = await db.collection("paymentTransactions")
    .where("payerId", "==", uid)
    .where("referenceId", "==", referenceId)
    .where("purpose", "==", purpose)
    .limit(1).get();
  if (duplicate.empty) return {kind: "clear"};
  const existing = duplicate.docs[0];
  const status = String(existing.get("status"));
  if (status === "confirmed") return {kind: "blocked"};
  if (["pending", "processing"].includes(status)) return {kind: "reuse", doc: existing};
  return {kind: "clear"};
}

router.post("/payments/intents", authenticate, requireRoles(...users), async (request, response) => { const input = z.object({purpose: z.enum(["pickupFee", "marketplaceOrder", "partnerService", "other"]), referenceId: z.string().trim().min(1), amount: z.number().positive(), currency: z.string().trim().length(3).default("SLE"), method: z.enum(["mobileMoney", "bank", "card"]), provider: z.string().trim().min(2).max(100), payerPhoneOrReference: z.string().trim().min(2).max(200)}).parse(request.body); await verifiedIntentAmount(input.purpose, input.referenceId, request.user!.uid, input.amount); const duplicate = await db.collection("paymentTransactions").where("payerId", "==", request.user!.uid).where("referenceId", "==", input.referenceId).where("purpose", "==", input.purpose).limit(1).get(); if (!duplicate.empty && ["pending", "confirmed"].includes(String(duplicate.docs[0].get("status")))) throw new ApiError(409, "An active payment already exists for this reference.", "duplicate_payment"); const ref = db.collection("paymentTransactions").doc(); await ref.set({...input, transactionNumber: `PAY-${ref.id.substring(0, 10).toUpperCase()}`, payerId: request.user!.uid, status: "pending", providerStatus: "initiated", attempts: 1, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}); response.status(201).json({data: {id: ref.id, transactionNumber: `PAY-${ref.id.substring(0, 10).toUpperCase()}`, status: "pending", providerRequest: {provider: input.provider, method: input.method}}}); });

const monimeProviderLabels: Record<MonimeMomoProviderKey, string> = {orangeMoney: "Orange Money", afrimoney: "Afrimoney"};

// Maps a Monime payment-code lifecycle status to this app's payment status vocabulary.
function monimeStatusMapping(monimeStatus: string): {status: string; providerStatus: string} {
  if (monimeStatus === "completed") return {status: "confirmed", providerStatus: "completed"};
  if (monimeStatus === "expired") return {status: "failed", providerStatus: "expired"};
  if (monimeStatus === "cancelled") return {status: "failed", providerStatus: "cancelled"};
  if (monimeStatus === "processing") return {status: "processing", providerStatus: "processing"};
  return {status: "pending", providerStatus: "pending"};
}

router.post("/payments/monime/initiate", authenticate, requireRoles(...users), async (request, response) => {
  const input = z.object({
    purpose: z.enum(["pickupFee", "marketplaceOrder", "partnerService", "other"]),
    referenceId: z.string().trim().min(1),
    amount: z.number().positive(),
    currency: z.string().trim().length(3).default("SLE"),
    provider: z.enum(["orangeMoney", "afrimoney"]),
    phoneNumber: z.string().trim().regex(/^\+?[0-9]{8,15}$/, "Enter a valid mobile money phone number."),
  }).parse(request.body);
  await verifiedIntentAmount(input.purpose, input.referenceId, request.user!.uid, input.amount);
  const duplicate = await checkDuplicateTransaction(request.user!.uid, input.referenceId, input.purpose);
  if (duplicate.kind === "blocked") {
    throw new ApiError(409, "This has already been paid.", "already_paid");
  }
  if (duplicate.kind === "reuse") {
    // A payment attempt is already in flight for this reference (e.g. a
    // duplicate button press) — reuse it instead of creating a second
    // Monime payment code, so retries never double-charge.
    const existing = duplicate.doc;
    const monime = existing.get("monime") as {ussdCode?: string; expireTime?: string} | undefined;
    response.status(200).json({data: {
      id: existing.id,
      transactionNumber: existing.get("transactionNumber"),
      status: String(existing.get("status")),
      ussdCode: monime?.ussdCode ?? "",
      expiresAt: monime?.expireTime ?? null,
    }});
    return;
  }
  const ref = db.collection("paymentTransactions").doc();
  const providerId = MONIME_MOMO_PROVIDERS[input.provider];
  const paymentCode = await createPaymentCode({
    name: `EcoTrace ${input.purpose}`.slice(0, 64),
    amountMinorUnits: Math.round(input.amount * 100),
    currency: input.currency,
    providerId,
    durationMinutes: 30,
    reference: ref.id,
    metadata: {ecotraceTransactionId: ref.id, purpose: input.purpose, referenceId: input.referenceId},
  }, ref.id);
  const transactionNumber = `PAY-${ref.id.substring(0, 10).toUpperCase()}`;
  await ref.set({
    purpose: input.purpose, referenceId: input.referenceId, amount: input.amount, currency: input.currency,
    method: "mobileMoney", provider: monimeProviderLabels[input.provider], payerId: request.user!.uid,
    status: "pending", providerStatus: "initiated", transactionNumber, attempts: 1, gateway: "monime",
    monime: {paymentCodeId: paymentCode.id, ussdCode: paymentCode.ussdCode, providerId, phoneNumber: input.phoneNumber, expireTime: paymentCode.expireTime},
    createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  });
  response.status(201).json({data: {id: ref.id, transactionNumber, status: "pending", ussdCode: paymentCode.ussdCode, expiresAt: paymentCode.expireTime}});
});

// Called directly by Monime, not by an app user, so this route intentionally has no Firebase
// auth. Monime's `Monime-Signature` verification algorithm is undocumented and unconfirmed as of
// this integration (see project notes), so instead of trusting the webhook body we treat it only
// as a trigger to re-fetch the authoritative payment-code status from Monime's own API before
// writing anything to Firestore. This keeps the endpoint safe against a spoofed or malformed
// webhook call even though signature verification is not yet enforced.
router.post("/payments/monime/webhook", async (request, response) => {
  const signaturePresent = Boolean(request.header("monime-signature"));
  const body = request.body as {event?: {name?: string}; object?: {id?: string; type?: string}};
  const eventName = String(body?.event?.name ?? "");
  const objectId = String(body?.object?.id ?? "");
  console.log(`Monime webhook received: event=${eventName || "unknown"} object=${body?.object?.type ?? "?"}:${objectId || "?"} signature=${signaturePresent ? "present" : "MISSING"}`);
  if (!eventName.startsWith("payment_code.") || eventName === "payment_code.created" || !objectId) {
    response.status(200).json({received: true});
    return;
  }
  const matches = await db.collection("paymentTransactions").where("monime.paymentCodeId", "==", objectId).limit(1).get();
  if (matches.empty) {
    console.warn(`Monime webhook referenced unknown payment code ${objectId}.`);
    response.status(200).json({received: true});
    return;
  }
  const doc = matches.docs[0];
  if (["confirmed", "failed"].includes(String(doc.get("status")))) {
    response.status(200).json({received: true});
    return;
  }
  const paymentCode = await getPaymentCode(objectId);
  const mapped = monimeStatusMapping(paymentCode.status);
  const channelData = paymentCode.processedPaymentData?.channelData;
  await doc.ref.update({
    status: mapped.status,
    providerStatus: mapped.providerStatus,
    providerReference: channelData?.reference ?? paymentCode.processedPaymentData?.financialTransactionReference ?? "",
    failureReason: mapped.status === "failed" ? (paymentCode.status === "expired" ? "The payment code expired before the customer completed payment." : "The payment was cancelled.") : "",
    confirmedAt: mapped.status === "confirmed" ? FieldValue.serverTimestamp() : null,
    failedAt: mapped.status === "failed" ? FieldValue.serverTimestamp() : null,
    "monime.lastEventName": eventName,
    updatedAt: FieldValue.serverTimestamp(),
  });
  if (mapped.status === "confirmed" || mapped.status === "failed") {
    void publishNotificationEvent({
      event: mapped.status === "confirmed" ? "payment_confirmed" : "payment_failed",
      recipientId: String(doc.get("payerId") ?? ""),
      body: mapped.status === "confirmed"
        ? `Your payment of ${doc.get("amount")} ${doc.get("currency")} was confirmed.`
        : `Your payment could not be processed: ${paymentCode.status === "expired" ? "the payment code expired" : "it was cancelled"}.`,
      data: {transactionId: doc.ref.id},
    });
    if (mapped.status === "confirmed" && doc.get("purpose") === "pickupFee") {
      await confirmPickupAfterPayment(String(doc.get("referenceId")));
    }
  }
  response.status(200).json({received: true});
});

function webAppUrl(): string {
  return (process.env.WEB_APP_URL?.trim() || "https://wastemanagementsystem-902eb.web.app").replace(/\/$/, "");
}

// This API's own public base URL, used to build a return URL PayPal's servers redirect the
// payer's browser to -- distinct from webAppUrl(), which is the Flutter web frontend.
function apiPublicUrl(): string {
  return (process.env.API_PUBLIC_URL?.trim() || "https://ecotrace-api-ixev.onrender.com").replace(/\/$/, "");
}

router.post("/payments/stripe/checkout", authenticate, requireRoles(...users), async (request, response) => {
  const input = z.object({
    purpose: z.enum(["pickupFee", "marketplaceOrder"]),
    referenceId: z.string().trim().min(1),
  }).parse(request.body);
  const sleAmount = await authoritativeSleAmount(input.purpose, input.referenceId, request.user!.uid);
  const duplicate = await checkDuplicateTransaction(request.user!.uid, input.referenceId, input.purpose);
  if (duplicate.kind === "blocked") {
    throw new ApiError(409, "This has already been paid.", "already_paid");
  }
  if (duplicate.kind === "reuse") {
    const existing = duplicate.doc;
    const stripe = existing.get("stripe") as {checkoutUrl?: string} | undefined;
    response.status(200).json({data: {
      id: existing.id,
      transactionNumber: existing.get("transactionNumber"),
      status: String(existing.get("status")),
      checkoutUrl: stripe?.checkoutUrl ?? "",
    }});
    return;
  }
  const ref = db.collection("paymentTransactions").doc();
  const {usdCents, fxRate} = await sleToUsdCents(sleAmount);
  const transactionNumber = `PAY-${ref.id.substring(0, 10).toUpperCase()}`;
  const session = await createCheckoutSession({
    amountUsdCents: usdCents,
    reference: ref.id,
    successUrl: webAppUrl(),
    cancelUrl: webAppUrl(),
    metadata: {ecotraceTransactionId: ref.id, purpose: input.purpose, referenceId: input.referenceId},
  });
  await ref.set({
    purpose: input.purpose, referenceId: input.referenceId, amount: sleAmount, currency: "SLE",
    method: "card", provider: "Stripe", payerId: request.user!.uid,
    status: "pending", providerStatus: "initiated", transactionNumber, attempts: 1, gateway: "stripe",
    stripe: {sessionId: session.id, checkoutUrl: session.url, usdCents, fxRate},
    createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  });
  response.status(201).json({data: {id: ref.id, transactionNumber, status: "pending", checkoutUrl: session.url}});
});

// Called directly by Stripe, not by an app user, so this route intentionally has no Firebase
// auth. Unlike Monime, Stripe's webhook signature verification is well-documented and fully
// supported (constructWebhookEvent, in stripe-client.ts), so it's enforced rather than treated
// as an untrusted trigger. Only checkout.session.completed/.expired drive status transitions --
// payment_intent.payment_failed is deliberately ignored, since a Checkout Session lets the
// customer retry a declined card within the same still-open session.
router.post("/payments/stripe/webhook", async (request, response) => {
  const signature = request.header("stripe-signature") ?? "";
  const rawBody = (request as Request & {rawBody?: Buffer}).rawBody;
  if (!rawBody) throw new ApiError(400, "Missing raw request body for signature verification.", "stripe_invalid_signature");
  const event = constructWebhookEvent(rawBody, signature);
  console.log(`Stripe webhook received: event=${event.type} id=${event.id}`);
  if (event.type !== "checkout.session.completed" && event.type !== "checkout.session.expired") {
    response.status(200).json({received: true});
    return;
  }
  const session = event.data.object as {id: string; payment_intent?: string | null};
  const matches = await db.collection("paymentTransactions").where("stripe.sessionId", "==", session.id).limit(1).get();
  if (matches.empty) {
    console.warn(`Stripe webhook referenced unknown session ${session.id}.`);
    response.status(200).json({received: true});
    return;
  }
  const doc = matches.docs[0];
  if (["confirmed", "failed"].includes(String(doc.get("status")))) {
    response.status(200).json({received: true});
    return;
  }
  const confirmed = event.type === "checkout.session.completed";
  await doc.ref.update({
    status: confirmed ? "confirmed" : "failed",
    providerStatus: event.type,
    providerReference: typeof session.payment_intent === "string" ? session.payment_intent : "",
    failureReason: confirmed ? "" : "The checkout session expired before payment was completed.",
    confirmedAt: confirmed ? FieldValue.serverTimestamp() : null,
    failedAt: confirmed ? null : FieldValue.serverTimestamp(),
    "stripe.lastEventType": event.type,
    updatedAt: FieldValue.serverTimestamp(),
  });
  void publishNotificationEvent({
    event: confirmed ? "payment_confirmed" : "payment_failed",
    recipientId: String(doc.get("payerId") ?? ""),
    body: confirmed
      ? `Your payment of ${doc.get("amount")} ${doc.get("currency")} was confirmed.`
      : "Your payment could not be processed: the checkout session expired.",
    data: {transactionId: doc.ref.id},
  });
  if (confirmed && doc.get("purpose") === "pickupFee") {
    await confirmPickupAfterPayment(String(doc.get("referenceId")));
  }
  response.status(200).json({received: true});
});

router.post("/payments/paypal/checkout", authenticate, requireRoles(...users), async (request, response) => {
  const input = z.object({
    purpose: z.enum(["pickupFee", "marketplaceOrder"]),
    referenceId: z.string().trim().min(1),
  }).parse(request.body);
  const sleAmount = await authoritativeSleAmount(input.purpose, input.referenceId, request.user!.uid);
  const duplicate = await checkDuplicateTransaction(request.user!.uid, input.referenceId, input.purpose);
  if (duplicate.kind === "blocked") {
    throw new ApiError(409, "This has already been paid.", "already_paid");
  }
  if (duplicate.kind === "reuse") {
    const existing = duplicate.doc;
    const paypal = existing.get("paypal") as {approveUrl?: string} | undefined;
    response.status(200).json({data: {
      id: existing.id,
      transactionNumber: existing.get("transactionNumber"),
      status: String(existing.get("status")),
      approveUrl: paypal?.approveUrl ?? "",
    }});
    return;
  }
  const ref = db.collection("paymentTransactions").doc();
  const {usdCents, fxRate} = await sleToUsdCents(sleAmount);
  const transactionNumber = `PAY-${ref.id.substring(0, 10).toUpperCase()}`;
  const order = await createPaypalOrder({
    amountUsdCents: usdCents,
    reference: ref.id,
    returnUrl: `${apiPublicUrl()}/api/v1/payments/paypal/capture`,
    cancelUrl: webAppUrl(),
  });
  await ref.set({
    purpose: input.purpose, referenceId: input.referenceId, amount: sleAmount, currency: "SLE",
    method: "paypal", provider: "PayPal", payerId: request.user!.uid,
    status: "pending", providerStatus: "initiated", transactionNumber, attempts: 1, gateway: "paypal",
    paypal: {orderId: order.id, approveUrl: order.approveUrl, usdCents, fxRate},
    createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  });
  response.status(201).json({data: {id: ref.id, transactionNumber, status: "pending", approveUrl: order.approveUrl}});
});

async function finalizePaypalCapture(orderId: string): Promise<void> {
  const matches = await db.collection("paymentTransactions").where("paypal.orderId", "==", orderId).limit(1).get();
  if (matches.empty) {
    console.warn(`PayPal capture referenced unknown order ${orderId}.`);
    return;
  }
  const doc = matches.docs[0];
  // Short-circuits a page reload, back-button, or a duplicate hit from both
  // the redirect and the webhook racing each other -- exactly like Monime's
  // webhook does before it writes anything.
  if (["confirmed", "failed"].includes(String(doc.get("status")))) return;
  let captureStatus: string;
  try {
    captureStatus = (await capturePaypalOrder(orderId)).status;
  } catch (error) {
    if (error instanceof PayPalAlreadyCapturedError) {
      captureStatus = "COMPLETED";
    } else {
      throw error;
    }
  }
  const confirmed = captureStatus === "COMPLETED";
  await doc.ref.update({
    status: confirmed ? "confirmed" : "failed",
    providerStatus: captureStatus,
    failureReason: confirmed ? "" : "PayPal did not complete the capture.",
    confirmedAt: confirmed ? FieldValue.serverTimestamp() : null,
    failedAt: confirmed ? null : FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  void publishNotificationEvent({
    event: confirmed ? "payment_confirmed" : "payment_failed",
    recipientId: String(doc.get("payerId") ?? ""),
    body: confirmed
      ? `Your payment of ${doc.get("amount")} ${doc.get("currency")} was confirmed.`
      : "Your payment could not be processed by PayPal.",
    data: {transactionId: doc.ref.id},
  });
  if (confirmed && doc.get("purpose") === "pickupFee") {
    await confirmPickupAfterPayment(String(doc.get("referenceId")));
  }
}

// PayPal redirects the payer's browser here (not an API call) after they approve on PayPal's
// hosted page, so this intentionally has no Firebase auth -- the `token` query param is used
// only as a lookup key into our own transaction record, never trusted for amount/status, so an
// unmatched or foreign token can't confirm a different payer's transaction.
router.get("/payments/paypal/capture", async (request, response) => {
  const token = typeof request.query.token === "string" ? request.query.token : "";
  if (token) {
    try {
      await finalizePaypalCapture(token);
    } catch (error) {
      console.error(`PayPal capture failed for order ${token}:`, error);
    }
  }
  response.redirect(302, webAppUrl());
});

// A backup confirmation path for when the payer approves on PayPal but never lands back on the
// capture redirect above (closed tab, lost network, abandoned) -- same unverified-signature-but
// -authoritative-refetch posture as Monime's webhook today.
router.post("/payments/paypal/webhook", async (request, response) => {
  const body = request.body as {event_type?: string; resource?: {id?: string; supplementary_data?: {related_ids?: {order_id?: string}}}};
  const eventType = String(body?.event_type ?? "");
  console.log(`PayPal webhook received: event=${eventType || "unknown"}`);
  const orderId = body?.resource?.supplementary_data?.related_ids?.order_id ?? (eventType === "CHECKOUT.ORDER.APPROVED" ? body?.resource?.id : undefined);
  if (!orderId || (eventType !== "CHECKOUT.ORDER.APPROVED" && eventType !== "PAYMENT.CAPTURE.COMPLETED")) {
    response.status(200).json({received: true});
    return;
  }
  try {
    await finalizePaypalCapture(orderId);
  } catch (error) {
    console.error(`PayPal webhook capture failed for order ${orderId}:`, error);
  }
  response.status(200).json({received: true});
});

router.get("/payments/transactions", authenticate, requireRoles(...users), async (request, response) => { const privileged = ["administrator", "superAdministrator"].includes(request.user!.role); let query: FirebaseFirestore.Query = db.collection("paymentTransactions"); if (!privileged) query = query.where("payerId", "==", request.user!.uid); if (typeof request.query.status === "string") query = query.where("status", "==", request.query.status); const snapshot = await query.limit(500).get(); response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))}); });

router.get("/payments/transactions/:id", authenticate, requireRoles(...users), async (request, response) => { const payment = await transactionRecord(id(request.params.id)); if (!access(payment.snapshot.data()!, request.user!.uid, request.user!.role)) throw new ApiError(403, "You cannot access this transaction.", "forbidden"); response.json({data: documentJson(payment.snapshot.id, payment.snapshot.data()!)}); });

router.patch("/payments/transactions/:id/confirm", authenticate, requireRoles(...finance), async (request, response) => { const input = z.object({providerReference: z.string().trim().min(2).max(200), providerStatus: z.enum(["successful", "failed"]), failureReason: z.string().trim().max(1000).default("")}).parse(request.body); const payment = await transactionRecord(id(request.params.id)); if (payment.snapshot.get("status") !== "pending") throw new ApiError(409, "Only pending payments can be confirmed.", "invalid_state"); const successful = input.providerStatus === "successful"; await payment.ref.update({...input, status: successful ? "confirmed" : "failed", confirmedBy: request.user!.uid, confirmedAt: successful ? FieldValue.serverTimestamp() : null, failedAt: successful ? null : FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}); void publishNotificationEvent({event: successful ? "payment_confirmed" : "payment_failed", recipientId: String(payment.snapshot.get("payerId") ?? ""), body: successful ? `Your payment of ${payment.snapshot.get("amount")} ${payment.snapshot.get("currency")} was confirmed.` : `Your payment could not be processed: ${input.failureReason || "provider declined the transaction"}.`, data: {transactionId: payment.ref.id}}); response.json({data: {id: payment.ref.id, status: successful ? "confirmed" : "failed"}}); });

router.post("/payments/transactions/:id/retry", authenticate, requireRoles(...users), async (request, response) => { const input = z.object({method: z.enum(["mobileMoney", "bank", "card"]), provider: z.string().trim().min(2).max(100)}).parse(request.body); const payment = await transactionRecord(id(request.params.id)); if (payment.snapshot.get("payerId") !== request.user!.uid && !["administrator", "superAdministrator"].includes(request.user!.role)) throw new ApiError(403, "You cannot retry this payment.", "forbidden"); if (payment.snapshot.get("status") !== "failed") throw new ApiError(409, "Only failed payments can be retried.", "invalid_state"); await payment.ref.update({...input, status: "pending", providerStatus: "reinitiated", attempts: FieldValue.increment(1), failureReason: "", updatedAt: FieldValue.serverTimestamp()}); response.json({data: {id: payment.ref.id, status: "pending"}}); });

router.post("/payments/transactions/:id/refunds", authenticate, requireRoles(...finance), async (request, response) => { const input = z.object({amount: z.number().positive(), reason: z.string().trim().min(2).max(1000)}).parse(request.body); const payment = await transactionRecord(id(request.params.id)); if (!["confirmed", "refundPending"].includes(String(payment.snapshot.get("status")))) throw new ApiError(409, "Only confirmed or refund-pending payments can be refunded.", "invalid_state"); const refunded = number(payment.snapshot.get("refundedAmount")); if (refunded + input.amount > number(payment.snapshot.get("amount")) + 0.001) throw new ApiError(409, "Refund exceeds the captured amount.", "amount_exceeded"); const ref = payment.ref.collection("refunds").doc(); const totalRefunded = refunded + input.amount; const batch = db.batch(); batch.set(ref, {...input, status: "processed", processedBy: request.user!.uid, createdAt: FieldValue.serverTimestamp()}); batch.update(payment.ref, {refundedAmount: totalRefunded, status: totalRefunded >= number(payment.snapshot.get("amount")) - 0.001 ? "refunded" : "partiallyRefunded", updatedAt: FieldValue.serverTimestamp()}); await batch.commit(); void publishNotificationEvent({event: "payment_refunded", recipientId: String(payment.snapshot.get("payerId") ?? ""), body: `A refund of ${input.amount} ${payment.snapshot.get("currency")} was issued for your payment.`, data: {transactionId: payment.ref.id, refundedAmount: totalRefunded}}); response.status(201).json({data: {id: ref.id, refundedAmount: totalRefunded}}); });

router.post("/payments/invoices", authenticate, requireRoles(...users), async (request, response) => { const input = z.object({referenceType: z.enum(["pickup", "marketplaceOrder", "partnerContract", "other"]), referenceId: z.string().trim().min(1), customerId: z.string().trim().min(1), lineItems: z.array(z.object({description: z.string().trim().min(2).max(300), quantity: z.number().positive(), unitPrice: z.number().nonnegative()})).min(1), currency: z.string().trim().length(3).default("SLE"), taxRate: z.number().min(0).max(1).default(0.15), dueAt: z.coerce.date()}).parse(request.body); if (input.customerId !== request.user!.uid && !["administrator", "superAdministrator"].includes(request.user!.role)) throw new ApiError(403, "You cannot invoice another customer.", "forbidden"); const subtotal = input.lineItems.reduce((sum, item) => sum + item.quantity * item.unitPrice, 0); const tax = subtotal * input.taxRate; const ref = db.collection("invoices").doc(); await ref.set({...input, invoiceNumber: `INV-${ref.id.substring(0, 10).toUpperCase()}`, subtotal, tax, total: subtotal + tax, amountPaid: 0, status: "issued", dueAt: Timestamp.fromDate(input.dueAt), issuedBy: request.user!.uid, issuedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}); response.status(201).json({data: {id: ref.id, invoiceNumber: `INV-${ref.id.substring(0, 10).toUpperCase()}`, subtotal, tax, total: subtotal + tax}}); });

router.get("/payments/invoices", authenticate, requireRoles(...users), async (request, response) => { const privileged = ["administrator", "superAdministrator"].includes(request.user!.role); const query = privileged ? db.collection("invoices") : db.collection("invoices").where("customerId", "==", request.user!.uid); const snapshot = await query.limit(500).get(); response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))}); });

router.post("/payments/payouts", authenticate, requireRoles(...finance), async (request, response) => { const input = z.object({payeeId: z.string().trim().min(1), payeeType: z.enum(["partner", "collector", "driver", "seller"]), amount: z.number().positive(), currency: z.string().trim().length(3).default("SLE"), method: z.enum(["mobileMoney", "bank"]), accountReference: z.string().trim().min(2).max(200), referenceIds: z.array(z.string().trim().min(1)).min(1)}).parse(request.body); const ref = db.collection("payouts").doc(); await ref.set({...input, payoutNumber: `OUT-${ref.id.substring(0, 10).toUpperCase()}`, status: "pending", approvedBy: request.user!.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}); response.status(201).json({data: {id: ref.id, payoutNumber: `OUT-${ref.id.substring(0, 10).toUpperCase()}`}}); });

router.patch("/payments/payouts/:id/process", authenticate, requireRoles(...finance), async (request, response) => { const input = z.object({status: z.enum(["paid", "failed"]), providerReference: z.string().trim().min(1).max(200), failureReason: z.string().trim().max(1000).default("")}).parse(request.body); const ref = db.collection("payouts").doc(id(request.params.id)); const payout = await ref.get(); if (!payout.exists) throw new ApiError(404, "Payout not found.", "not_found"); if (payout.get("status") !== "pending") throw new ApiError(409, "Only pending payouts can be processed.", "invalid_state"); await ref.update({...input, processedBy: request.user!.uid, processedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}); if (input.status === "paid") void publishNotificationEvent({event: "payout_processed", recipientId: String(payout.get("payeeId") ?? ""), body: `A payout of ${payout.get("amount")} ${payout.get("currency")} was processed.`, data: {payoutId: ref.id}}); response.json({data: {id: ref.id, status: input.status}}); });

router.post("/payments/reconciliation", authenticate, requireRoles(...finance), async (request, response) => { const input = z.object({from: z.coerce.date(), to: z.coerce.date(), provider: z.string().trim().max(100).default("")}).parse(request.body); if (input.to <= input.from) throw new ApiError(400, "Reconciliation end must be after start.", "invalid_argument"); let query: FirebaseFirestore.Query = db.collection("paymentTransactions").where("createdAt", ">=", Timestamp.fromDate(input.from)).where("createdAt", "<=", Timestamp.fromDate(input.to)); if (input.provider) query = query.where("provider", "==", input.provider); const snapshot = await query.limit(2000).get(); let confirmedAmount = 0; let failedAmount = 0; let refundedAmount = 0; for (const doc of snapshot.docs) { if (doc.get("status") === "confirmed" || doc.get("status") === "partiallyRefunded") confirmedAmount += number(doc.get("amount")); if (doc.get("status") === "failed") failedAmount += number(doc.get("amount")); refundedAmount += number(doc.get("refundedAmount")); } const ref = await db.collection("financialReconciliations").add({...input, from: Timestamp.fromDate(input.from), to: Timestamp.fromDate(input.to), transactionCount: snapshot.size, confirmedAmount, failedAmount, refundedAmount, netAmount: confirmedAmount - refundedAmount, createdBy: request.user!.uid, createdAt: FieldValue.serverTimestamp()}); response.status(201).json({data: {id: ref.id, transactionCount: snapshot.size, confirmedAmount, failedAmount, refundedAmount, netAmount: confirmedAmount - refundedAmount}}); });

router.get("/payments/reports/summary", authenticate, requireRoles(...finance), async (_request, response) => { const [transactions, payouts, invoices] = await Promise.all([db.collection("paymentTransactions").limit(2000).get(), db.collection("payouts").limit(1000).get(), db.collection("invoices").limit(1000).get()]); const byStatus: Record<string, number> = {}; let collected = 0; let refunds = 0; let paidOut = 0; for (const doc of transactions.docs) { const status = String(doc.get("status") ?? "unknown"); byStatus[status] = (byStatus[status] ?? 0) + 1; if (["confirmed", "partiallyRefunded"].includes(status)) collected += number(doc.get("amount")); refunds += number(doc.get("refundedAmount")); } for (const doc of payouts.docs) if (doc.get("status") === "paid") paidOut += number(doc.get("amount")); response.json({data: {transactions: transactions.size, invoices: invoices.size, collected, refunds, paidOut, netCash: collected - refunds - paidOut, failedPayments: byStatus.failed ?? 0, byStatus}}); });

export default router;
