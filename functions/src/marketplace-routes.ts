import {Router} from "express";
import {FieldValue} from "firebase-admin/firestore";
import {z} from "zod";
import {authenticate, requireRoles} from "./auth.js";
import {ApiError} from "./errors.js";
import {db} from "./firebase.js";
import {documentJson} from "./firestore-json.js";

const router = Router();
const buyers = ["household", "business", "institution", "collector", "driver", "collectionCentreOperator", "repairTechnician", "recycler", "environmentalOfficer", "administrator", "superAdministrator"] as const;
const sellers = ["repairTechnician", "recycler", "administrator", "superAdministrator"] as const;
const managers = ["administrator", "superAdministrator"] as const;
const listingTypes = ["refurbishedDevice", "recoveredMaterial"] as const;

function id(value: string | string[]) { return Array.isArray(value) ? value[0] : value; }
function number(value: unknown) { return Number(value ?? 0); }
async function listingRecord(listingId: string) {
  const ref = db.collection("marketplaceListings").doc(listingId); const snapshot = await ref.get();
  if (!snapshot.exists) throw new ApiError(404, "Marketplace listing not found.", "not_found"); return {ref, snapshot};
}
async function orderRecord(orderId: string) {
  const ref = db.collection("marketplaceOrders").doc(orderId); const snapshot = await ref.get();
  if (!snapshot.exists) throw new ApiError(404, "Marketplace order not found.", "not_found"); return {ref, snapshot};
}
function orderAccess(data: FirebaseFirestore.DocumentData, uid: string, role: string) { return ["administrator", "superAdministrator"].includes(role) || data.buyerId === uid || data.sellerId === uid; }

router.get("/marketplace/listings", async (request, response) => {
  let query: FirebaseFirestore.Query = db.collection("marketplaceListings").where("status", "==", "active");
  if (typeof request.query.type === "string") query = query.where("type", "==", request.query.type);
  if (typeof request.query.category === "string") query = query.where("category", "==", request.query.category);
  const snapshot = await query.limit(300).get(); const search = typeof request.query.search === "string" ? request.query.search.trim().toLowerCase() : "";
  const data = snapshot.docs.map((doc) => documentJson(doc.id, doc.data())).filter((item) => !search || `${item.title} ${item.description} ${item.category}`.toLowerCase().includes(search));
  response.json({data});
});

router.get("/marketplace/listings/:id", async (request, response) => {
  const listing = await listingRecord(id(request.params.id));
  if (listing.snapshot.get("status") !== "active") throw new ApiError(404, "Active listing not found.", "not_found");
  response.json({data: documentJson(listing.snapshot.id, listing.snapshot.data()!)});
});

router.put("/marketplace/buyer-profile", authenticate, requireRoles(...buyers), async (request, response) => {
  const input = z.object({displayName: z.string().trim().min(2).max(200), phone: z.string().trim().min(5).max(50), deliveryAddress: z.string().trim().min(2).max(500), buyerType: z.enum(["individual", "business", "institution"]), organizationName: z.string().trim().max(300).default("")}).parse(request.body);
  await db.collection("marketplaceBuyers").doc(request.user!.uid).set({...input, userId: request.user!.uid, email: request.user!.email ?? "", active: true, updatedAt: FieldValue.serverTimestamp(), createdAt: FieldValue.serverTimestamp()}, {merge: true});
  response.json({data: {id: request.user!.uid}});
});

router.put("/marketplace/seller-profile", authenticate, requireRoles(...sellers), async (request, response) => {
  const input = z.object({displayName: z.string().trim().min(2).max(200), businessName: z.string().trim().min(2).max(300), description: z.string().trim().max(1000).default(""), phone: z.string().trim().min(5).max(50), address: z.string().trim().min(2).max(500), serviceAreas: z.array(z.string().trim().min(2).max(200)).min(1)}).parse(request.body);
  await db.collection("marketplaceSellers").doc(request.user!.uid).set({...input, userId: request.user!.uid, active: true, rating: 0, ratingCount: 0, updatedAt: FieldValue.serverTimestamp(), createdAt: FieldValue.serverTimestamp()}, {merge: true});
  response.json({data: {id: request.user!.uid}});
});

router.get("/marketplace/sellers/:id", async (request, response) => {
  const snapshot = await db.collection("marketplaceSellers").doc(id(request.params.id)).get();
  if (!snapshot.exists || snapshot.get("active") !== true) throw new ApiError(404, "Active seller not found.", "not_found");
  response.json({data: documentJson(snapshot.id, snapshot.data()!)});
});

router.post("/marketplace/listings", authenticate, requireRoles(...sellers), async (request, response) => {
  const input = z.object({type: z.enum(listingTypes), sourceId: z.string().trim().min(1), title: z.string().trim().min(2).max(300), description: z.string().trim().min(2).max(2000), category: z.string().trim().min(2).max(100), conditionOrGrade: z.string().trim().min(1).max(100), quantityAvailable: z.number().int().positive(), unitPrice: z.number().nonnegative(), currency: z.string().trim().length(3).default("SLE"), imageUrls: z.array(z.string().url()).min(1).max(10), deliveryAvailable: z.boolean().default(true)}).parse(request.body);
  const sourceCollection = input.type === "refurbishedDevice" ? "refurbishedInventory" : "recoveredMaterialLots"; const source = await db.collection(sourceCollection).doc(input.sourceId).get();
  if (!source.exists) throw new ApiError(404, "Listing source inventory was not found.", "not_found");
  if (input.type === "recoveredMaterial" && !["salesReady", "reserved"].includes(String(source.get("status")))) throw new ApiError(409, "Recovered material must be sales-ready before listing.", "invalid_state");
  const ref = db.collection("marketplaceListings").doc();
  await ref.set({...input, listingCode: `LST-${ref.id.substring(0, 8).toUpperCase()}`, sellerId: request.user!.uid, reservedQuantity: 0, soldQuantity: 0, status: "active", createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.status(201).json({data: {id: ref.id, listingCode: `LST-${ref.id.substring(0, 8).toUpperCase()}`}});
});

router.patch("/marketplace/listings/:id", authenticate, requireRoles(...sellers), async (request, response) => {
  const input = z.object({title: z.string().trim().min(2).max(300).optional(), description: z.string().trim().min(2).max(2000).optional(), unitPrice: z.number().nonnegative().optional(), quantityAvailable: z.number().int().positive().optional(), imageUrls: z.array(z.string().url()).min(1).max(10).optional(), deliveryAvailable: z.boolean().optional(), status: z.enum(["active", "paused", "closed"]).optional()}).refine((value) => Object.keys(value).length > 0, "At least one field is required.").parse(request.body);
  const listing = await listingRecord(id(request.params.id));
  if (listing.snapshot.get("sellerId") !== request.user!.uid && !["administrator", "superAdministrator"].includes(request.user!.role)) throw new ApiError(403, "Only the listing seller can update it.", "forbidden");
  if (input.quantityAvailable !== undefined && input.quantityAvailable < number(listing.snapshot.get("reservedQuantity")) + number(listing.snapshot.get("soldQuantity"))) throw new ApiError(409, "Available quantity cannot be lower than reserved and sold quantities.", "invalid_quantity");
  await listing.ref.update({...input, updatedAt: FieldValue.serverTimestamp()}); response.json({data: {id: listing.ref.id}});
});

router.post("/marketplace/quotations", authenticate, requireRoles(...buyers), async (request, response) => {
  const input = z.object({listingId: z.string().trim().min(1), quantity: z.number().int().positive(), offeredUnitPrice: z.number().nonnegative(), message: z.string().trim().max(1000).default("")}).parse(request.body);
  const listing = await listingRecord(input.listingId); if (listing.snapshot.get("status") !== "active") throw new ApiError(409, "This listing is not active.", "invalid_state");
  const available = number(listing.snapshot.get("quantityAvailable")) - number(listing.snapshot.get("reservedQuantity")) - number(listing.snapshot.get("soldQuantity")); if (input.quantity > available) throw new ApiError(409, "Requested quantity exceeds available inventory.", "insufficient_inventory");
  const ref = await db.collection("marketplaceQuotations").add({...input, buyerId: request.user!.uid, sellerId: listing.snapshot.get("sellerId"), status: "pending", createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.status(201).json({data: {id: ref.id, status: "pending"}});
});

router.patch("/marketplace/quotations/:id/respond", authenticate, requireRoles(...sellers), async (request, response) => {
  const input = z.object({decision: z.enum(["accepted", "rejected", "countered"]), unitPrice: z.number().nonnegative().optional(), message: z.string().trim().max(1000).default("")}).parse(request.body);
  const ref = db.collection("marketplaceQuotations").doc(id(request.params.id)); const quote = await ref.get(); if (!quote.exists) throw new ApiError(404, "Quotation not found.", "not_found");
  if (quote.get("sellerId") !== request.user!.uid && !["administrator", "superAdministrator"].includes(request.user!.role)) throw new ApiError(403, "Only the seller can respond to this quotation.", "forbidden");
  if (quote.get("status") !== "pending") throw new ApiError(409, "This quotation has already been answered.", "invalid_state");
  await ref.update({status: input.decision, finalUnitPrice: input.unitPrice ?? quote.get("offeredUnitPrice"), responseMessage: input.message, respondedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.json({data: {id: ref.id, status: input.decision}});
});

router.post("/marketplace/orders", authenticate, requireRoles(...buyers), async (request, response) => {
  const input = z.object({listingId: z.string().trim().min(1), quantity: z.number().int().positive(), deliveryAddress: z.string().trim().min(2).max(500), quotationId: z.string().trim().default("")}).parse(request.body);
  const listing = await listingRecord(input.listingId); const ref = db.collection("marketplaceOrders").doc(); let unitPrice = number(listing.snapshot.get("unitPrice"));
  if (input.quotationId) { const quote = await db.collection("marketplaceQuotations").doc(input.quotationId).get(); if (!quote.exists || quote.get("buyerId") !== request.user!.uid || quote.get("listingId") !== input.listingId || quote.get("status") !== "accepted") throw new ApiError(409, "A valid accepted quotation is required.", "invalid_quotation"); unitPrice = number(quote.get("finalUnitPrice")); }
  await db.runTransaction(async (transaction) => { const fresh = await transaction.get(listing.ref); if (fresh.get("status") !== "active") throw new ApiError(409, "This listing is not active.", "invalid_state"); const available = number(fresh.get("quantityAvailable")) - number(fresh.get("reservedQuantity")) - number(fresh.get("soldQuantity")); if (input.quantity > available) throw new ApiError(409, "Requested quantity exceeds available inventory.", "insufficient_inventory"); transaction.update(listing.ref, {reservedQuantity: FieldValue.increment(input.quantity), updatedAt: FieldValue.serverTimestamp()}); transaction.set(ref, {...input, orderNumber: `ORD-${ref.id.substring(0, 10).toUpperCase()}`, buyerId: request.user!.uid, sellerId: fresh.get("sellerId"), unitPrice, subtotal: unitPrice * input.quantity, deliveryFee: 0, total: unitPrice * input.quantity, currency: fresh.get("currency") ?? "SLE", status: "pendingPayment", paymentStatus: "pending", deliveryStatus: "notDispatched", createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}); });
  response.status(201).json({data: {id: ref.id, orderNumber: `ORD-${ref.id.substring(0, 10).toUpperCase()}`, total: unitPrice * input.quantity}});
});

router.get("/marketplace/orders", authenticate, requireRoles(...buyers), async (request, response) => {
  const privileged = ["administrator", "superAdministrator"].includes(request.user!.role); const [buyerOrders, sellerOrders] = privileged ? [await db.collection("marketplaceOrders").limit(500).get(), null] : await Promise.all([db.collection("marketplaceOrders").where("buyerId", "==", request.user!.uid).limit(300).get(), db.collection("marketplaceOrders").where("sellerId", "==", request.user!.uid).limit(300).get()]);
  const docs = [...buyerOrders.docs, ...(sellerOrders?.docs ?? [])]; const unique = new Map(docs.map((doc) => [doc.id, documentJson(doc.id, doc.data())])); response.json({data: [...unique.values()]});
});

router.get("/marketplace/orders/:id", authenticate, requireRoles(...buyers), async (request, response) => {
  const order = await orderRecord(id(request.params.id)); if (!orderAccess(order.snapshot.data()!, request.user!.uid, request.user!.role)) throw new ApiError(403, "You cannot access this order.", "forbidden"); response.json({data: documentJson(order.snapshot.id, order.snapshot.data()!)});
});

router.patch("/marketplace/orders/:id/payment", authenticate, requireRoles(...managers), async (request, response) => {
  const input = z.object({status: z.enum(["confirmed", "failed", "refunded"]), transactionReference: z.string().trim().min(1).max(200), paymentMethod: z.enum(["mobileMoney", "bank", "card", "cash"])}).parse(request.body); const order = await orderRecord(id(request.params.id));
  if (!["pending", "failed"].includes(String(order.snapshot.get("paymentStatus"))) && input.status === "confirmed") throw new ApiError(409, "Payment cannot be confirmed in the current state.", "invalid_state");
  await order.ref.update({paymentStatus: input.status, transactionReference: input.transactionReference, paymentMethod: input.paymentMethod, status: input.status === "confirmed" ? "confirmed" : order.snapshot.get("status"), paymentUpdatedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}); response.json({data: {id: order.ref.id, paymentStatus: input.status}});
});

router.patch("/marketplace/orders/:id/delivery", authenticate, requireRoles(...sellers), async (request, response) => {
  const input = z.object({status: z.enum(["processing", "dispatched", "inTransit", "delivered"]), carrier: z.string().trim().max(200).default(""), trackingNumber: z.string().trim().max(200).default(""), proofUrls: z.array(z.string().url()).max(10).default([])}).parse(request.body); const order = await orderRecord(id(request.params.id));
  if (order.snapshot.get("sellerId") !== request.user!.uid && !["administrator", "superAdministrator"].includes(request.user!.role)) throw new ApiError(403, "Only the seller can update delivery.", "forbidden"); if (order.snapshot.get("paymentStatus") !== "confirmed") throw new ApiError(409, "Payment must be confirmed before delivery.", "invalid_state");
  await order.ref.update({deliveryStatus: input.status, carrier: input.carrier, trackingNumber: input.trackingNumber, deliveryProofUrls: input.proofUrls, status: input.status === "delivered" ? "delivered" : "fulfilling", deliveryUpdatedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}); response.json({data: {id: order.ref.id, deliveryStatus: input.status}});
});

router.patch("/marketplace/orders/:id/confirm-receipt", authenticate, requireRoles(...buyers), async (request, response) => {
  const order = await orderRecord(id(request.params.id)); if (order.snapshot.get("buyerId") !== request.user!.uid) throw new ApiError(403, "Only the buyer can confirm receipt.", "forbidden"); if (order.snapshot.get("deliveryStatus") !== "delivered") throw new ApiError(409, "Delivery must be completed first.", "invalid_state");
  const listing = db.collection("marketplaceListings").doc(String(order.snapshot.get("listingId"))); const batch = db.batch(); batch.update(order.ref, {status: "completed", receiptConfirmedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}); batch.update(listing, {reservedQuantity: FieldValue.increment(-number(order.snapshot.get("quantity"))), soldQuantity: FieldValue.increment(number(order.snapshot.get("quantity"))), updatedAt: FieldValue.serverTimestamp()}); await batch.commit(); response.json({data: {id: order.ref.id, status: "completed"}});
});

router.patch("/marketplace/orders/:id/cancel", authenticate, requireRoles(...buyers), async (request, response) => {
  const input = z.object({reason: z.string().trim().min(2).max(1000)}).parse(request.body); const order = await orderRecord(id(request.params.id)); if (order.snapshot.get("buyerId") !== request.user!.uid && !["administrator", "superAdministrator"].includes(request.user!.role)) throw new ApiError(403, "You cannot cancel this order.", "forbidden"); if (!["pendingPayment", "confirmed"].includes(String(order.snapshot.get("status")))) throw new ApiError(409, "This order can no longer be cancelled.", "invalid_state");
  const listing = db.collection("marketplaceListings").doc(String(order.snapshot.get("listingId"))); const batch = db.batch(); batch.update(order.ref, {status: "cancelled", cancellationReason: input.reason, cancelledBy: request.user!.uid, cancelledAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}); batch.update(listing, {reservedQuantity: FieldValue.increment(-number(order.snapshot.get("quantity"))), updatedAt: FieldValue.serverTimestamp()}); await batch.commit(); response.json({data: {id: order.ref.id, status: "cancelled"}});
});

router.get("/marketplace/orders/:id/receipt", authenticate, requireRoles(...buyers), async (request, response) => {
  const order = await orderRecord(id(request.params.id)); if (!orderAccess(order.snapshot.data()!, request.user!.uid, request.user!.role)) throw new ApiError(403, "You cannot access this receipt.", "forbidden"); if (!order.snapshot.get("transactionReference")) throw new ApiError(409, "A receipt is available after payment confirmation.", "invalid_state"); response.json({data: {receiptNumber: `RCT-${order.ref.id.substring(0, 10).toUpperCase()}`, issuedAt: new Date().toISOString(), order: documentJson(order.snapshot.id, order.snapshot.data()!)}});
});

router.post("/marketplace/orders/:id/reviews", authenticate, requireRoles(...buyers), async (request, response) => {
  const input = z.object({rating: z.number().int().min(1).max(5), comments: z.string().trim().max(1000).default("")}).parse(request.body); const order = await orderRecord(id(request.params.id)); if (order.snapshot.get("buyerId") !== request.user!.uid || order.snapshot.get("status") !== "completed") throw new ApiError(409, "Only the buyer can review a completed order.", "invalid_state");
  const existing = await db.collection("marketplaceReviews").where("orderId", "==", order.ref.id).limit(1).get(); if (!existing.empty) throw new ApiError(409, "This order has already been reviewed.", "conflict");
  const sellerRef = db.collection("marketplaceSellers").doc(String(order.snapshot.get("sellerId"))); const seller = await sellerRef.get(); const count = number(seller.get("ratingCount")); const rating = (number(seller.get("rating")) * count + input.rating) / (count + 1); const ref = db.collection("marketplaceReviews").doc(); const batch = db.batch(); batch.set(ref, {...input, orderId: order.ref.id, listingId: order.snapshot.get("listingId"), buyerId: request.user!.uid, sellerId: order.snapshot.get("sellerId"), createdAt: FieldValue.serverTimestamp()}); batch.set(sellerRef, {rating, ratingCount: count + 1, updatedAt: FieldValue.serverTimestamp()}, {merge: true}); await batch.commit(); response.status(201).json({data: {id: ref.id, sellerRating: rating}});
});

router.get("/marketplace/reports/summary", authenticate, requireRoles(...managers), async (_request, response) => {
  const [listings, orders, buyersSnapshot, sellersSnapshot] = await Promise.all([db.collection("marketplaceListings").limit(1000).get(), db.collection("marketplaceOrders").limit(1000).get(), db.collection("marketplaceBuyers").limit(1000).get(), db.collection("marketplaceSellers").limit(1000).get()]); const byStatus: Record<string, number> = {}; const byType: Record<string, number> = {}; let revenue = 0; let completed = 0;
  for (const doc of listings.docs) { const type = String(doc.get("type") ?? "unknown"); byType[type] = (byType[type] ?? 0) + 1; } for (const doc of orders.docs) { const status = String(doc.get("status") ?? "unknown"); byStatus[status] = (byStatus[status] ?? 0) + 1; if (status === "completed") {completed++; revenue += number(doc.get("total"));} }
  response.json({data: {activeListings: listings.docs.filter((doc) => doc.get("status") === "active").length, totalOrders: orders.size, completedOrders: completed, grossMarketplaceValue: revenue, registeredBuyers: buyersSnapshot.size, registeredSellers: sellersSnapshot.size, byStatus, byType}});
});

export default router;
