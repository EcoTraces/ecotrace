import {Router} from "express";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {z} from "zod";
import {authenticate, requireRoles} from "./auth.js";
import {ApiError} from "./errors.js";
import {db} from "./firebase.js";
import {documentJson} from "./firestore-json.js";
import {publishNotificationEvent} from "./push-events.js";

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
function canReceive(data: FirebaseFirestore.DocumentData, uid: string, role: string) {
  if (assigned(data, uid, role)) return true;
  return (data.type === "pickupToCentre" && role === "collectionCentreOperator") ||
    (data.type === "centreToRepair" && role === "repairTechnician") ||
    (data.type === "centreToRecycler" && role === "recycler") ||
    (data.type === "interFacility" && ["collectionCentreOperator", "repairTechnician", "recycler"].includes(role));
}

router.get("/logistics/transfers", authenticate, requireRoles(...operators), async (request, response) => {
  let query: FirebaseFirestore.Query = db.collection("logisticsTransfers");
  if (typeof request.query.status === "string") query = query.where("status", "==", request.query.status);
  if (typeof request.query.type === "string") query = query.where("type", "==", request.query.type);
  const snapshot = await query.limit(500).get();
  const data = snapshot.docs.filter((doc) => assigned(doc.data(), request.user!.uid, request.user!.role)).map((doc) => documentJson(doc.id, doc.data()));
  response.json({data});
});

router.get("/logistics/drivers", authenticate, requireRoles(...operators), async (_request, response) => {
  const snapshot = await db.collection("users").where("role", "==", "driver").limit(500).get();
  response.json({data: snapshot.docs.filter((doc) => doc.get("accountStatus") !== "suspended").map((doc) => documentJson(doc.id, doc.data()))});
});

router.get("/logistics/centres", authenticate, requireRoles(...operators), async (_request, response) => {
  const snapshot = await db.collection("collectionCentres").where("active", "==", true).limit(500).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.get("/logistics/transfers/:id", authenticate, requireRoles(...operators), async (request, response) => {
  const transfer = await transferRecord(id(request.params.id));
  if (!assigned(transfer.snapshot.data()!, request.user!.uid, request.user!.role)) throw new ApiError(403, "You cannot access this transfer.", "forbidden");
  response.json({data: documentJson(transfer.snapshot.id, transfer.snapshot.data()!)});
});

router.post("/logistics/transfers/drafts", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({
    type: z.enum(transferTypes), originId: z.string().trim().max(200).default(""), originName: z.string().trim().min(2).max(300),
    destinationId: z.string().trim().max(200).default(""), destinationName: z.string().trim().min(2).max(300),
    assetReferences: z.array(z.string().trim().min(1)).min(1).max(500), itemCount: z.number().int().positive(), weightKg: z.number().positive(),
  }).parse(request.body);
  if (input.originId && input.originId === input.destinationId) throw new ApiError(400, "Origin and destination must differ.", "invalid_argument");
  if (input.itemCount !== input.assetReferences.length) throw new ApiError(400, "Item count must match the supplied asset references.", "item_count_mismatch");
  const items = await Promise.all(input.assetReferences.map((itemId) => db.collection("inventoryItems").doc(itemId).get()));
  if (items.some((item) => !item.exists)) throw new ApiError(404, "One or more inventory item IDs were not found.", "not_found");
  if (items.some((item) => item.get("logisticsTransferId"))) throw new ApiError(409, "One or more items already belong to an active transfer.", "item_unavailable");
  const ref = db.collection("logisticsTransfers").doc(); const write = db.batch();
  write.set(ref, {...input, transferCode: `TRF-${ref.id.substring(0, 8).toUpperCase()}`, transferNumber: `TRF-${ref.id.substring(0, 8).toUpperCase()}`, itemIds: input.assetReferences, totalWeightKg: input.weightKg, source: {facilityId: input.originId, name: input.originName, address: input.originName}, destination: {facilityId: input.destinationId, name: input.destinationName, address: input.destinationName}, status: "draft", vehicleId: "", vehicleRegistration: "", driverId: "", driverName: "", collectorIds: [], transportDocumentNumber: "", transportDocumentUrls: [], deliveryProofUrls: [], deliveryProofUrl: "", exceptionCount: 0, openExceptionCount: 0, createdBy: request.user!.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  write.set(ref.collection("custodyEvents").doc(), {type: "transferRequested", action: "Transfer created", custodianId: request.user!.uid, custodianName: request.user!.uid, location: input.originName, notes: `${input.itemCount} items, ${input.weightKg} kg`, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  for (const item of items) write.update(item.ref, {logisticsTransferId: ref.id, processingStatus: "transferDraft", updatedAt: FieldValue.serverTimestamp()});
  await write.commit(); response.status(201).json({data: {id: ref.id, status: "draft"}});
});

router.patch("/logistics/transfers/:id/transport", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({vehicleId: z.string().trim().min(1), driverId: z.string().trim().min(1), documentNumber: z.string().trim().min(2).max(200), documentUrls: z.array(z.string().url()).default([])}).parse(request.body);
  const transfer = await transferRecord(id(request.params.id));
  if (!["draft", "pendingApproval"].includes(String(transfer.snapshot.get("status")))) throw new ApiError(409, "Transport can no longer be changed.", "invalid_state");
  const [vehicle, driver] = await Promise.all([db.collection("vehicles").doc(input.vehicleId).get(), db.collection("users").doc(input.driverId).get()]);
  if (!vehicle.exists || vehicle.get("availability") !== "available") throw new ApiError(409, "An available vehicle is required.", "vehicle_unavailable");
  if (!driver.exists || driver.get("role") !== "driver" || driver.get("accountStatus") === "suspended") throw new ApiError(409, "An active driver is required.", "driver_unavailable");
  if (number(vehicle.get("capacityKg")) < number(transfer.snapshot.get("totalWeightKg"))) throw new ApiError(409, "Transfer weight exceeds vehicle capacity.", "capacity_exceeded");
  await transfer.ref.update({vehicleId: input.vehicleId, vehicleRegistration: String(vehicle.get("registrationNumber") ?? ""), driverId: input.driverId, driverName: String(driver.get("displayName") ?? ""), transportDocumentNumber: input.documentNumber, transportDocumentUrls: input.documentUrls, updatedAt: FieldValue.serverTimestamp()});
  await publishNotificationEvent({event: "logistics_transport_assigned", recipientId: input.driverId, body: `You were assigned to transfer ${String(transfer.snapshot.get("transferNumber") ?? transfer.ref.id)}.`, data: {transferId: transfer.ref.id, vehicleId: input.vehicleId}});
  response.json({data: {id: transfer.ref.id, assigned: true}});
});

router.patch("/logistics/transfers/:id/documents", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({documentUrl: z.string().url()}).parse(request.body); const transfer = await transferRecord(id(request.params.id));
  if (!assigned(transfer.snapshot.data()!, request.user!.uid, request.user!.role)) throw new ApiError(403, "You cannot update this transfer.", "forbidden");
  await transfer.ref.update({transportDocumentUrls: FieldValue.arrayUnion(input.documentUrl), updatedAt: FieldValue.serverTimestamp()});
  response.json({data: {id: transfer.ref.id, documentUrl: input.documentUrl}});
});

router.patch("/logistics/transfers/:id/submit", authenticate, requireRoles(...operators), async (request, response) => {
  const transfer = await transferRecord(id(request.params.id)); const data = transfer.snapshot.data()!;
  if (data.status !== "draft") throw new ApiError(409, "Only draft transfers can be submitted.", "invalid_state");
  if (!data.vehicleId || !data.driverId || !data.transportDocumentNumber || !(data.transportDocumentUrls ?? []).length) throw new ApiError(409, "Vehicle, driver, document number, and transport document are required.", "incomplete_transfer");
  await transfer.ref.update({status: "pendingApproval", submittedBy: request.user!.uid, submittedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  await publishNotificationEvent({event: "logistics_transfer_submitted", body: `Transfer ${String(data.transferNumber ?? transfer.ref.id)} requires approval.`, data: {transferId: transfer.ref.id}});
  response.json({data: {id: transfer.ref.id, status: "pendingApproval"}});
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
  if (!["requested", "pendingApproval"].includes(String(transfer.snapshot.get("status")))) throw new ApiError(409, "Only pending transfers can be reviewed.", "invalid_state");
  await transfer.ref.update({status: input.decision, reviewReason: input.reason, reviewedBy: request.user!.uid, reviewedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  await publishNotificationEvent({event: "logistics_transfer_reviewed", recipientId: String(transfer.snapshot.get("createdBy") ?? ""), body: `Your logistics transfer was ${input.decision}.`, data: {transferId: transfer.ref.id, status: input.decision}});
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
  await batch.commit();
  await publishNotificationEvent({event: "logistics_dispatched", recipientId: String(data.driverId), body: `Transfer ${String(data.transferNumber ?? transfer.ref.id)} is ready for transit.`, data: {transferId: transfer.ref.id}});
  response.json({data: {id: transfer.ref.id, status: "dispatched"}});
});

router.patch("/logistics/transfers/:id/start", authenticate, requireRoles(...operators), async (request, response) => {
  const transfer = await transferRecord(id(request.params.id)); const data = transfer.snapshot.data()!;
  if (!assigned(data, request.user!.uid, request.user!.role)) throw new ApiError(403, "You are not assigned to this transfer.", "forbidden");
  if (data.status !== "dispatched") throw new ApiError(409, "Only dispatched transfers can start transit.", "invalid_state");
  const event = transfer.ref.collection("custodyEvents").doc(); const write = db.batch();
  write.update(transfer.ref, {status: "inTransit", currentCustodianId: String(data.driverId), currentLocation: data.source?.name ?? data.originName ?? "", updatedAt: FieldValue.serverTimestamp()});
  write.set(event, {type: "departed", action: "Departed origin", custodianId: String(data.driverId), custodianName: String(data.driverName ?? ""), location: data.source?.name ?? data.originName ?? "", notes: "", actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  await write.commit(); response.json({data: {id: transfer.ref.id, status: "inTransit"}});
});

router.patch("/logistics/transfers/:id/deliver", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({deliveryProofUrl: z.string().url(), notes: z.string().trim().max(1000).default("")}).parse(request.body);
  const transfer = await transferRecord(id(request.params.id)); const data = transfer.snapshot.data()!;
  if (!assigned(data, request.user!.uid, request.user!.role)) throw new ApiError(403, "You are not assigned to this transfer.", "forbidden");
  if (!["dispatched", "inTransit"].includes(String(data.status))) throw new ApiError(409, "The transfer is not in transit.", "invalid_state");
  const event = transfer.ref.collection("custodyEvents").doc(); const write = db.batch();
  write.update(transfer.ref, {status: "delivered", deliveryProofUrl: input.deliveryProofUrl, deliveryProofUrls: FieldValue.arrayUnion(input.deliveryProofUrl), deliveryNotes: input.notes, deliveredBy: request.user!.uid, deliveredAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  write.set(event, {type: "handover", action: "Delivery confirmed", custodianId: request.user!.uid, custodianName: String(data.driverName ?? ""), location: data.destination?.name ?? data.destinationName ?? "", notes: input.notes, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  await write.commit(); response.json({data: {id: transfer.ref.id, status: "delivered"}});
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
  batch.update(transfer.ref, {status: "exception", resumeStatus: transfer.snapshot.get("status"), exceptionCount: FieldValue.increment(1), openExceptionCount: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp()});
  await batch.commit();
  await publishNotificationEvent({event: "logistics_exception_reported", body: `${input.severity} logistics exception: ${input.type}.`, data: {transferId: transfer.ref.id, exceptionId: ref.id}});
  response.status(201).json({data: {id: ref.id, status: "open"}});
});

router.get("/logistics/transfers/:id/exceptions", authenticate, requireRoles(...operators), async (request, response) => {
  const transfer = await transferRecord(id(request.params.id));
  if (!assigned(transfer.snapshot.data()!, request.user!.uid, request.user!.role)) throw new ApiError(403, "You cannot access this transfer.", "forbidden");
  const snapshot = await transfer.ref.collection("exceptions").orderBy("createdAt", "desc").limit(300).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.patch("/logistics/transfers/:id/exceptions/:exceptionId/resolve", authenticate, requireRoles(...approvers), async (request, response) => {
  const input = z.object({resolution: z.string().trim().min(2).max(2000)}).parse(request.body); const transfer = await transferRecord(id(request.params.id));
  const exceptionRef = transfer.ref.collection("exceptions").doc(id(request.params.exceptionId));
  await db.runTransaction(async (transaction) => {
    const [current, exception] = await Promise.all([transaction.get(transfer.ref), transaction.get(exceptionRef)]);
    if (!exception.exists) throw new ApiError(404, "Transfer exception not found.", "not_found");
    if (exception.get("status") === "resolved" || exception.get("resolved") === true) throw new ApiError(409, "This exception is already resolved.", "invalid_state");
    const open = Math.max(0, number(current.get("openExceptionCount")) - 1);
    transaction.update(exceptionRef, {status: "resolved", resolved: true, resolution: input.resolution, resolvedBy: request.user!.uid, resolvedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
    transaction.update(transfer.ref, {openExceptionCount: open, ...(open === 0 ? {status: String(current.get("resumeStatus") ?? "inTransit")} : {}), updatedAt: FieldValue.serverTimestamp()});
  });
  response.json({data: {id: exceptionRef.id, status: "resolved"}});
});

router.patch("/logistics/transfers/:id/receive", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({receivedWeightKg: z.number().positive(), receivedItemIds: z.array(z.string().trim().min(1)).min(1), condition: z.enum(["intact", "partiallyDamaged", "damaged"]), deliveryProofUrls: z.array(z.string().url()).min(1).max(10), receiverName: z.string().trim().min(2).max(200), notes: z.string().trim().max(1000).default("")}).parse(request.body);
  const transfer = await transferRecord(id(request.params.id)); const data = transfer.snapshot.data()!;
  if (!canReceive(data, request.user!.uid, request.user!.role)) throw new ApiError(403, "You cannot receive this transfer.", "forbidden");
  if (!["dispatched", "inTransit", "exception", "delivered"].includes(String(data.status))) throw new ApiError(409, "This transfer cannot be received.", "invalid_state");
  const expectedIds = new Set<string>(data.itemIds ?? []);
  const receivedIds = new Set(input.receivedItemIds);
  if (receivedIds.size !== expectedIds.size || [...receivedIds].some((itemId) => !expectedIds.has(itemId))) throw new ApiError(409, "Every transferred item must be confirmed at receipt.", "item_mismatch");
  const discrepancyKg = Math.abs(input.receivedWeightKg - number(data.totalWeightKg)); const batch = db.batch();
  batch.update(transfer.ref, {...input, discrepancyKg, status: "received", receivedBy: request.user!.uid, receivedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  batch.update(db.collection("vehicles").doc(String(data.vehicleId)), {availability: "available", updatedAt: FieldValue.serverTimestamp()});
  batch.set(transfer.ref.collection("custodyEvents").doc(), {type: "received", custodianId: request.user!.uid, location: data.destination?.name ?? "", notes: input.notes, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  for (const itemId of input.receivedItemIds) batch.update(db.collection("inventoryItems").doc(itemId), {currentLocation: data.destination?.name ?? "", logisticsTransferId: "", processingStatus: "received", updatedAt: FieldValue.serverTimestamp()});
  await batch.commit();
  await publishNotificationEvent({event: "logistics_received", recipientId: String(data.createdBy ?? ""), body: `Transfer ${String(data.transferNumber ?? transfer.ref.id)} was received.`, data: {transferId: transfer.ref.id, discrepancyKg}});
  response.json({data: {id: transfer.ref.id, status: "received", discrepancyKg}});
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
