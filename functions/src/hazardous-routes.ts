import {Router} from "express";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {z} from "zod";
import {authenticate, requireRoles} from "./auth.js";
import {ApiError} from "./errors.js";
import {db} from "./firebase.js";
import {documentJson} from "./firestore-json.js";

const router = Router();
const operators = ["recycler", "environmentalOfficer", "administrator", "superAdministrator"] as const;
const supervisors = ["environmentalOfficer", "administrator", "superAdministrator"] as const;
const classes = ["battery", "mercury", "lead", "cadmium", "lithium", "cobalt", "brominatedPlastic", "refrigerant", "other"] as const;
const riskLevels = ["low", "medium", "high", "critical"] as const;

function id(value: string | string[]) { return Array.isArray(value) ? value[0] : value; }
function number(value: unknown) { return Number(value ?? 0); }
async function hazardousRecord(recordId: string) {
  const ref = db.collection("hazardousWasteRecords").doc(recordId);
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new ApiError(404, "Hazardous waste record not found.", "not_found");
  return {ref, snapshot};
}

router.get("/hazardous/records", authenticate, requireRoles(...operators), async (request, response) => {
  let query: FirebaseFirestore.Query = db.collection("hazardousWasteRecords");
  if (typeof request.query.status === "string") query = query.where("status", "==", request.query.status);
  if (typeof request.query.classification === "string") query = query.where("classification", "==", request.query.classification);
  const snapshot = await query.limit(500).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.get("/hazardous/records/:id", authenticate, requireRoles(...operators), async (request, response) => {
  const record = await hazardousRecord(id(request.params.id));
  response.json({data: documentJson(record.snapshot.id, record.snapshot.data()!)});
});

router.post("/hazardous/records", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({
    sourceType: z.enum(["inventoryItem", "recyclingBatch", "manual"]),
    sourceId: z.string().trim().max(200).default(""),
    classification: z.enum(classes),
    description: z.string().trim().min(2).max(1000),
    weightKg: z.number().positive(),
    quantity: z.number().int().positive().default(1),
    riskLevel: z.enum(riskLevels),
    storageLocation: z.string().trim().min(2).max(300),
    safetyInstructions: z.array(z.string().trim().min(2).max(300)).min(1),
  }).parse(request.body);
  if (input.sourceType !== "manual" && !input.sourceId) throw new ApiError(400, "A source ID is required.", "invalid_argument");
  const ref = db.collection("hazardousWasteRecords").doc();
  await ref.set({...input, recordCode: `HAZ-${ref.id.substring(0, 8).toUpperCase()}`, status: "identified", currentCustodianId: request.user!.uid, disposedWeightKg: 0, createdBy: request.user!.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.status(201).json({data: {id: ref.id, recordCode: `HAZ-${ref.id.substring(0, 8).toUpperCase()}`}});
});

router.patch("/hazardous/records/:id/storage", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({storageLocation: z.string().trim().min(2).max(300), containmentType: z.string().trim().min(2).max(200), inspectionDueAt: z.coerce.date()}).parse(request.body);
  const record = await hazardousRecord(id(request.params.id));
  if (record.snapshot.get("status") === "disposed") throw new ApiError(409, "Disposed waste cannot be moved into storage.", "invalid_state");
  await record.ref.update({...input, inspectionDueAt: Timestamp.fromDate(input.inspectionDueAt), status: "stored", storedBy: request.user!.uid, storedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.json({data: {id: record.ref.id, status: "stored"}});
});

router.post("/hazardous/records/:id/battery-handling", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({batteryType: z.string().trim().min(2).max(100), damaged: z.boolean(), terminalsIsolated: z.boolean(), fireproofContainer: z.boolean(), notes: z.string().trim().max(1000).default("")}).parse(request.body);
  const record = await hazardousRecord(id(request.params.id));
  if (record.snapshot.get("classification") !== "battery" && record.snapshot.get("classification") !== "lithium") throw new ApiError(409, "Battery handling can only be recorded for battery or lithium waste.", "classification_mismatch");
  const ref = await record.ref.collection("batteryHandlingRecords").add({...input, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  response.status(201).json({data: {id: ref.id}});
});

router.post("/hazardous/records/:id/safety-checks", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({ppeItems: z.array(z.object({name: z.string().trim().min(2).max(100), checked: z.boolean()})).min(1), instructionsAcknowledged: z.boolean(), notes: z.string().trim().max(1000).default("")}).parse(request.body);
  if (!input.instructionsAcknowledged || input.ppeItems.some((item) => !item.checked)) throw new ApiError(409, "All protective equipment and safety instructions must be confirmed.", "safety_check_incomplete");
  const record = await hazardousRecord(id(request.params.id));
  const ref = await record.ref.collection("safetyChecks").add({...input, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  response.status(201).json({data: {id: ref.id, passed: true}});
});

router.post("/hazardous/incidents", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({recordId: z.string().trim().default(""), type: z.enum(["spill", "exposure", "fire", "leak", "damagedContainer", "other"]), severity: z.enum(riskLevels), location: z.string().trim().min(2).max(300), description: z.string().trim().min(2).max(2000), immediateActions: z.array(z.string().trim().min(2).max(300)).min(1), evidenceUrls: z.array(z.string().url()).max(10).default([]), staffIds: z.array(z.string().trim().min(1)).default([])}).parse(request.body);
  if (input.recordId) await hazardousRecord(input.recordId);
  const ref = await db.collection("hazardousIncidents").add({...input, status: "reported", reportedBy: request.user!.uid, reportedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.status(201).json({data: {id: ref.id, status: "reported"}});
});

router.get("/hazardous/incidents", authenticate, requireRoles(...operators), async (request, response) => {
  let query: FirebaseFirestore.Query = db.collection("hazardousIncidents");
  if (typeof request.query.status === "string") query = query.where("status", "==", request.query.status);
  const snapshot = await query.limit(500).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.patch("/hazardous/incidents/:id/response", authenticate, requireRoles(...supervisors), async (request, response) => {
  const input = z.object({responseStatus: z.enum(["responding", "contained", "investigating", "closed"]), actions: z.array(z.string().trim().min(2).max(300)).min(1), emergencyContact: z.string().trim().max(200).default(""), rootCause: z.string().trim().max(1000).default(""), correctiveActions: z.array(z.string().trim().min(2).max(300)).default([])}).parse(request.body);
  const ref = db.collection("hazardousIncidents").doc(id(request.params.id)); const snapshot = await ref.get();
  if (!snapshot.exists) throw new ApiError(404, "Hazardous incident not found.", "not_found");
  await ref.update({...input, status: input.responseStatus, reviewedBy: request.user!.uid, updatedAt: FieldValue.serverTimestamp(), ...(input.responseStatus === "closed" ? {closedAt: FieldValue.serverTimestamp()} : {})});
  response.json({data: {id: ref.id, status: input.responseStatus}});
});

router.post("/hazardous/records/:id/transfers", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({destinationFacilityId: z.string().trim().min(1), destinationFacilityName: z.string().trim().min(2).max(300), carrier: z.string().trim().min(2).max(200), manifestNumber: z.string().trim().min(2).max(100), weightKg: z.number().positive(), driverName: z.string().trim().min(2).max(200), vehicleRegistration: z.string().trim().min(2).max(50)}).parse(request.body);
  const record = await hazardousRecord(id(request.params.id));
  if (record.snapshot.get("status") === "disposed") throw new ApiError(409, "Disposed waste cannot be transferred.", "invalid_state");
  if (input.weightKg > number(record.snapshot.get("weightKg")) - number(record.snapshot.get("disposedWeightKg")) + 0.001) throw new ApiError(409, "Transfer weight exceeds available hazardous waste.", "mass_balance_exceeded");
  const transfer = record.ref.collection("transfers").doc(); const batch = db.batch();
  batch.set(transfer, {...input, from: String(record.snapshot.get("storageLocation") ?? ""), status: "dispatched", dispatchedBy: request.user!.uid, dispatchedAt: FieldValue.serverTimestamp(), createdAt: FieldValue.serverTimestamp()});
  batch.update(record.ref, {status: "inTransfer", currentCustodianId: input.destinationFacilityId, updatedAt: FieldValue.serverTimestamp()});
  await batch.commit(); response.status(201).json({data: {id: transfer.id, status: "dispatched"}});
});

router.get("/hazardous/records/:id/transfers", authenticate, requireRoles(...operators), async (request, response) => {
  const record = await hazardousRecord(id(request.params.id));
  const snapshot = await record.ref.collection("transfers").orderBy("createdAt", "desc").limit(300).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.patch("/hazardous/records/:id/disposal", authenticate, requireRoles(...supervisors), async (request, response) => {
  const input = z.object({facilityId: z.string().trim().min(1), facilityName: z.string().trim().min(2).max(300), method: z.string().trim().min(2).max(200), disposedWeightKg: z.number().positive(), manifestNumber: z.string().trim().min(2).max(100), complianceDocumentUrls: z.array(z.string().url()).min(1).max(10)}).parse(request.body);
  const record = await hazardousRecord(id(request.params.id));
  const remaining = number(record.snapshot.get("weightKg")) - number(record.snapshot.get("disposedWeightKg"));
  if (input.disposedWeightKg > remaining + 0.001) throw new ApiError(409, "Disposal weight exceeds the remaining hazardous waste.", "mass_balance_exceeded");
  const totalDisposed = number(record.snapshot.get("disposedWeightKg")) + input.disposedWeightKg;
  const completed = totalDisposed >= number(record.snapshot.get("weightKg")) - 0.001;
  await record.ref.update({...input, disposedWeightKg: totalDisposed, status: completed ? "disposed" : "stored", disposedBy: request.user!.uid, disposalRecordedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.json({data: {id: record.ref.id, disposedWeightKg: totalDisposed, status: completed ? "disposed" : "stored"}});
});

router.post("/hazardous/training-records", authenticate, requireRoles(...supervisors), async (request, response) => {
  const input = z.object({staffId: z.string().trim().min(1), courseName: z.string().trim().min(2).max(300), provider: z.string().trim().min(2).max(300), completedAt: z.coerce.date(), expiresAt: z.coerce.date(), certificateUrl: z.string().url()}).parse(request.body);
  if (input.expiresAt <= input.completedAt) throw new ApiError(400, "Training expiry must be after completion.", "invalid_argument");
  const ref = await db.collection("hazardousSafetyTraining").add({...input, completedAt: Timestamp.fromDate(input.completedAt), expiresAt: Timestamp.fromDate(input.expiresAt), recordedBy: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  response.status(201).json({data: {id: ref.id}});
});

router.get("/hazardous/training-records", authenticate, requireRoles(...operators), async (request, response) => {
  let query: FirebaseFirestore.Query = db.collection("hazardousSafetyTraining");
  if (typeof request.query.staffId === "string") query = query.where("staffId", "==", request.query.staffId);
  const snapshot = await query.limit(500).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.get("/hazardous/records/:id/certificate", authenticate, requireRoles(...operators), async (request, response) => {
  const record = await hazardousRecord(id(request.params.id));
  if (record.snapshot.get("status") !== "disposed") throw new ApiError(409, "A certificate is available only after complete disposal.", "invalid_state");
  response.json({data: {certificateNumber: `HAZ-CERT-${record.ref.id.substring(0, 10).toUpperCase()}`, issuedAt: new Date().toISOString(), record: documentJson(record.snapshot.id, record.snapshot.data()!)}});
});

router.get("/hazardous/reports/summary", authenticate, requireRoles(...operators), async (_request, response) => {
  const [records, incidents, training] = await Promise.all([db.collection("hazardousWasteRecords").limit(1000).get(), db.collection("hazardousIncidents").limit(1000).get(), db.collection("hazardousSafetyTraining").limit(1000).get()]);
  const byClassification: Record<string, number> = {}; let totalWeightKg = 0; let disposedWeightKg = 0;
  for (const doc of records.docs) { const classification = String(doc.get("classification") ?? "other"); const weight = number(doc.get("weightKg")); totalWeightKg += weight; disposedWeightKg += number(doc.get("disposedWeightKg")); byClassification[classification] = (byClassification[classification] ?? 0) + weight; }
  const openIncidents = incidents.docs.filter((doc) => doc.get("status") !== "closed").length;
  const now = Date.now(); const validTrainingRecords = training.docs.filter((doc) => doc.get("expiresAt")?.toDate?.().getTime() > now).length;
  response.json({data: {totalRecords: records.size, totalWeightKg, disposedWeightKg, safelyHandledPercent: totalWeightKg ? disposedWeightKg / totalWeightKg * 100 : 0, incidents: incidents.size, openIncidents, trainingRecords: training.size, validTrainingRecords, byClassification}});
});

export default router;
