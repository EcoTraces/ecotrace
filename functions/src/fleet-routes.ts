import {Router} from "express";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {z} from "zod";
import {authenticate, requireRoles} from "./auth.js";
import {ApiError} from "./errors.js";
import {db} from "./firebase.js";
import {documentJson} from "./firestore-json.js";

const router = Router();
const managers = ["administrator", "superAdministrator"] as const;
const operators = ["administrator", "superAdministrator", "driver", "collector", "collectionCentreOperator", "recycler", "repairTechnician", "environmentalOfficer"] as const;
const vehicleTypes = ["van", "truck", "pickupTruck", "motorcycle", "specializedHazardous"] as const;
const availabilityStates = ["available", "dispatched", "maintenance", "breakdown", "inactive"] as const;

const vehicleSchema = z.object({
  registrationNumber: z.string().trim().min(2).max(30),
  type: z.enum(vehicleTypes),
  capacityKg: z.number().positive(),
  driverId: z.string().trim().max(160).default(""),
  insuranceExpiry: z.coerce.date().refine((value) => value.getTime() > Date.now(), "Insurance expiry must be in the future."),
  licenceExpiry: z.coerce.date().refine((value) => value.getTime() > Date.now(), "Licence expiry must be in the future."),
});

function id(value: string | string[]) { return Array.isArray(value) ? value[0] : value; }
async function vehicleRecord(vehicleId: string) {
  const ref = db.collection("vehicles").doc(vehicleId);
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new ApiError(404, "Vehicle not found.", "not_found");
  return {ref, snapshot};
}
async function validateDriver(driverId: string) {
  if (!driverId) return;
  const driver = await db.collection("users").doc(driverId).get();
  if (!driver.exists || driver.get("role") !== "driver" || driver.get("accountStatus") === "suspended") {
    throw new ApiError(409, "The selected driver is not an active driver.", "invalid_driver");
  }
}
async function ensureDriverAvailable(driverId: string, exceptVehicleId = "") {
  if (!driverId) return;
  const snapshot = await db.collection("vehicles").where("driverId", "==", driverId).limit(2).get();
  if (snapshot.docs.some((vehicle) => vehicle.id !== exceptVehicleId && vehicle.get("availability") !== "inactive")) {
    throw new ApiError(409, "The selected driver is already assigned to another active vehicle.", "driver_already_assigned");
  }
}
async function ensureRegistrationAvailable(registrationNumber: string, exceptId = "") {
  const normalized = registrationNumber.trim().toUpperCase();
  const snapshot = await db.collection("vehicles").where("registrationNumber", "==", normalized).limit(2).get();
  if (snapshot.docs.some((document) => document.id !== exceptId)) {
    throw new ApiError(409, "A vehicle with this registration number already exists.", "duplicate_registration");
  }
  return normalized;
}

router.get("/vehicles", authenticate, requireRoles(...operators), async (request, response) => {
  const filters = z.object({
    availability: z.enum(availabilityStates).optional(), type: z.enum(vehicleTypes).optional(),
    driverId: z.string().trim().max(160).optional(), query: z.string().trim().max(100).optional(),
  }).parse(request.query);
  let query: FirebaseFirestore.Query = db.collection("vehicles");
  if (filters.availability) query = query.where("availability", "==", filters.availability);
  if (filters.type) query = query.where("type", "==", filters.type);
  if (filters.driverId) query = query.where("driverId", "==", filters.driverId);
  const snapshot = await query.limit(500).get();
  const needle = filters.query?.toLowerCase();
  const data = snapshot.docs.map((document) => documentJson(document.id, document.data()))
    .filter((vehicle) => !needle || String(vehicle.registrationNumber ?? "").toLowerCase().includes(needle))
    .sort((left, right) => String(left.registrationNumber).localeCompare(String(right.registrationNumber)));
  response.json({data});
});

router.post("/vehicles", authenticate, requireRoles(...managers), async (request, response) => {
  const input = vehicleSchema.parse(request.body);
  await validateDriver(input.driverId);
  await ensureDriverAvailable(input.driverId);
  const registrationNumber = await ensureRegistrationAvailable(input.registrationNumber);
  const ref = db.collection("vehicles").doc(); const batch = db.batch();
  batch.set(ref, {...input, registrationNumber, insuranceExpiry: Timestamp.fromDate(input.insuranceExpiry), licenceExpiry: Timestamp.fromDate(input.licenceExpiry), availability: "available", mileageKm: 0, fuelLitres: 0, fuelCostSLE: 0, latitude: null, longitude: null, createdBy: request.user!.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  batch.set(ref.collection("events").doc(), {type: "registered", details: "Vehicle registered", actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  await batch.commit(); response.status(201).json({data: {id: ref.id, registrationNumber}});
});

router.get("/vehicles/:id", authenticate, requireRoles(...operators), async (request, response) => {
  const vehicle = await vehicleRecord(id(request.params.id));
  const [inspections, maintenance, breakdowns, trips] = await Promise.all([
    vehicle.ref.collection("inspections").limit(500).get(), vehicle.ref.collection("maintenance").limit(500).get(),
    vehicle.ref.collection("breakdowns").limit(500).get(), vehicle.ref.collection("trips").limit(1000).get(),
  ]);
  response.json({data: {...documentJson(vehicle.ref.id, vehicle.snapshot.data()!), summary: {inspections: inspections.size, openMaintenance: maintenance.docs.filter((document) => document.get("status") !== "completed").length, openBreakdowns: breakdowns.docs.filter((document) => document.get("status") !== "resolved").length, trips: trips.size}}});
});

router.patch("/vehicles/:id", authenticate, requireRoles(...managers), async (request, response) => {
  const input = vehicleSchema.partial().extend({availability: z.enum(availabilityStates).optional()}).refine((value) => Object.keys(value).length > 0).parse(request.body);
  const vehicle = await vehicleRecord(id(request.params.id));
  if (input.driverId !== undefined) {
    await validateDriver(input.driverId);
    await ensureDriverAvailable(input.driverId, vehicle.ref.id);
  }
  const update: Record<string, unknown> = {...input, updatedAt: FieldValue.serverTimestamp()};
  if (input.registrationNumber) update.registrationNumber = await ensureRegistrationAvailable(input.registrationNumber, vehicle.ref.id);
  if (input.insuranceExpiry) update.insuranceExpiry = Timestamp.fromDate(input.insuranceExpiry);
  if (input.licenceExpiry) update.licenceExpiry = Timestamp.fromDate(input.licenceExpiry);
  await vehicle.ref.update(update); response.json({data: {id: vehicle.ref.id}});
});

router.patch("/vehicles/:id/driver", authenticate, requireRoles(...managers), async (request, response) => {
  const input = z.object({driverId: z.string().trim().max(160)}).parse(request.body);
  await validateDriver(input.driverId); const vehicle = await vehicleRecord(id(request.params.id));
  await ensureDriverAvailable(input.driverId, vehicle.ref.id);
  const batch = db.batch(); batch.update(vehicle.ref, {driverId: input.driverId, updatedAt: FieldValue.serverTimestamp()});
  batch.set(vehicle.ref.collection("events").doc(), {type: "driverAssigned", details: input.driverId || "Driver unassigned", actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  await batch.commit(); response.json({data: {id: vehicle.ref.id, driverId: input.driverId}});
});

router.get("/vehicles/:id/inspections", authenticate, requireRoles(...operators), async (request, response) => {
  const vehicle = await vehicleRecord(id(request.params.id)); const snapshot = await vehicle.ref.collection("inspections").orderBy("inspectedAt", "desc").limit(500).get();
  response.json({data: snapshot.docs.map((document) => documentJson(document.id, document.data()))});
});
router.get("/vehicles/:id/events", authenticate, requireRoles(...operators), async (request, response) => { const vehicle = await vehicleRecord(id(request.params.id)); const snapshot = await vehicle.ref.collection("events").orderBy("createdAt", "desc").limit(1000).get(); response.json({data: snapshot.docs.map((document) => documentJson(document.id, document.data()))}); });
router.post("/vehicles/:id/inspections", authenticate, requireRoles(...managers), async (request, response) => {
  const input = z.object({result: z.enum(["passed", "passedWithIssues", "failed"]), odometerKm: z.number().nonnegative(), checklist: z.record(z.string(), z.boolean()), defects: z.array(z.string().trim().min(1).max(300)).max(50).default([]), evidenceUrls: z.array(z.string().url()).max(10).default([]), nextInspectionAt: z.coerce.date(), notes: z.string().trim().max(2000).default("")}).parse(request.body);
  const vehicle = await vehicleRecord(id(request.params.id)); const ref = vehicle.ref.collection("inspections").doc(); const batch = db.batch();
  if (input.odometerKm < Number(vehicle.snapshot.get("mileageKm") ?? 0)) throw new ApiError(409, "Odometer cannot decrease.", "invalid_odometer");
  if (input.nextInspectionAt.getTime() <= Date.now()) throw new ApiError(400, "Next inspection must be in the future.", "invalid_date");
  batch.set(ref, {...input, nextInspectionAt: Timestamp.fromDate(input.nextInspectionAt), inspectedBy: request.user!.uid, inspectedAt: FieldValue.serverTimestamp(), createdAt: FieldValue.serverTimestamp()});
  batch.update(vehicle.ref, {mileageKm: input.odometerKm, lastInspectionAt: FieldValue.serverTimestamp(), nextInspectionAt: Timestamp.fromDate(input.nextInspectionAt), ...(input.result === "failed" ? {availability: "maintenance"} : {}), updatedAt: FieldValue.serverTimestamp()});
  batch.set(vehicle.ref.collection("events").doc(), {type: "inspection", details: `${input.result}; ${input.defects.length} defect(s)`, recordId: ref.id, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  await batch.commit(); response.status(201).json({data: {id: ref.id}});
});

router.post("/vehicles/:id/fuel-records", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({litres: z.number().positive(), costSLE: z.number().nonnegative(), odometerKm: z.number().nonnegative(), station: z.string().trim().min(2).max(200), receiptUrl: z.string().url().nullable().default(null), filledAt: z.coerce.date().default(new Date())}).parse(request.body);
  const vehicle = await vehicleRecord(id(request.params.id)); if (input.odometerKm < Number(vehicle.snapshot.get("mileageKm") ?? 0)) throw new ApiError(409, "Odometer cannot decrease.", "invalid_odometer");
  const ref = vehicle.ref.collection("fuelRecords").doc(); const batch = db.batch();
  batch.set(ref, {...input, filledAt: Timestamp.fromDate(input.filledAt), recordedBy: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  batch.update(vehicle.ref, {fuelLitres: FieldValue.increment(input.litres), fuelCostSLE: FieldValue.increment(input.costSLE), mileageKm: input.odometerKm, updatedAt: FieldValue.serverTimestamp()});
  batch.set(vehicle.ref.collection("events").doc(), {type: "fuel", details: `${input.litres} L at ${input.station}`, recordId: ref.id, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  await batch.commit(); response.status(201).json({data: {id: ref.id}});
});
router.get("/vehicles/:id/fuel-records", authenticate, requireRoles(...operators), async (request, response) => { const vehicle = await vehicleRecord(id(request.params.id)); const snapshot = await vehicle.ref.collection("fuelRecords").orderBy("filledAt", "desc").limit(1000).get(); response.json({data: snapshot.docs.map((document) => documentJson(document.id, document.data()))}); });

router.post("/vehicles/:id/mileage-records", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({odometerKm: z.number().nonnegative(), purpose: z.string().trim().min(2).max(500), recordedAt: z.coerce.date().default(new Date())}).parse(request.body);
  const vehicle = await vehicleRecord(id(request.params.id)); const previous = Number(vehicle.snapshot.get("mileageKm") ?? 0); if (input.odometerKm < previous) throw new ApiError(409, "Odometer cannot decrease.", "invalid_odometer");
  const ref = vehicle.ref.collection("mileageRecords").doc(); const batch = db.batch(); batch.set(ref, {...input, distanceKm: input.odometerKm - previous, recordedAt: Timestamp.fromDate(input.recordedAt), recordedBy: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  batch.update(vehicle.ref, {mileageKm: input.odometerKm, updatedAt: FieldValue.serverTimestamp()}); batch.set(vehicle.ref.collection("events").doc(), {type: "mileage", details: `${input.odometerKm} km`, recordId: ref.id, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  await batch.commit(); response.status(201).json({data: {id: ref.id, distanceKm: input.odometerKm - previous}});
});
router.get("/vehicles/:id/mileage-records", authenticate, requireRoles(...operators), async (request, response) => { const vehicle = await vehicleRecord(id(request.params.id)); const snapshot = await vehicle.ref.collection("mileageRecords").orderBy("recordedAt", "desc").limit(1000).get(); response.json({data: snapshot.docs.map((document) => documentJson(document.id, document.data()))}); });

router.get("/vehicles/:id/maintenance", authenticate, requireRoles(...operators), async (request, response) => { const vehicle = await vehicleRecord(id(request.params.id)); const snapshot = await vehicle.ref.collection("maintenance").orderBy("scheduledAt", "desc").limit(500).get(); response.json({data: snapshot.docs.map((document) => documentJson(document.id, document.data()))}); });
router.post("/vehicles/:id/maintenance", authenticate, requireRoles(...managers), async (request, response) => {
  const input = z.object({type: z.enum(["preventive", "corrective", "inspectionFollowUp", "service"]), description: z.string().trim().min(2).max(2000), scheduledAt: z.coerce.date().refine((value) => value.getTime() > Date.now(), "Maintenance must be scheduled in the future."), estimatedCostSLE: z.number().nonnegative().default(0), provider: z.string().trim().max(200).default("")}).parse(request.body);
  const vehicle = await vehicleRecord(id(request.params.id)); const ref = vehicle.ref.collection("maintenance").doc(); const batch = db.batch(); batch.set(ref, {...input, scheduledAt: Timestamp.fromDate(input.scheduledAt), status: "scheduled", createdBy: request.user!.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}); batch.update(vehicle.ref, {nextMaintenanceAt: Timestamp.fromDate(input.scheduledAt), updatedAt: FieldValue.serverTimestamp()}); batch.set(vehicle.ref.collection("events").doc(), {type: "maintenanceScheduled", details: input.description, recordId: ref.id, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()}); await batch.commit(); response.status(201).json({data: {id: ref.id}});
});
router.patch("/vehicles/:id/maintenance/:recordId/complete", authenticate, requireRoles(...managers), async (request, response) => {
  const input = z.object({actualCostSLE: z.number().nonnegative(), workPerformed: z.string().trim().min(2).max(2000), nextMaintenanceAt: z.coerce.date().refine((value) => value.getTime() > Date.now(), "Next maintenance must be in the future."), evidenceUrls: z.array(z.string().url()).min(1).max(10)}).parse(request.body); const vehicle = await vehicleRecord(id(request.params.id)); const record = vehicle.ref.collection("maintenance").doc(id(request.params.recordId)); const recordSnapshot = await record.get(); if (!recordSnapshot.exists) throw new ApiError(404, "Maintenance record not found.", "not_found"); if (recordSnapshot.get("status") === "completed") throw new ApiError(409, "Maintenance is already completed.", "invalid_state"); const batch = db.batch(); batch.update(record, {...input, nextMaintenanceAt: Timestamp.fromDate(input.nextMaintenanceAt), status: "completed", completedBy: request.user!.uid, completedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}); batch.update(vehicle.ref, {availability: "available", lastMaintenanceAt: FieldValue.serverTimestamp(), nextMaintenanceAt: Timestamp.fromDate(input.nextMaintenanceAt), updatedAt: FieldValue.serverTimestamp()}); batch.set(vehicle.ref.collection("events").doc(), {type: "maintenanceCompleted", details: input.workPerformed, recordId: record.id, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()}); await batch.commit(); response.json({data: {id: record.id, status: "completed"}});
});

router.post("/vehicles/:id/breakdowns", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({location: z.string().trim().min(2).max(300), description: z.string().trim().min(2).max(2000), severity: z.enum(["low", "medium", "high", "critical"]), evidenceUrls: z.array(z.string().url()).max(10).default([]), occurredAt: z.coerce.date().default(new Date())}).parse(request.body); const vehicle = await vehicleRecord(id(request.params.id)); const ref = vehicle.ref.collection("breakdowns").doc(); const batch = db.batch(); batch.set(ref, {...input, occurredAt: Timestamp.fromDate(input.occurredAt), status: "open", reportedBy: request.user!.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}); batch.update(vehicle.ref, {availability: "breakdown", updatedAt: FieldValue.serverTimestamp()}); batch.set(vehicle.ref.collection("events").doc(), {type: "breakdown", details: input.description, recordId: ref.id, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()}); await batch.commit(); response.status(201).json({data: {id: ref.id}});
});
router.get("/vehicles/:id/breakdowns", authenticate, requireRoles(...operators), async (request, response) => { const vehicle = await vehicleRecord(id(request.params.id)); const snapshot = await vehicle.ref.collection("breakdowns").orderBy("occurredAt", "desc").limit(500).get(); response.json({data: snapshot.docs.map((document) => documentJson(document.id, document.data()))}); });
router.patch("/vehicles/:id/breakdowns/:recordId/resolve", authenticate, requireRoles(...managers), async (request, response) => { const input = z.object({resolution: z.string().trim().min(2).max(2000), repairCostSLE: z.number().nonnegative().default(0)}).parse(request.body); const vehicle = await vehicleRecord(id(request.params.id)); const record = vehicle.ref.collection("breakdowns").doc(id(request.params.recordId)); const recordSnapshot = await record.get(); if (!recordSnapshot.exists) throw new ApiError(404, "Breakdown record not found.", "not_found"); if (recordSnapshot.get("status") === "resolved") throw new ApiError(409, "Breakdown is already resolved.", "invalid_state"); const batch = db.batch(); batch.update(record, {...input, status: "resolved", resolvedBy: request.user!.uid, resolvedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}); batch.update(vehicle.ref, {availability: "available", updatedAt: FieldValue.serverTimestamp()}); batch.set(vehicle.ref.collection("events").doc(), {type: "breakdownResolved", details: input.resolution, recordId: record.id, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()}); await batch.commit(); response.json({data: {id: record.id, status: "resolved"}}); });

router.post("/vehicles/:id/location", authenticate, requireRoles(...operators), async (request, response) => { const input = z.object({latitude: z.number().min(-90).max(90), longitude: z.number().min(-180).max(180), accuracyMetres: z.number().nonnegative().nullable().default(null)}).parse(request.body); const vehicle = await vehicleRecord(id(request.params.id)); await vehicle.ref.update({...input, lastLocationAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}); response.json({data: {id: vehicle.ref.id, ...input}}); });
router.get("/vehicles/:id/trips", authenticate, requireRoles(...operators), async (request, response) => { const vehicle = await vehicleRecord(id(request.params.id)); const snapshot = await vehicle.ref.collection("trips").orderBy("createdAt", "desc").limit(1000).get(); response.json({data: snapshot.docs.map((document) => documentJson(document.id, document.data()))}); });

router.get("/fleet/alerts", authenticate, requireRoles(...managers), async (request, response) => {
  const days = z.coerce.number().int().min(1).max(365).default(30).parse(request.query.days); const cutoff = Date.now() + days * 86400000; const snapshot = await db.collection("vehicles").limit(1000).get(); const alerts: Array<Record<string, unknown>> = [];
  for (const vehicle of snapshot.docs) { const data = vehicle.data(); for (const [field, label] of [["insuranceExpiry", "Insurance"], ["licenceExpiry", "Licence"], ["nextMaintenanceAt", "Maintenance"]] as const) { const date = data[field]?.toDate?.() as Date | undefined; if (date && date.getTime() <= cutoff) alerts.push({vehicleId: vehicle.id, registrationNumber: data.registrationNumber, type: field, title: `${label} ${date.getTime() < Date.now() ? "overdue" : "due soon"}`, dueAt: date.toISOString(), critical: date.getTime() < Date.now()}); } if (["breakdown", "maintenance"].includes(data.availability)) alerts.push({vehicleId: vehicle.id, registrationNumber: data.registrationNumber, type: data.availability, title: `Vehicle ${data.availability}`, critical: true}); }
  response.json({data: alerts.sort((left, right) => Number(right.critical) - Number(left.critical))});
});
router.get("/fleet/utilization", authenticate, requireRoles(...managers), async (request, response) => {
  const range = z.object({from: z.coerce.date(), to: z.coerce.date()}).parse(request.query); const vehicles = await db.collection("vehicles").limit(500).get(); const data = [];
  for (const vehicle of vehicles.docs) { const trips = await vehicle.ref.collection("trips").where("completedAt", ">=", Timestamp.fromDate(range.from)).where("completedAt", "<", Timestamp.fromDate(range.to)).limit(1000).get(); const pickupCount = trips.docs.reduce((sum, trip) => sum + Number(trip.get("pickupCount") ?? 0), 0); const distanceKm = trips.docs.reduce((sum, trip) => sum + Number(trip.get("distanceKm") ?? 0), 0); data.push({vehicleId: vehicle.id, registrationNumber: vehicle.get("registrationNumber"), trips: trips.size, pickupCount, distanceKm, utilizationScore: Math.min(100, trips.size * 10)}); }
  response.json({data});
});

export default router;
