import { Router } from "express";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { z } from "zod";
import { authenticate, requireRoles } from "./auth.js";
import { ApiError } from "./errors.js";
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
import complianceWorkflowRoutes from "./compliance-workflow-routes.js";
import incidentRoutes from "./incident-routes.js";
import documentRoutes from "./document-routes.js";
import auditRoutes, {auditMutations} from "./audit-routes.js";
import administrationRoutes from "./administration-routes.js";
import identityRoutes from "./identity-routes.js";
import organizationRoutes from "./organization-routes.js";
import pickupRoutes from "./pickup-routes.js";
import classificationRoutes from "./classification-routes.js";
import fleetRoutes from "./fleet-routes.js";
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
router.use(complianceWorkflowRoutes);
router.use(incidentRoutes);
router.use(documentRoutes);
router.use(auditRoutes);
router.use(administrationRoutes);
router.use(identityRoutes);
router.use(organizationRoutes);
router.use(pickupRoutes);
router.use(classificationRoutes);
router.use(fleetRoutes);
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

const scheduleSchema = z.object({
  scheduledAt: z.coerce.date().refine(
    (value) => value.getTime() > Date.now(),
    "Collection schedules must be created for a future date and time.",
  ),
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

function routeParameter(value: string | string[]): string {
  return Array.isArray(value) ? value[0] : value;
}

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

router.get(
  "/dispatch/dashboard",
  authenticate,
  requireRoles(...dispatchSupervisors),
  async (request, response) => {
    const range = z.object({from: z.coerce.date(), to: z.coerce.date()}).parse(request.query);
    const snapshot = await db.collection("collectionSchedules")
      .where("scheduledAt", ">=", Timestamp.fromDate(range.from))
      .where("scheduledAt", "<", Timestamp.fromDate(range.to)).limit(1000).get();
    const byStatus: Record<string, number> = {};
    const byPriority: Record<string, number> = {};
    let pickupCount = 0;
    let estimatedWeightKg = 0;
    for (const schedule of snapshot.docs) {
      const status = String(schedule.get("status") ?? "unknown");
      const priority = String(schedule.get("priority") ?? "normal");
      byStatus[status] = (byStatus[status] ?? 0) + 1;
      byPriority[priority] = (byPriority[priority] ?? 0) + 1;
      pickupCount += (schedule.get("pickupIds") ?? []).length;
      estimatedWeightKg += Number(schedule.get("estimatedWeight") ?? 0);
    }
    response.json({data: {
      totalSchedules: snapshot.size,
      pickupCount,
      estimatedWeightKg,
      completionRate: snapshot.size ? (byStatus.completed ?? 0) / snapshot.size : 0,
      byStatus,
      byPriority,
    }});
  },
);

router.get(
  "/dispatch/availability",
  authenticate,
  requireRoles(...dispatchSupervisors),
  async (request, response) => {
    const at = z.coerce.date().default(new Date()).parse(request.query.at);
    const [staff, vehicles, schedules] = await Promise.all([
      db.collection("users").where("role", "in", ["collector", "driver"]).limit(500).get(),
      db.collection("vehicles").limit(500).get(),
      db.collection("collectionSchedules")
        .where("scheduledAt", ">=", Timestamp.fromDate(new Date(at.getTime() - 12 * 60 * 60 * 1000)))
        .where("scheduledAt", "<", Timestamp.fromDate(new Date(at.getTime() + 12 * 60 * 60 * 1000)))
        .limit(500).get(),
    ]);
    const active = schedules.docs.filter((schedule) =>
      ["planned", "dispatched", "inProgress"].includes(String(schedule.get("status"))));
    const busyStaff = new Set(active.flatMap((schedule) => [
      String(schedule.get("driverId") ?? ""),
      ...(schedule.get("collectorIds") ?? []).map(String),
    ]));
    const busyVehicles = new Set(active.map((schedule) => String(schedule.get("vehicleId") ?? "")));
    response.json({data: {
      staff: staff.docs.map((person) => ({
        ...documentJson(person.id, person.data()),
        available: person.get("dispatchAvailable") !== false && !busyStaff.has(person.id),
      })),
      vehicles: vehicles.docs.map((vehicle) => ({
        ...documentJson(vehicle.id, vehicle.data()),
        available: vehicle.get("availability") === "available" && !busyVehicles.has(vehicle.id),
      })),
    }});
  },
);

router.get(
  "/dispatch/nearby-groups",
  authenticate,
  requireRoles(...dispatchSupervisors),
  async (request, response) => {
    const radiusKm = z.coerce.number().min(0.5).max(100).default(10).parse(request.query.radiusKm);
    const snapshot = await db.collection("pickupRequests")
      .where("status", "in", ["submitted", "approved"]).limit(500).get();
    const remaining = snapshot.docs.map((document) => documentJson(document.id, document.data()));
    const groups: Array<{groupId: string; centre: {latitude: number | null; longitude: number | null}; pickupIds: string[]; serviceArea: string; totalWeightKg: number}> = [];
    const radians = (degrees: number) => degrees * Math.PI / 180;
    const distance = (left: Record<string, unknown>, right: Record<string, unknown>) => {
      const lat1 = Number(left.latitude); const lon1 = Number(left.longitude);
      const lat2 = Number(right.latitude); const lon2 = Number(right.longitude);
      if (![lat1, lon1, lat2, lon2].every(Number.isFinite)) return Number.POSITIVE_INFINITY;
      const dLat = radians(lat2 - lat1); const dLon = radians(lon2 - lon1);
      const value = Math.sin(dLat / 2) ** 2 + Math.cos(radians(lat1)) * Math.cos(radians(lat2)) * Math.sin(dLon / 2) ** 2;
      return 6371 * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value));
    };
    while (remaining.length) {
      const seed = remaining.shift()!;
      const nearby = remaining.filter((pickup) => distance(seed, pickup) <= radiusKm ||
        (!Number.isFinite(Number(seed.latitude)) && String(seed.location ?? "").toLowerCase() === String(pickup.location ?? "").toLowerCase()));
      for (const pickup of nearby) remaining.splice(remaining.indexOf(pickup), 1);
      const members = [seed, ...nearby];
      groups.push({
        groupId: `GROUP-${groups.length + 1}`,
        centre: {latitude: Number.isFinite(Number(seed.latitude)) ? Number(seed.latitude) : null, longitude: Number.isFinite(Number(seed.longitude)) ? Number(seed.longitude) : null},
        pickupIds: members.map((pickup) => String(pickup.id)),
        serviceArea: String(seed.location ?? "Unspecified area"),
        totalWeightKg: members.reduce((total, pickup) => total + Number(pickup.estimatedWeight ?? 0), 0),
      });
    }
    response.json({data: groups});
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
    const staffRefs = [...new Set([input.driverId, ...input.collectorIds])]
      .map((id) => db.collection("users").doc(id));
    const [vehicleAndPickups, staff, activeSchedules] = await Promise.all([
      db.getAll(vehicleRef, ...pickupRefs),
      db.getAll(...staffRefs),
      db.collection("collectionSchedules")
        .where("scheduledAt", ">=", Timestamp.fromDate(new Date(input.scheduledAt.getTime() - 12 * 60 * 60 * 1000)))
        .where("scheduledAt", "<", Timestamp.fromDate(new Date(input.scheduledAt.getTime() + 12 * 60 * 60 * 1000)))
        .limit(500).get(),
    ]);
    const [vehicle, ...pickups] = vehicleAndPickups;
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
    const driver = staff.find((person) => person.id === input.driverId);
    if (!driver?.exists || driver.get("role") !== "driver" || driver.get("dispatchAvailable") === false) {
      throw new ApiError(409, "The selected driver is not available.", "driver_unavailable");
    }
    const invalidCollector = input.collectorIds.some((collectorId) => {
      const collector = staff.find((person) => person.id === collectorId);
      return !collector?.exists || collector.get("role") !== "collector" || collector.get("dispatchAvailable") === false;
    });
    if (invalidCollector) throw new ApiError(409, "One or more collectors are not available.", "collector_unavailable");
    const requestedStaff = new Set([input.driverId, ...input.collectorIds]);
    const conflict = activeSchedules.docs.find((schedule) => {
      if (!["planned", "dispatched", "inProgress"].includes(String(schedule.get("status")))) return false;
      const assignedStaff = [String(schedule.get("driverId") ?? ""), ...(schedule.get("collectorIds") ?? []).map(String)];
      return schedule.get("vehicleId") === input.vehicleId || assignedStaff.some((id) => requestedStaff.has(id));
    });
    if (conflict) throw new ApiError(409, "A selected driver, collector, or vehicle already has a nearby active assignment.", "schedule_conflict");
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
      scheduleCode: `SCH-${reference.id.substring(0, 8).toUpperCase()}`,
      scheduledAt: Timestamp.fromDate(input.scheduledAt),
      status: "planned",
      evidenceUrls: [],
      estimatedWeight,
      teamSize: input.collectorIds.length + 1,
      createdBy: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    for (const pickup of pickups) {
      const statusEvent = {
        from: String(pickup.get("status")),
        to: "assigned",
        actorId: request.user!.uid,
        reason: "Assigned to a collection schedule",
        changedAt: Timestamp.now(),
      };
      batch.update(pickup.ref, {
        status: "assigned",
        statusHistory: FieldValue.arrayUnion(statusEvent),
        updatedAt: FieldValue.serverTimestamp(),
      });
      batch.set(pickup.ref.collection("events").doc(), {
        type: "statusChanged",
        ...statusEvent,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    for (const staffId of [...new Set([input.driverId, ...input.collectorIds])]) {
      batch.set(db.collection("users").doc(staffId).collection("notifications").doc(), {
        type: "assignment",
        title: "New collection assignment",
        body: `${input.serviceArea} collection scheduled for ${input.scheduledAt.toISOString()}`,
        data: {scheduleId: reference.id, pickupIds: input.pickupIds},
        read: false,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    batch.set(reference.collection("events").doc(), {
      type: "created",
      status: "planned",
      actorId: request.user!.uid,
      details: `${input.pickupIds.length} pickup(s) assigned`,
      createdAt: FieldValue.serverTimestamp(),
    });
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

router.get(
  "/dispatch/schedules/:id",
  authenticate,
  requireRoles(...dispatchOperators),
  async (request, response) => {
    const {reference, snapshot} = await scheduleForAction(
      routeParameter(request.params.id), request.user!.uid, request.user!.role,
    );
    const [pickups, events] = await Promise.all([
      db.getAll(...(snapshot.get("pickupIds") ?? []).map((pickupId: string) => db.collection("pickupRequests").doc(pickupId))),
      reference.collection("events").orderBy("createdAt", "asc").limit(500).get(),
    ]);
    response.json({data: {
      ...documentJson(snapshot.id, snapshot.data()!),
      pickups: pickups.map((pickup) => documentJson(pickup.id, pickup.data() ?? {})),
      events: events.docs.map((event) => documentJson(event.id, event.data())),
    }});
  },
);

router.patch(
  "/dispatch/schedules/:id/cancel",
  authenticate,
  requireRoles(...dispatchSupervisors),
  async (request, response) => {
    const input = z.object({reason: z.string().trim().min(2).max(1000)}).parse(request.body);
    const {reference, snapshot} = await scheduleForAction(
      routeParameter(request.params.id), request.user!.uid, request.user!.role,
    );
    if (["completed", "cancelled"].includes(String(snapshot.get("status")))) {
      throw new ApiError(409, "This schedule can no longer be cancelled.", "invalid_state");
    }
    const batch = db.batch();
    batch.update(reference, {
      status: "cancelled", cancellationReason: input.reason,
      cancelledBy: request.user!.uid, cancelledAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    batch.update(db.collection("vehicles").doc(String(snapshot.get("vehicleId"))), {
      availability: "available", updatedAt: FieldValue.serverTimestamp(),
    });
    for (const pickupId of snapshot.get("pickupIds") ?? []) {
      const pickup = db.collection("pickupRequests").doc(String(pickupId));
      batch.update(pickup, {status: "approved", updatedAt: FieldValue.serverTimestamp()});
      batch.set(pickup.collection("events").doc(), {
        type: "scheduleCancelled", scheduleId: reference.id, reason: input.reason,
        actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp(),
      });
    }
    batch.set(reference.collection("events").doc(), {
      type: "cancelled", status: "cancelled", reason: input.reason,
      actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp(),
    });
    for (const staffId of [...new Set([snapshot.get("driverId"), ...(snapshot.get("collectorIds") ?? [])].filter(Boolean).map(String))]) {
      batch.set(db.collection("users").doc(staffId).collection("notifications").doc(), {
        type: "assignment", title: "Collection cancelled", body: input.reason,
        data: {scheduleId: reference.id}, read: false, createdAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    response.json({data: {id: reference.id, status: "cancelled"}});
  },
);

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
    if (snapshot.get("status") !== "planned") {
      throw new ApiError(409, "Only a planned schedule can be dispatched.", "invalid_state");
    }
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
    for (const pickupId of snapshot.get("pickupIds") ?? []) {
      const pickup = db.collection("pickupRequests").doc(pickupId);
      const statusEvent = {
        from: "assigned",
        to: "scheduled",
        actorId: request.user!.uid,
        reason: "Collection team dispatched",
        changedAt: Timestamp.now(),
      };
      batch.update(pickup, {
        status: "scheduled",
        statusHistory: FieldValue.arrayUnion(statusEvent),
        updatedAt: FieldValue.serverTimestamp(),
      });
      batch.set(pickup.collection("events").doc(), {
        type: "statusChanged",
        ...statusEvent,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    batch.set(reference.collection("events").doc(), {
      type: "dispatched", status: "dispatched", actorId: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(),
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
    if (snapshot.get("status") !== "dispatched") {
      throw new ApiError(409, "The team must be dispatched before collection starts.", "invalid_state");
    }
    const batch = db.batch();
    batch.update(reference, {
      status: "inProgress",
      startedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    for (const pickupId of snapshot.get("pickupIds") ?? []) {
      const pickup = db.collection("pickupRequests").doc(pickupId);
      const statusEvent = {
        from: "scheduled",
        to: "inProgress",
        actorId: request.user!.uid,
        reason: "Collection started",
        changedAt: Timestamp.now(),
      };
      batch.update(pickup, {
        status: "inProgress",
        statusHistory: FieldValue.arrayUnion(statusEvent),
        updatedAt: FieldValue.serverTimestamp(),
      });
      batch.set(pickup.collection("events").doc(), {
        type: "statusChanged",
        ...statusEvent,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    batch.set(reference.collection("events").doc(), {
      type: "started", status: "inProgress", actorId: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(),
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
      .object({ evidenceUrls: z.array(z.string().url()).min(1).max(10) })
      .parse(request.body);
    const { reference, snapshot } = await scheduleForAction(
      routeParameter(request.params.id),
      request.user!.uid,
      request.user!.role,
    );
    if (snapshot.get("status") !== "inProgress") {
      throw new ApiError(409, "Only an active collection can be completed.", "invalid_state");
    }
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
    for (const pickupId of snapshot.get("pickupIds") ?? []) {
      const pickup = db.collection("pickupRequests").doc(pickupId);
      const statusEvent = {
        from: "inProgress",
        to: "collected",
        actorId: request.user!.uid,
        reason: "Items collected with evidence",
        changedAt: Timestamp.now(),
      };
      batch.update(pickup, {
        status: "collected",
        statusHistory: FieldValue.arrayUnion(statusEvent),
        updatedAt: FieldValue.serverTimestamp(),
      });
      batch.set(pickup.collection("events").doc(), {
        type: "statusChanged",
        ...statusEvent,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    batch.set(reference.collection("events").doc(), {
      type: "completed", status: "completed", evidenceUrls: input.evidenceUrls,
      actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp(),
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
      .object({
        scheduledAt: z.coerce.date().refine(
          (value) => value.getTime() > Date.now(),
          "The replacement collection date must be in the future.",
        ),
        reason: z.string().trim().min(2).max(1000),
      })
      .parse(request.body);
    const { reference, snapshot } = await scheduleForAction(
      routeParameter(request.params.id),
      request.user!.uid,
      request.user!.role,
    );
    if (["completed", "cancelled"].includes(String(snapshot.get("status")))) {
      throw new ApiError(409, "A completed or cancelled schedule cannot be rescheduled.", "invalid_state");
    }
    const conflicts = await db.collection("collectionSchedules")
      .where("scheduledAt", ">=", Timestamp.fromDate(new Date(input.scheduledAt.getTime() - 12 * 60 * 60 * 1000)))
      .where("scheduledAt", "<", Timestamp.fromDate(new Date(input.scheduledAt.getTime() + 12 * 60 * 60 * 1000)))
      .limit(500).get();
    const assignedStaff = new Set([
      String(snapshot.get("driverId") ?? ""),
      ...(snapshot.get("collectorIds") ?? []).map(String),
    ]);
    const conflict = conflicts.docs.find((candidate) => {
      if (candidate.id === reference.id || !["planned", "dispatched", "inProgress"].includes(String(candidate.get("status")))) return false;
      const candidateStaff = [String(candidate.get("driverId") ?? ""), ...(candidate.get("collectorIds") ?? []).map(String)];
      return candidate.get("vehicleId") === snapshot.get("vehicleId") || candidateStaff.some((id) => assignedStaff.has(id));
    });
    if (conflict) {
      throw new ApiError(409, "The assigned team or vehicle is not available at the replacement time.", "schedule_conflict");
    }
    const batch = db.batch();
    batch.update(reference, {
      status: "planned",
      scheduledAt: Timestamp.fromDate(input.scheduledAt),
      missedAt: FieldValue.serverTimestamp(),
      rescheduleReason: input.reason,
      previousScheduledAt: snapshot.get("scheduledAt"),
      updatedAt: FieldValue.serverTimestamp(),
    });
    batch.update(db.collection("vehicles").doc(snapshot.get("vehicleId")), {
      availability: "available",
      updatedAt: FieldValue.serverTimestamp(),
    });
    for (const pickupId of snapshot.get("pickupIds") ?? []) {
      const pickup = db.collection("pickupRequests").doc(pickupId);
      const statusEvent = {
        from: "assigned",
        to: "assigned",
        actorId: request.user!.uid,
        reason: "Missed collection rescheduled",
        scheduledAt: Timestamp.fromDate(input.scheduledAt),
        changedAt: Timestamp.now(),
      };
      batch.update(pickup, {
        status: "assigned",
        scheduledAt: Timestamp.fromDate(input.scheduledAt),
        statusHistory: FieldValue.arrayUnion(statusEvent),
        updatedAt: FieldValue.serverTimestamp(),
      });
      batch.set(pickup.collection("events").doc(), {
        type: "rescheduled",
        ...statusEvent,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    batch.set(reference.collection("events").doc(), {
      type: "rescheduled", status: "planned", reason: input.reason,
      scheduledAt: Timestamp.fromDate(input.scheduledAt), actorId: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(),
    });
    await batch.commit();
    void publishNotificationEvent({
      event: "pickup_rescheduled",
      affectedUserIds: [
        ...new Set([
          String(snapshot.get("driverId") ?? ""),
          ...(snapshot.get("collectorIds") ?? []).map(String),
        ].filter(Boolean)),
      ],
      data: {
        scheduleId: reference.id,
        scheduledAt: input.scheduledAt.toISOString(),
        reason: input.reason,
      },
    });
    response.json({ data: { id: reference.id, status: "planned" } });
  },
);

export default router;
