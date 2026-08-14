import {Router} from "express";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {z} from "zod";
import {authenticate, requireRoles} from "./auth.js";
import {ApiError} from "./errors.js";
import {db} from "./firebase.js";
import {documentJson} from "./firestore-json.js";
import {publishNotificationEvent} from "./push-events.js";

const router = Router();
const administrators = ["administrator", "superAdministrator"] as const;
const operationalRoles = [
  "administrator",
  "superAdministrator",
  "collector",
  "driver",
  "environmentalOfficer",
] as const;

const pickupStatuses = [
  "draft",
  "submitted",
  "approved",
  "assigned",
  "scheduled",
  "inProgress",
  "collected",
  "cancelled",
  "failed",
  "completed",
] as const;
type PickupStatus = (typeof pickupStatuses)[number];

const wasteCategory = z.enum([
  "computers",
  "phones",
  "televisions",
  "appliances",
  "batteries",
  "accessories",
  "networkingEquipment",
  "industrialElectronics",
  "other",
]);

const pickupFields = {
  category: wasteCategory,
  quantity: z.number().int().positive(),
  estimatedWeight: z.number().nonnegative(),
  condition: z.string().trim().min(1).max(100),
  location: z.string().trim().min(2).max(300),
  scheduledAt: z.coerce.date(),
  urgent: z.boolean().default(false),
  instructions: z.string().trim().max(1000).default(""),
  latitude: z.number().min(-90).max(90).nullable().optional(),
  longitude: z.number().min(-180).max(180).nullable().optional(),
  photoUrls: z.array(z.string().url()).max(5).default([]),
};

const createSchema = z.object({
  ...pickupFields,
  status: z.enum(["draft", "submitted"]).default("submitted"),
}).superRefine((input, context) => {
  if (input.status === "submitted" && input.photoUrls.length === 0) {
    context.addIssue({
      code: "custom",
      path: ["photoUrls"],
      message: "At least one item photo is required before submission.",
    });
  }
  if ((input.latitude == null) !== (input.longitude == null)) {
    context.addIssue({
      code: "custom",
      path: ["latitude"],
      message: "Latitude and longitude must be supplied together.",
    });
  }
  if (input.scheduledAt.getTime() <= Date.now()) {
    context.addIssue({
      code: "custom",
      path: ["scheduledAt"],
      message: "The pickup date and time must be in the future.",
    });
  }
});

const draftUpdateSchema = z.object({
  category: pickupFields.category.optional(),
  quantity: pickupFields.quantity.optional(),
  estimatedWeight: pickupFields.estimatedWeight.optional(),
  condition: pickupFields.condition.optional(),
  location: pickupFields.location.optional(),
  scheduledAt: pickupFields.scheduledAt.optional(),
  urgent: z.boolean().optional(),
  instructions: z.string().trim().max(1000).optional(),
  latitude: pickupFields.latitude,
  longitude: pickupFields.longitude,
  photoUrls: pickupFields.photoUrls.optional(),
}).refine((input) => Object.keys(input).length > 0, {
  message: "At least one field must be supplied.",
});

const allowedTransitions: Record<PickupStatus, readonly PickupStatus[]> = {
  draft: ["submitted", "cancelled"],
  submitted: ["approved", "cancelled", "failed"],
  approved: ["assigned", "cancelled", "failed"],
  assigned: ["scheduled", "cancelled", "failed"],
  scheduled: ["inProgress", "cancelled", "failed"],
  inProgress: ["collected", "failed"],
  collected: ["completed", "failed"],
  cancelled: [],
  failed: ["submitted", "cancelled"],
  completed: [],
};

function idParameter(value: string | string[]): string {
  return Array.isArray(value) ? value[0] : value;
}

async function calculateFee(input: {
  quantity: number;
  estimatedWeight: number;
  urgent: boolean;
}) {
  const settings = await db.collection("systemSettings").doc("billing").get();
  const baseRate = Number(settings.get("pickupBaseFee") ?? 2);
  const weightRate = Number(settings.get("pickupWeightRate") ?? 0.75);
  const urgentRate = Number(settings.get("urgentPickupFee") ?? 15);
  const effectiveBaseRate = Number.isFinite(baseRate) ? baseRate : 2;
  const effectiveWeightRate = Number.isFinite(weightRate) ? weightRate : 0.75;
  const effectiveUrgentRate = Number.isFinite(urgentRate) ? urgentRate : 15;
  const baseFee = input.quantity * effectiveBaseRate;
  const weightFee = input.estimatedWeight * effectiveWeightRate;
  const urgentFee = input.urgent ?
    effectiveUrgentRate : 0;
  const total = Math.round((baseFee + weightFee + urgentFee) * 100) / 100;
  return {
    currency: "SLE",
    rates: {
      basePerItem: effectiveBaseRate,
      perKg: effectiveWeightRate,
      urgent: effectiveUrgentRate,
    },
    baseFee,
    weightFee,
    urgentFee,
    total,
  };
}

async function pickupForAccess(id: string, uid: string, role: string) {
  const reference = db.collection("pickupRequests").doc(id);
  const snapshot = await reference.get();
  if (!snapshot.exists) {
    throw new ApiError(404, "Pickup request not found.", "not_found");
  }
  const privileged = operationalRoles.some((candidate) => candidate === role);
  if (!privileged && snapshot.get("userId") !== uid) {
    throw new ApiError(403, "You cannot access this pickup request.", "forbidden");
  }
  return {reference, snapshot};
}

async function customerPickup(id: string, uid: string, role: string) {
  const result = await pickupForAccess(id, uid, role);
  const administrator = administrators.some((candidate) => candidate === role);
  if (!administrator && result.snapshot.get("userId") !== uid) {
    throw new ApiError(403, "You cannot modify this pickup request.", "forbidden");
  }
  return result;
}

async function appendStatus(
  reference: FirebaseFirestore.DocumentReference,
  from: PickupStatus,
  to: PickupStatus,
  actorId: string,
  reason = "",
  additional: Record<string, unknown> = {},
) {
  if (!allowedTransitions[from]?.includes(to)) {
    throw new ApiError(
      409,
      `Pickup status cannot change from ${from} to ${to}.`,
      "invalid_status_transition",
    );
  }
  const changedAt = Timestamp.now();
  const event = {from, to, actorId, reason, changedAt};
  const batch = db.batch();
  batch.update(reference, {
    status: to,
    ...additional,
    statusHistory: FieldValue.arrayUnion(event),
    updatedAt: FieldValue.serverTimestamp(),
  });
  batch.set(reference.collection("events").doc(), {
    type: "statusChanged",
    ...event,
    createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
}

router.post("/pickup-requests/estimate-fee", authenticate, async (request, response) => {
  const input = z.object({
    quantity: z.number().int().positive(),
    estimatedWeight: z.number().nonnegative(),
    urgent: z.boolean().default(false),
  }).parse(request.body);
  response.json({data: await calculateFee(input)});
});

router.get("/pickup-requests", authenticate, async (request, response) => {
  const filters = z.object({
    status: z.enum(pickupStatuses).optional(),
    category: wasteCategory.optional(),
    urgent: z.enum(["true", "false"]).optional(),
    limit: z.coerce.number().int().min(1).max(200).default(100),
  }).parse(request.query);
  const privileged = operationalRoles.some(
    (candidate) => candidate === request.user!.role,
  );
  let query: FirebaseFirestore.Query = privileged
    ? db.collection("pickupRequests")
    : db.collection("pickupRequests").where("userId", "==", request.user!.uid);
  if (filters.status) query = query.where("status", "==", filters.status);
  if (filters.category) query = query.where("category", "==", filters.category);
  if (filters.urgent) query = query.where("urgent", "==", filters.urgent === "true");
  const snapshot = await query.limit(filters.limit).get();
  response.json({
    data: snapshot.docs
      .map((document) => documentJson(document.id, document.data()))
      .sort((a, b) => String(b.createdAt ?? "").localeCompare(String(a.createdAt ?? ""))),
  });
});

router.post("/pickup-requests", authenticate, async (request, response) => {
  const input = createSchema.parse(request.body);
  const fee = await calculateFee(input);
  const reference = db.collection("pickupRequests").doc();
  const now = Timestamp.now();
  const initialEvent = {
    from: null,
    to: input.status,
    actorId: request.user!.uid,
    reason: input.status === "draft" ? "Draft created" : "Pickup submitted",
    changedAt: now,
  };
  const batch = db.batch();
  batch.set(reference, {
    ...input,
    userId: request.user!.uid,
    scheduledAt: Timestamp.fromDate(input.scheduledAt),
    estimatedFee: fee.total,
    feeBreakdown: fee,
    statusHistory: [initialEvent],
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  batch.set(reference.collection("events").doc(), {
    type: input.status === "draft" ? "draftCreated" : "submitted",
    ...initialEvent,
    createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  if (input.status === "submitted") {
    void publishNotificationEvent({
      event: "pickup_request_submitted",
      data: {pickupId: reference.id, customerId: request.user!.uid},
    });
  }
  response.status(201).json({
    data: {id: reference.id, status: input.status, estimatedFee: fee.total, fee},
  });
});

router.get("/pickup-requests/:id", authenticate, async (request, response) => {
  const {snapshot} = await pickupForAccess(
    idParameter(request.params.id), request.user!.uid, request.user!.role,
  );
  response.json({data: documentJson(snapshot.id, snapshot.data()!)});
});

router.get("/pickup-requests/:id/history", authenticate, async (request, response) => {
  const {reference, snapshot} = await pickupForAccess(
    idParameter(request.params.id), request.user!.uid, request.user!.role,
  );
  const events = await reference.collection("events").orderBy("createdAt", "asc").get();
  response.json({
    data: {
      pickupId: reference.id,
      currentStatus: snapshot.get("status"),
      events: events.docs.map((event) => documentJson(event.id, event.data())),
    },
  });
});

router.patch("/pickup-requests/:id", authenticate, async (request, response) => {
  const input = draftUpdateSchema.parse(request.body);
  const {reference, snapshot} = await customerPickup(
    idParameter(request.params.id), request.user!.uid, request.user!.role,
  );
  if (snapshot.get("status") !== "draft") {
    throw new ApiError(409, "Only draft pickup requests can be edited.", "not_draft");
  }
  const update: Record<string, unknown> = {...input, updatedAt: FieldValue.serverTimestamp()};
  if (input.scheduledAt) update.scheduledAt = Timestamp.fromDate(input.scheduledAt);
  const combined = {...snapshot.data(), ...input};
  const fee = await calculateFee({
    quantity: Number(combined.quantity),
    estimatedWeight: Number(combined.estimatedWeight),
    urgent: Boolean(combined.urgent),
  });
  update.estimatedFee = fee.total;
  update.feeBreakdown = fee;
  await reference.update(update);
  response.json({data: {id: reference.id, status: "draft", fee}});
});

// Confirming a draft into a submitted pickup requires its pickup fee to have
// actually been paid — see the pickupFee payment flow in payment-routes.ts,
// which is the normal path into this state. This check exists so nothing
// (including a direct API call) can bypass payment by hitting this endpoint.
async function requirePickupPaid(pickupId: string): Promise<void> {
  const paid = await db.collection("paymentTransactions")
    .where("referenceId", "==", pickupId)
    .where("purpose", "==", "pickupFee")
    .where("status", "==", "confirmed")
    .limit(1).get();
  if (paid.empty) {
    throw new ApiError(402, "Payment is required before this pickup request can be confirmed.", "payment_required");
  }
}

router.post("/pickup-requests/:id/confirm", authenticate, async (request, response) => {
  const {reference, snapshot} = await customerPickup(
    idParameter(request.params.id), request.user!.uid, request.user!.role,
  );
  if (snapshot.get("status") !== "draft") {
    throw new ApiError(409, "Only a draft can be confirmed.", "not_draft");
  }
  const photos = snapshot.get("photoUrls") ?? [];
  if (!Array.isArray(photos) || photos.length === 0) {
    throw new ApiError(409, "At least one item photo is required.", "photo_required");
  }
  await requirePickupPaid(reference.id);
  await appendStatus(reference, "draft", "submitted", request.user!.uid, "Pickup confirmed");
  void publishNotificationEvent({
    event: "pickup_request_submitted",
    data: {pickupId: reference.id, customerId: request.user!.uid},
  });
  response.json({data: {id: reference.id, status: "submitted"}});
});

// Called from the Monime webhook handler once a pickupFee payment is
// confirmed, to auto-advance the draft pickup it belongs to. Does not
// re-check payment status (the caller just confirmed it) and is a no-op if
// the pickup is missing or already past the draft stage, so a retried
// webhook delivery can never double-submit or error.
export async function confirmPickupAfterPayment(pickupId: string): Promise<void> {
  const reference = db.collection("pickupRequests").doc(pickupId);
  const snapshot = await reference.get();
  if (!snapshot.exists || snapshot.get("status") !== "draft") return;
  const photos = snapshot.get("photoUrls") ?? [];
  if (!Array.isArray(photos) || photos.length === 0) {
    console.error(`Pickup ${pickupId} was paid but has no photos; leaving it as a draft.`);
    return;
  }
  await appendStatus(reference, "draft", "submitted", String(snapshot.get("userId") ?? ""), "Payment confirmed");
  void publishNotificationEvent({
    event: "pickup_request_submitted",
    data: {pickupId: reference.id, customerId: String(snapshot.get("userId") ?? "")},
  });
}

router.patch("/pickup-requests/:id/cancel", authenticate, async (request, response) => {
  const input = z.object({reason: z.string().trim().max(500).default("")}).parse(request.body);
  const {reference, snapshot} = await customerPickup(
    idParameter(request.params.id), request.user!.uid, request.user!.role,
  );
  const from = z.enum(pickupStatuses).parse(snapshot.get("status"));
  await appendStatus(reference, from, "cancelled", request.user!.uid, input.reason, {
    cancelledAt: FieldValue.serverTimestamp(),
    cancellationReason: input.reason,
  });
  void publishNotificationEvent({
    event: "pickup_cancelled",
    recipientId: String(snapshot.get("userId")),
    data: {pickupId: reference.id, reason: input.reason},
  });
  response.json({data: {id: reference.id, status: "cancelled"}});
});

router.patch("/pickup-requests/:id/reschedule", authenticate, async (request, response) => {
  const input = z.object({
    scheduledAt: z.coerce.date().refine(
      (value) => value.getTime() > Date.now(),
      "The pickup date and time must be in the future.",
    ),
    reason: z.string().trim().max(500).default(""),
  }).parse(request.body);
  const {reference, snapshot} = await customerPickup(
    idParameter(request.params.id), request.user!.uid, request.user!.role,
  );
  const status = z.enum(pickupStatuses).parse(snapshot.get("status"));
  if (!["submitted", "approved", "assigned", "scheduled", "failed"].includes(status)) {
    throw new ApiError(409, "This pickup can no longer be rescheduled.", "not_reschedulable");
  }
  const nextStatus: PickupStatus = status === "failed" ? "submitted" : status;
  const changedAt = Timestamp.now();
  const event = {
    type: "rescheduled",
    from: status,
    to: nextStatus,
    actorId: request.user!.uid,
    reason: input.reason,
    scheduledAt: Timestamp.fromDate(input.scheduledAt),
    changedAt,
  };
  const batch = db.batch();
  batch.update(reference, {
    scheduledAt: Timestamp.fromDate(input.scheduledAt),
    status: nextStatus,
    rescheduledAt: FieldValue.serverTimestamp(),
    rescheduleReason: input.reason,
    statusHistory: FieldValue.arrayUnion(event),
    updatedAt: FieldValue.serverTimestamp(),
  });
  batch.set(reference.collection("events").doc(), {
    ...event,
    createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  void publishNotificationEvent({
    event: "pickup_rescheduled",
    recipientId: String(snapshot.get("userId")),
    data: {pickupId: reference.id, scheduledAt: input.scheduledAt.toISOString()},
  });
  response.json({data: {id: reference.id, status: nextStatus, scheduledAt: input.scheduledAt}});
});

router.patch(
  "/pickup-requests/:id/status",
  authenticate,
  requireRoles(...administrators),
  async (request, response) => {
    const input = z.object({
      status: z.enum(pickupStatuses),
      reason: z.string().trim().max(500).default(""),
    }).parse(request.body);
    const {reference, snapshot} = await pickupForAccess(
      idParameter(request.params.id), request.user!.uid, request.user!.role,
    );
    const from = z.enum(pickupStatuses).parse(snapshot.get("status"));
    await appendStatus(reference, from, input.status, request.user!.uid, input.reason);
    const event = input.status === "approved" ? "pickup_accepted" :
      input.status === "completed" ? "pickup_completed" :
      input.status === "failed" ? "pickup_failed" : "pickup_status_updated";
    void publishNotificationEvent({
      event,
      recipientId: String(snapshot.get("userId")),
      data: {pickupId: reference.id, status: input.status, reason: input.reason},
    });
    response.json({data: {id: reference.id, status: input.status}});
  },
);

router.patch(
  "/pickup-requests/:id/approve",
  authenticate,
  requireRoles(...administrators),
  async (request, response) => {
    const input = z.object({note: z.string().trim().max(500).default("")}).parse(request.body);
    const {reference, snapshot} = await pickupForAccess(
      idParameter(request.params.id), request.user!.uid, request.user!.role,
    );
    const from = z.enum(pickupStatuses).parse(snapshot.get("status"));
    await appendStatus(reference, from, "approved", request.user!.uid, input.note, {
      approvedAt: FieldValue.serverTimestamp(),
      approvedBy: request.user!.uid,
    });
    void publishNotificationEvent({
      event: "pickup_accepted",
      recipientId: String(snapshot.get("userId")),
      data: {pickupId: reference.id},
    });
    response.json({data: {id: reference.id, status: "approved"}});
  },
);

router.patch("/pickup-requests/:id/rating", authenticate, async (request, response) => {
  const input = z.object({
    rating: z.number().int().min(1).max(5),
    comment: z.string().trim().max(1000).default(""),
  }).parse(request.body);
  const {reference, snapshot} = await customerPickup(
    idParameter(request.params.id), request.user!.uid, request.user!.role,
  );
  if (snapshot.get("status") !== "completed") {
    throw new ApiError(409, "Only completed pickups can be rated.", "pickup_not_completed");
  }
  if (snapshot.get("rating") != null) {
    throw new ApiError(409, "This pickup has already been rated.", "already_rated");
  }
  const batch = db.batch();
  batch.update(reference, {
    rating: input.rating,
    ratingComment: input.comment,
    ratedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  batch.set(reference.collection("events").doc(), {
    type: "rated",
    rating: input.rating,
    comment: input.comment,
    actorId: request.user!.uid,
    createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  response.json({data: {id: reference.id, rating: input.rating, comment: input.comment}});
});

export default router;
