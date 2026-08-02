import {Router} from "express";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {z} from "zod";
import {authenticate, requireRoles} from "./auth.js";
import {ApiError} from "./errors.js";
import {db} from "./firebase.js";
import {documentJson} from "./firestore-json.js";

const router = Router();
const operators = ["collector", "driver", "collectionCentreOperator", "repairTechnician", "recycler", "environmentalOfficer", "administrator", "superAdministrator"] as const;
const approvers = ["environmentalOfficer", "administrator", "superAdministrator"] as const;
const transferTypes = ["pickupToCentre", "centreToRepair", "centreToRecycler", "interFacility"] as const;

function id(value: string | string[]) { return Array.isArray(value) ? value[0] : value; }
function number(value: unknown) { return Number(value ?? 0); }
async function transferRecord(transferId: string) {
  const ref = db.collection("logisticsTransfers").doc(transferId);
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new ApiError(404, "Logistics transfer not found.", "not_found");
  return {ref, snapshot};
}
function assigned(data: FirebaseFirestore.DocumentData, uid: string, role: string) {
  return ["administrator", "superAdministrator", "environmentalOfficer"].includes(role) ||
    data.driverId === uid || (data.collectorIds ?? []).includes(uid) || data.createdBy === uid;
}

router.get("/logistics/transfers", authenticate, requireRoles(...operators), async (request, response) => {
  let query: FirebaseFirestore.Query = db.collection("logisticsTransfers");
  if (typeof request.query.status === "string") query = query.where("status", "==", request.query.status);
  if (typeof request.query.type === "string") query = query.where("type", "==", request.query.type);
  const snapshot = await query.limit(500).get();
  const data = snapshot.docs.filter((doc) => assigned(doc.data(), request.user!.uid, request.user!.role)).map((doc) => documentJson(doc.id, doc.data()));
  response.json({data});
});

router.get("/logistics/transfers/:id", authenticate, requireRoles(...operators), async (request, response) => {
  const transfer = await transferRecord(id(request.params.id));
  if (!assigned(transfer.snapshot.data()!, request.user!.uid, request.user!.role)) throw new ApiError(403, "You cannot access this transfer.", "forbidden");
  response.json({data: documentJson(transfer.snapshot.id, transfer.snapshot.data()!)});
});

router.post("/logistics/transfers", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({
    type: z.enum(transferTypes),
    source: z.object({facilityId: z.string().trim().max(200).default(""), name: z.string().trim().min(2).max(300), address: z.string().trim().min(2).max(500)}),
    destination: z.object({facilityId: z.string().trim().max(200).default(""), name: z.string().trim().min(2).max(300), address: z.string().trim().min(2).max(500)}),
    itemIds: z.array(z.string().trim().min(1)).min(1).max(500),
    totalWeightKg: z.number().positive(),
    scheduledAt: z.coerce.date(),
    driverId: z.string().trim().min(1),
    collectorIds: z.array(z.string().trim().min(1)).default([]),
    vehicleId: z.string().trim().min(1),
    hazardous: z.boolean().default(false),
    notes: z.string().trim().max(2000).default(""),
  }).parse(request.body);
  if (input.source.facilityId && input.source.facilityId === input.destination.facilityId) throw new ApiError(400, "Source and destination must differ.", "invalid_argument");
  const [vehicle, driver, itemSnapshots] = await Promise.all([
    db.collection("vehicles").doc(input.vehicleId).get(),
    db.collection("users").doc(input.driverId).get(),
    Promise.all(input.itemIds.map((itemId) => db.collection("inventoryItems").doc(itemId).get())),
  ]);
  if (!vehicle.exists || vehicle.get("availability") !== "available") throw new ApiError(409, "An available vehicle is required.", "vehicle_unavailable");
  if (!driver.exists || driver.get("role") !== "driver" || driver.get("accountStatus") === "suspended") throw new ApiError(409, "An active driver is required.", "driver_unavailable");
  if (itemSnapshots.some((item) => !item.exists)) throw new ApiError(404, "One or more inventory items were not found.", "not_found");
  if (number(vehicle.get("capacityKg")) < input.totalWeightKg) throw new ApiError(409, "Transfer weight exceeds vehicle capacity.", "capacity_exceeded");
  const ref = db.collection("logisticsTransfers").doc(); const batch = db.batch();
  batch.set(ref, {...input, transferCode: `TRF-${ref.id.substring(0, 8).toUpperCase()}`, scheduledAt: Timestamp.fromDate(input.scheduledAt), status: "requested", transportDocumentNumber: `TD-${ref.id.substring(0, 10).toUpperCase()}`, deliveryProofUrls: [], exceptionCount: 0, createdBy: request.user!.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  batch.set(ref.collection("custodyEvents").doc(), {type: "transferRequested", custodianId: request.user!.uid, location: input.source.name, notes: "Transfer request created", actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  for (const item of itemSnapshots) batch.update(item.ref, {logisticsTransferId: ref.id, processingStatus: "inTransfer", updatedAt: FieldValue.serverTimestamp()});
  await batch.commit();
  response.status(201).json({data: {id: ref.id, transferCode: `TRF-${ref.id.substring(0, 8).toUpperCase()}`, status: "requested"}});
});

router.patch("/logistics/transfers/:id/review", authenticate, requireRoles(...approvers), async (request, response) => {
  const input = z.object({decision: z.enum(["approved", "rejected"]), reason: z.string().trim().max(1000).default("")}).parse(request.body);
  if (input.decision === "rejected" && !input.reason) throw new ApiError(400, "A rejection reason is required.", "invalid_argument");
  const transfer = await transferRecord(id(request.params.id));
  if (transfer.snapshot.get("status") !== "requested") throw new ApiError(409, "Only requested transfers can be reviewed.", "invalid_state");
  await transfer.ref.update({status: input.decision, reviewReason: input.reason, reviewedBy: request.user!.uid, reviewedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.json({data: {id: transfer.ref.id, status: input.decision}});
});

router.patch("/logistics/transfers/:id/dispatch", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({odometerKm: z.number().nonnegative(), sealNumber: z.string().trim().max(100).default(""), documentUrls: z.array(z.string().url()).min(1).max(10)}).parse(request.body);
  const transfer = await transferRecord(id(request.params.id)); const data = transfer.snapshot.data()!;
  if (!assigned(data, request.user!.uid, request.user!.role)) throw new ApiError(403, "You are not assigned to this transfer.", "forbidden");
  if (data.status !== "approved") throw new ApiError(409, "Only approved transfers can be dispatched.", "invalid_state");
  const vehicleRef = db.collection("vehicles").doc(String(data.vehicleId)); const batch = db.batch();
  batch.update(transfer.ref, {...input, status: "dispatched", dispatchedBy: request.user!.uid, dispatchedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  batch.update(vehicleRef, {availability: "assigned", mileageKm: input.odometerKm, updatedAt: FieldValue.serverTimestamp()});
  batch.set(transfer.ref.collection("custodyEvents").doc(), {type: "dispatched", custodianId: String(data.driverId), location: data.source?.name ?? "", notes: `Seal ${input.sealNumber || "not recorded"}`, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  await batch.commit(); response.json({data: {id: transfer.ref.id, status: "dispatched"}});
});

router.post("/logistics/transfers/:id/custody-events", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({type: z.enum(["departed", "checkpoint", "handover", "received", "inspection"]), custodianId: z.string().trim().min(1), location: z.string().trim().min(2).max(300), latitude: z.number().min(-90).max(90).nullable().default(null), longitude: z.number().min(-180).max(180).nullable().default(null), notes: z.string().trim().max(1000).default("")}).parse(request.body);
  const transfer = await transferRecord(id(request.params.id));
  if (!assigned(transfer.snapshot.data()!, request.user!.uid, request.user!.role)) throw new ApiError(403, "You are not assigned to this transfer.", "forbidden");
  if (!["dispatched", "inTransit", "exception"].includes(String(transfer.snapshot.get("status")))) throw new ApiError(409, "Custody events require an active transfer.", "invalid_state");
  const ref = await transfer.ref.collection("custodyEvents").add({...input, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  await transfer.ref.update({status: input.type === "departed" || input.type === "checkpoint" ? "inTransit" : transfer.snapshot.get("status"), currentCustodianId: input.custodianId, currentLocation: input.location, updatedAt: FieldValue.serverTimestamp()});
  response.status(201).json({data: {id: ref.id}});
});

router.get("/logistics/transfers/:id/custody-events", authenticate, requireRoles(...operators), async (request, response) => {
  const transfer = await transferRecord(id(request.params.id));
  if (!assigned(transfer.snapshot.data()!, request.user!.uid, request.user!.role)) throw new ApiError(403, "You cannot access this transfer.", "forbidden");
  const snapshot = await transfer.ref.collection("custodyEvents").orderBy("createdAt", "asc").limit(500).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.post("/logistics/transfers/:id/exceptions", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({type: z.enum(["delay", "breakdown", "accident", "routeDeviation", "damagedLoad", "missingItem", "other"]), severity: z.enum(["low", "medium", "high", "critical"]), description: z.string().trim().min(2).max(2000), location: z.string().trim().min(2).max(300), evidenceUrls: z.array(z.string().url()).max(10).default([]), immediateAction: z.string().trim().min(2).max(1000)}).parse(request.body);
  const transfer = await transferRecord(id(request.params.id));
  if (!assigned(transfer.snapshot.data()!, request.user!.uid, request.user!.role)) throw new ApiError(403, "You are not assigned to this transfer.", "forbidden");
  const ref = transfer.ref.collection("exceptions").doc(); const batch = db.batch();
  batch.set(ref, {...input, status: "open", reportedBy: request.user!.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  batch.update(transfer.ref, {status: "exception", exceptionCount: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp()});
  await batch.commit(); response.status(201).json({data: {id: ref.id, status: "open"}});
});

router.patch("/logistics/transfers/:id/receive", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({receivedWeightKg: z.number().positive(), receivedItemIds: z.array(z.string().trim().min(1)).min(1), condition: z.enum(["intact", "partiallyDamaged", "damaged"]), deliveryProofUrls: z.array(z.string().url()).min(1).max(10), receiverName: z.string().trim().min(2).max(200), notes: z.string().trim().max(1000).default("")}).parse(request.body);
  const transfer = await transferRecord(id(request.params.id)); const data = transfer.snapshot.data()!;
  if (!["dispatched", "inTransit", "exception"].includes(String(data.status))) throw new ApiError(409, "This transfer cannot be received.", "invalid_state");
  const expectedIds = new Set<string>(data.itemIds ?? []); if (input.receivedItemIds.some((itemId) => !expectedIds.has(itemId))) throw new ApiError(409, "Received items must belong to the transfer.", "item_mismatch");
  const discrepancyKg = Math.abs(input.receivedWeightKg - number(data.totalWeightKg)); const batch = db.batch();
  batch.update(transfer.ref, {...input, discrepancyKg, status: "received", receivedBy: request.user!.uid, receivedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  batch.update(db.collection("vehicles").doc(String(data.vehicleId)), {availability: "available", updatedAt: FieldValue.serverTimestamp()});
  batch.set(transfer.ref.collection("custodyEvents").doc(), {type: "received", custodianId: request.user!.uid, location: data.destination?.name ?? "", notes: input.notes, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  for (const itemId of input.receivedItemIds) batch.update(db.collection("inventoryItems").doc(itemId), {currentLocation: data.destination?.name ?? "", logisticsTransferId: "", processingStatus: "received", updatedAt: FieldValue.serverTimestamp()});
  await batch.commit(); response.json({data: {id: transfer.ref.id, status: "received", discrepancyKg}});
});

router.get("/logistics/transfers/:id/document", authenticate, requireRoles(...operators), async (request, response) => {
  const transfer = await transferRecord(id(request.params.id));
  if (!assigned(transfer.snapshot.data()!, request.user!.uid, request.user!.role)) throw new ApiError(403, "You cannot access this document.", "forbidden");
  const custody = await transfer.ref.collection("custodyEvents").orderBy("createdAt", "asc").limit(500).get();
  response.json({data: {documentNumber: transfer.snapshot.get("transportDocumentNumber"), generatedAt: new Date().toISOString(), transfer: documentJson(transfer.snapshot.id, transfer.snapshot.data()!), chainOfCustody: custody.docs.map((doc) => documentJson(doc.id, doc.data()))}});
});

router.get("/logistics/reports/summary", authenticate, requireRoles(...approvers), async (_request, response) => {
  const snapshot = await db.collection("logisticsTransfers").limit(1000).get(); const byStatus: Record<string, number> = {}; const byType: Record<string, number> = {};
  let totalWeightKg = 0; let receivedWeightKg = 0; let exceptionCount = 0; let completed = 0;
  for (const doc of snapshot.docs) { const data = doc.data(); const status = String(data.status ?? "unknown"); const type = String(data.type ?? "unknown"); byStatus[status] = (byStatus[status] ?? 0) + 1; byType[type] = (byType[type] ?? 0) + 1; totalWeightKg += number(data.totalWeightKg); receivedWeightKg += number(data.receivedWeightKg); exceptionCount += number(data.exceptionCount); if (status === "received") completed++; }
  response.json({data: {totalTransfers: snapshot.size, completedTransfers: completed, completionRatePercent: snapshot.size ? completed / snapshot.size * 100 : 0, totalWeightKg, receivedWeightKg, exceptionCount, byStatus, byType}});
});

export default router;
