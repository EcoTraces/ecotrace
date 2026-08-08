import { Router } from "express";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { z } from "zod";
import { authenticate, requireRoles } from "./auth.js";
import { db } from "./firebase.js";
import { documentJson } from "./firestore-json.js";
import { seedDemoData } from "./demo-data.js";
import routeRoutes from "./route-routes.js";
import centreRoutes from "./centre-routes.js";
import inventoryRoutes from "./inventory-routes.js";
import mediaRoutes from "./media-routes.js";
import repairRoutes from "./repair-routes.js";
import recyclingRoutes from "./recycling-routes.js";
import recoveryRoutes from "./recovery-routes.js";
import hazardousRoutes from "./hazardous-routes.js";
import reverseLogisticsRoutes from "./reverse-logistics-routes.js";
import partnerRoutes from "./partner-routes.js";
import marketplaceRoutes from "./marketplace-routes.js";
import donationRoutes from "./donation-routes.js";
import rewardRoutes from "./reward-routes.js";
import paymentRoutes from "./payment-routes.js";
import impactRoutes from "./impact-routes.js";
import analyticsRoutes from "./analytics-routes.js";
import reportRoutes from "./report-routes.js";
import communicationRoutes from "./communication-routes.js";
import supportRoutes from "./support-routes.js";
import complianceRoutes from "./compliance-routes.js";
import incidentRoutes from "./incident-routes.js";
import documentRoutes from "./document-routes.js";
import auditRoutes, {auditMutations} from "./audit-routes.js";
import administrationRoutes from "./administration-routes.js";
import identityRoutes from "./identity-routes.js";
import organizationRoutes from "./organization-routes.js";
import { publishNotificationEvent } from "./push-events.js";

const router = Router();
router.use(auditMutations);
router.use(routeRoutes);
router.use(centreRoutes);
router.use(inventoryRoutes);
router.use(mediaRoutes);
router.use(repairRoutes);
router.use(recyclingRoutes);
router.use(recoveryRoutes);
router.use(hazardousRoutes);
router.use(reverseLogisticsRoutes);
router.use(partnerRoutes);
router.use(marketplaceRoutes);
router.use(donationRoutes);
router.use(rewardRoutes);
router.use(paymentRoutes);
router.use(impactRoutes);
router.use(analyticsRoutes);
router.use(reportRoutes);
router.use(communicationRoutes);
router.use(supportRoutes);
router.use(complianceRoutes);
router.use(incidentRoutes);
router.use(documentRoutes);
router.use(auditRoutes);
router.use(administrationRoutes);
router.use(identityRoutes);
router.use(organizationRoutes);
const administrators = ["administrator", "superAdministrator"] as const;

const centreSchema = z.object({
  name: z.string().trim().min(2).max(120),
  address: z.string().trim().min(2).max(300),
  contactName: z.string().trim().max(120).default(""),
  contactEmail: z.string().trim().email().or(z.literal("")),
  contactPhone: z.string().trim().max(40).default(""),
  latitude: z.number().min(-90).max(90).nullable().optional(),
  longitude: z.number().min(-180).max(180).nullable().optional(),
  operatingHours: z.record(z.string(), z.string()).default({}),
  supportedCategories: z
    .array(
      z.enum([
        "computers",
        "phones",
        "televisions",
        "appliances",
        "batteries",
        "accessories",
        "other",
      ]),
    )
    .default([]),
  capacityKg: z.number().positive(),
  capacityAlertPercent: z.number().min(1).max(100).default(80),
});

const vehicleSchema = z.object({
  registrationNumber: z.string().trim().min(2).max(30),
  type: z.enum([
    "van",
    "truck",
    "pickupTruck",
    "motorcycle",
    "specializedHazardous",
  ]),
  capacityKg: z.number().positive(),
  driverId: z.string().trim().default(""),
  insuranceExpiry: z.coerce.date(),
  licenceExpiry: z.coerce.date(),
});

const pickupSchema = z.object({
  category: z.enum([
    "computers",
    "phones",
    "televisions",
    "appliances",
    "batteries",
    "accessories",
    "other",
  ]),
  quantity: z.number().int().positive(),
  estimatedWeight: z.number().positive(),
  condition: z.string().trim().min(1).max(100),
  location: z.string().trim().min(2).max(300),
  scheduledAt: z.coerce.date(),
  urgent: z.boolean().default(false),
  instructions: z.string().trim().max(1000).default(""),
  latitude: z.number().min(-90).max(90).nullable().optional(),
  longitude: z.number().min(-180).max(180).nullable().optional(),
  photoUrls: z.array(z.string().url()).min(1).max(5),
});

const scheduleSchema = z.object({
  scheduledAt: z.coerce.date(),
  pickupIds: z.array(z.string().trim().min(1)).min(1),
  collectorIds: z.array(z.string().trim().min(1)).default([]),
  driverId: z.string().trim().min(1),
  vehicleId: z.string().trim().min(1),
  priority: z.enum(["normal", "high", "urgent"]),
  serviceArea: z.string().trim().min(2).max(200),
});

const dispatchSupervisors = ["administrator", "superAdministrator"] as const;
const dispatchOperators = [
  "administrator",
  "superAdministrator",
  "collector",
  "driver",
] as const;

router.get("/me", authenticate, async (request, response) => {
  const profile = await db.collection("users").doc(request.user!.uid).get();
  response.json({
    data: {
      uid: request.user!.uid,
      email: request.user!.email,
      role: request.user!.role,
      profile: profile.exists
        ? documentJson(profile.id, profile.data()!)
        : null,
    },
  });
});

router.post(
  "/admin/demo-data",
  authenticate,
  requireRoles(...administrators),
  async (request, response) => {
    const result = await seedDemoData(request.user!.uid);
    response.json({ data: result });
  },
);

// Public directory: only active centres and non-sensitive operational fields.
router.get("/collection-centres", async (_request, response) => {
  const snapshot = await db
    .collection("collectionCentres")
    .where("active", "==", true)
    .get();
  const data = snapshot.docs
    .map((document) => {
      const centre = document.data();
      return documentJson(document.id, {
        name: centre.name ?? "",
        address: centre.address ?? "",
        contactEmail: centre.contactEmail ?? "",
        contactPhone: centre.contactPhone ?? "",
        latitude: centre.latitude ?? null,
        longitude: centre.longitude ?? null,
        operatingHours: centre.operatingHours ?? {},
        supportedCategories: centre.supportedCategories ?? [],
        capacityKg: centre.capacityKg ?? 0,
        currentStockKg: centre.currentStockKg ?? 0,
        capacityAlertPercent: centre.capacityAlertPercent ?? 80,
        active: true,
      });
    })
    .sort((a, b) => String(a.name).localeCompare(String(b.name)));
  response.json({ data });
});

router.post(
  "/collection-centres",
  authenticate,
  requireRoles(...administrators),
  async (request, response) => {
    const input = centreSchema.parse(request.body);
    const reference = await db.collection("collectionCentres").add({
      ...input,
      currentStockKg: 0,
      staffIds: [],
      active: true,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      createdBy: request.user!.uid,
    });
    response.status(201).json({ data: { id: reference.id } });
  },
);

router.get("/vehicles", authenticate, async (request, response) => {
  let query: FirebaseFirestore.Query = db.collection("vehicles");
  if (typeof request.query.availability === "string") {
    query = query.where("availability", "==", request.query.availability);
  }
  const snapshot = await query.get();
  const data = snapshot.docs
    .map((document) => documentJson(document.id, document.data()))
    .sort((a, b) =>
      String(a.registrationNumber).localeCompare(String(b.registrationNumber)),
    );
  response.json({ data });
});

router.post(
  "/vehicles",
  authenticate,
  requireRoles(...administrators),
  async (request, response) => {
    const input = vehicleSchema.parse(request.body);
    const reference = db.collection("vehicles").doc();
    const batch = db.batch();
    batch.set(reference, {
      ...input,
      registrationNumber: input.registrationNumber.toUpperCase(),
      insuranceExpiry: Timestamp.fromDate(input.insuranceExpiry),
      licenceExpiry: Timestamp.fromDate(input.licenceExpiry),
      availability: "available",
      mileageKm: 0,
      fuelLitres: 0,
      latitude: null,
      longitude: null,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      createdBy: request.user!.uid,
    });
    batch.set(reference.collection("events").doc(), {
      type: "registered",
      details: "Vehicle registered through API",
      createdAt: FieldValue.serverTimestamp(),
      actorId: request.user!.uid,
    });
    await batch.commit();
    response.status(201).json({ data: { id: reference.id } });
  },
);

router.get("/pickup-requests", authenticate, async (request, response) => {
  const privileged = [
    "administrator",
    "superAdministrator",
    "collector",
    "driver",
  ].includes(request.user!.role);
  const query = privileged
    ? db.collection("pickupRequests")
    : db.collection("pickupRequests").where("userId", "==", request.user!.uid);
  const snapshot = await query.limit(200).get();
  response.json({
    data: snapshot.docs.map((document) =>
      documentJson(document.id, document.data()),
    ),
  });
});

router.post("/pickup-requests", authenticate, async (request, response) => {
  const input = pickupSchema.parse(request.body);
  const fee =
    input.quantity * 2 + input.estimatedWeight * 0.75 + (input.urgent ? 15 : 0);
  const reference = await db.collection("pickupRequests").add({
    ...input,
    userId: request.user!.uid,
    scheduledAt: Timestamp.fromDate(input.scheduledAt),
    estimatedFee: fee,
    photoUrls: input.photoUrls,
    status: "submitted",
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  void publishNotificationEvent({
    event: "pickup_request_submitted",
    data: { pickupId: reference.id, customerId: request.user!.uid },
  });
  response.status(201).json({ data: { id: reference.id, estimatedFee: fee } });
});

async function requirePickupAccess(id: string, uid: string, role: string) {
  const reference = db.collection("pickupRequests").doc(id);
  const snapshot = await reference.get();
  if (!snapshot.exists) {
    const { ApiError } = await import("./errors.js");
    throw new ApiError(404, "Pickup request not found.", "not_found");
  }
  const privileged = ["administrator", "superAdministrator"].includes(role);
  if (!privileged && snapshot.get("userId") !== uid) {
    const { ApiError } = await import("./errors.js");
    throw new ApiError(
      403,
      "You cannot modify this pickup request.",
      "forbidden",
    );
  }
  return reference;
}

function routeParameter(value: string | string[]): string {
  return Array.isArray(value) ? value[0] : value;
}

router.patch(
  "/pickup-requests/:id/cancel",
  authenticate,
  async (request, response) => {
    const reference = await requirePickupAccess(
      routeParameter(request.params.id),
      request.user!.uid,
      request.user!.role,
    );
    await reference.update({
      status: "cancelled",
      updatedAt: FieldValue.serverTimestamp(),
    });
    response.json({ data: { id: reference.id, status: "cancelled" } });
  },
);

router.patch(
  "/pickup-requests/:id/reschedule",
  authenticate,
  async (request, response) => {
    const input = z
      .object({ scheduledAt: z.coerce.date() })
      .parse(request.body);
    const reference = await requirePickupAccess(
      routeParameter(request.params.id),
      request.user!.uid,
      request.user!.role,
    );
    await reference.update({
      scheduledAt: Timestamp.fromDate(input.scheduledAt),
      status: "submitted",
      updatedAt: FieldValue.serverTimestamp(),
    });
    response.json({ data: { id: reference.id, status: "submitted" } });
  },
);

router.patch(
  "/pickup-requests/:id/rating",
  authenticate,
  async (request, response) => {
    const input = z
      .object({ rating: z.number().int().min(1).max(5) })
      .parse(request.body);
    const reference = await requirePickupAccess(
      routeParameter(request.params.id),
      request.user!.uid,
      request.user!.role,
    );
    await reference.update({
      rating: input.rating,
      ratedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    response.json({ data: { id: reference.id, rating: input.rating } });
  },
);

router.get(
  "/dispatch/schedules",
  authenticate,
  requireRoles(...dispatchOperators),
  async (request, response) => {
    const range = z
      .object({ from: z.coerce.date(), to: z.coerce.date() })
      .parse(request.query);
    let query: FirebaseFirestore.Query = db
      .collection("collectionSchedules")
      .where("scheduledAt", ">=", Timestamp.fromDate(range.from))
      .where("scheduledAt", "<", Timestamp.fromDate(range.to));
    if (request.user!.role === "driver") {
      query = query.where("driverId", "==", request.user!.uid);
    } else if (request.user!.role === "collector") {
      query = query.where("collectorIds", "array-contains", request.user!.uid);
    }
    const snapshot = await query.limit(200).get();
    response.json({
      data: snapshot.docs.map((document) =>
        documentJson(document.id, document.data()),
      ),
    });
  },
);

router.get(
  "/dispatch/assignable-pickups",
  authenticate,
  requireRoles(...dispatchSupervisors),
  async (_request, response) => {
    const snapshot = await db
      .collection("pickupRequests")
      .where("status", "in", ["submitted", "approved"])
      .limit(200)
      .get();
    response.json({
      data: snapshot.docs.map((document) =>
        documentJson(document.id, document.data()),
      ),
    });
  },
);

router.get(
  "/dispatch/staff",
  authenticate,
  requireRoles(...dispatchSupervisors),
  async (_request, response) => {
    const snapshot = await db
      .collection("users")
      .where("role", "in", ["collector", "driver"])
      .get();
    response.json({
      data: snapshot.docs.map((document) =>
        documentJson(document.id, {
          displayName:
            document.get("displayName") ?? document.get("email") ?? document.id,
          email: document.get("email") ?? "",
          role: document.get("role") ?? "",
          dispatchAvailable: document.get("dispatchAvailable") ?? true,
        }),
      ),
    });
  },
);

router.post(
  "/dispatch/schedules",
  authenticate,
  requireRoles(...dispatchSupervisors),
  async (request, response) => {
    const input = scheduleSchema.parse(request.body);
    const vehicleRef = db.collection("vehicles").doc(input.vehicleId);
    const pickupRefs = input.pickupIds.map((id) =>
      db.collection("pickupRequests").doc(id),
    );
    const [vehicle, ...pickups] = await db.getAll(vehicleRef, ...pickupRefs);
    if (!vehicle.exists || vehicle.get("availability") !== "available") {
      throw new (await import("./errors.js")).ApiError(
        409,
        "The selected vehicle is not available.",
        "vehicle_unavailable",
      );
    }
    if (
      pickups.some(
        (pickup) =>
          !pickup.exists ||
          !["submitted", "approved"].includes(String(pickup.get("status"))),
      )
    ) {
      throw new (await import("./errors.js")).ApiError(
        409,
        "One or more pickups are no longer assignable.",
        "pickup_unavailable",
      );
    }
    const estimatedWeight = pickups.reduce(
      (total, pickup) => total + Number(pickup.get("estimatedWeight") ?? 0),
      0,
    );
    if (estimatedWeight > Number(vehicle.get("capacityKg") ?? 0)) {
      throw new (await import("./errors.js")).ApiError(
        409,
        "Selected pickups exceed vehicle capacity.",
        "capacity_exceeded",
      );
    }
    const reference = db.collection("collectionSchedules").doc();
    const batch = db.batch();
    batch.set(reference, {
      ...input,
      scheduledAt: Timestamp.fromDate(input.scheduledAt),
      status: "planned",
      evidenceUrls: [],
      estimatedWeight,
      createdBy: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    for (const pickup of pickups) {
      batch.update(pickup.ref, {
        status: "assigned",
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    const customerIds = [
      ...new Set(
        pickups
          .map((pickup) => String(pickup.get("userId") ?? ""))
          .filter(Boolean),
      ),
    ];
    void publishNotificationEvent({
      event: "collector_assigned",
      affectedUserIds: customerIds,
      data: { scheduleId: reference.id, pickupIds: input.pickupIds },
    });
    response.status(201).json({ data: { id: reference.id, estimatedWeight } });
  },
);

async function scheduleForAction(id: string, uid: string, role: string) {
  const reference = db.collection("collectionSchedules").doc(id);
  const snapshot = await reference.get();
  if (!snapshot.exists) {
    throw new (await import("./errors.js")).ApiError(
      404,
      "Collection schedule not found.",
      "not_found",
    );
  }
  const supervisor = dispatchSupervisors.some(
    (candidate) => candidate === role,
  );
  const assigned =
    snapshot.get("driverId") === uid ||
    (snapshot.get("collectorIds") ?? []).includes(uid);
  if (!supervisor && !assigned) {
    throw new (await import("./errors.js")).ApiError(
      403,
      "You are not assigned to this collection.",
      "forbidden",
    );
  }
  return { reference, snapshot };
}

router.patch(
  "/dispatch/schedules/:id/dispatch",
  authenticate,
  requireRoles(...dispatchSupervisors),
  async (request, response) => {
    const { reference, snapshot } = await scheduleForAction(
      routeParameter(request.params.id),
      request.user!.uid,
      request.user!.role,
    );
    const batch = db.batch();
    batch.update(reference, {
      status: "dispatched",
      dispatchedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    batch.update(db.collection("vehicles").doc(snapshot.get("vehicleId")), {
      availability: "dispatched",
      updatedAt: FieldValue.serverTimestamp(),
    });
    for (const pickupId of snapshot.get("pickupIds") ?? [])
      batch.update(db.collection("pickupRequests").doc(pickupId), {
        status: "scheduled",
        updatedAt: FieldValue.serverTimestamp(),
      });
    await batch.commit();
    response.json({ data: { id: reference.id, status: "dispatched" } });
  },
);

router.patch(
  "/dispatch/schedules/:id/start",
  authenticate,
  requireRoles(...dispatchOperators),
  async (request, response) => {
    const { reference, snapshot } = await scheduleForAction(
      routeParameter(request.params.id),
      request.user!.uid,
      request.user!.role,
    );
    const batch = db.batch();
    batch.update(reference, {
      status: "inProgress",
      startedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    for (const pickupId of snapshot.get("pickupIds") ?? [])
      batch.update(db.collection("pickupRequests").doc(pickupId), {
        status: "inProgress",
        updatedAt: FieldValue.serverTimestamp(),
      });
    await batch.commit();
    const pickupDocuments = await db.getAll(
      ...(snapshot.get("pickupIds") ?? []).map((pickupId: string) =>
        db.collection("pickupRequests").doc(pickupId),
      ),
    );
    const customerIds = [
      ...new Set(
        pickupDocuments
          .map((pickup) => String(pickup.get("userId") ?? ""))
          .filter(Boolean),
      ),
    ];
    void publishNotificationEvent({
      event: "driver_en_route",
      affectedUserIds: customerIds,
      data: { scheduleId: reference.id },
    });
    response.json({ data: { id: reference.id, status: "inProgress" } });
  },
);

router.patch(
  "/dispatch/schedules/:id/complete",
  authenticate,
  requireRoles(...dispatchOperators),
  async (request, response) => {
    const input = z
      .object({ evidenceUrls: z.array(z.string().url()).default([]) })
      .parse(request.body);
    const { reference, snapshot } = await scheduleForAction(
      routeParameter(request.params.id),
      request.user!.uid,
      request.user!.role,
    );
    const batch = db.batch();
    batch.update(reference, {
      status: "completed",
      completedAt: FieldValue.serverTimestamp(),
      evidenceUrls: input.evidenceUrls,
      updatedAt: FieldValue.serverTimestamp(),
    });
    const vehicle = db.collection("vehicles").doc(snapshot.get("vehicleId"));
    batch.update(vehicle, {
      availability: "available",
      updatedAt: FieldValue.serverTimestamp(),
    });
    batch.set(vehicle.collection("trips").doc(), {
      scheduleId: reference.id,
      pickupCount: (snapshot.get("pickupIds") ?? []).length,
      completedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    });
    for (const pickupId of snapshot.get("pickupIds") ?? [])
      batch.update(db.collection("pickupRequests").doc(pickupId), {
        status: "collected",
        updatedAt: FieldValue.serverTimestamp(),
      });
    await batch.commit();
    const pickupDocuments = await db.getAll(
      ...(snapshot.get("pickupIds") ?? []).map((pickupId: string) =>
        db.collection("pickupRequests").doc(pickupId),
      ),
    );
    const customerIds = [
      ...new Set(
        pickupDocuments
          .map((pickup) => String(pickup.get("userId") ?? ""))
          .filter(Boolean),
      ),
    ];
    void publishNotificationEvent({
      event: "pickup_completed",
      affectedUserIds: customerIds,
      data: { scheduleId: reference.id },
    });
    response.json({ data: { id: reference.id, status: "completed" } });
  },
);

router.patch(
  "/dispatch/schedules/:id/reschedule",
  authenticate,
  requireRoles(...dispatchSupervisors),
  async (request, response) => {
    const input = z
      .object({ scheduledAt: z.coerce.date() })
      .parse(request.body);
    const { reference, snapshot } = await scheduleForAction(
      routeParameter(request.params.id),
      request.user!.uid,
      request.user!.role,
    );
    const batch = db.batch();
    batch.update(reference, {
      status: "planned",
      scheduledAt: Timestamp.fromDate(input.scheduledAt),
      missedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    batch.update(db.collection("vehicles").doc(snapshot.get("vehicleId")), {
      availability: "available",
      updatedAt: FieldValue.serverTimestamp(),
    });
    for (const pickupId of snapshot.get("pickupIds") ?? [])
      batch.update(db.collection("pickupRequests").doc(pickupId), {
        status: "assigned",
        scheduledAt: Timestamp.fromDate(input.scheduledAt),
        updatedAt: FieldValue.serverTimestamp(),
      });
    await batch.commit();
    response.json({ data: { id: reference.id, status: "planned" } });
  },
);

export default router;
