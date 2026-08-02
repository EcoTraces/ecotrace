import {Router} from "express";
import {FieldValue} from "firebase-admin/firestore";
import {z} from "zod";
import {authenticate, requireRoles} from "./auth.js";
import {ApiError} from "./errors.js";
import {db} from "./firebase.js";
import {documentJson} from "./firestore-json.js";
import {publishNotificationEvent} from "./push-events.js";

const router = Router();
const operators = ["recycler", "environmentalOfficer", "administrator", "superAdministrator"] as const;
const supervisors = ["environmentalOfficer", "administrator", "superAdministrator"] as const;
const stages = ["created", "sorting", "dismantling", "componentSeparation", "materialRecovery", "hazardousHandling", "finalDisposal", "verification", "completed"] as const;

function id(value: string | string[]) { return Array.isArray(value) ? value[0] : value; }
function number(value: unknown) { return Number(value ?? 0); }
function accounted(data: FirebaseFirestore.DocumentData) {
  return number(data.recoveredWeightKg) + number(data.hazardousWeightKg) + number(data.disposedWeightKg) + number(data.processingLossKg);
}
async function batchRef(batchId: string) {
  const ref = db.collection("recyclingBatches").doc(batchId);
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new ApiError(404, "Recycling batch not found.", "not_found");
  return {ref, snapshot};
}

router.get("/recycling/batches", authenticate, requireRoles(...operators), async (request, response) => {
  let query: FirebaseFirestore.Query = db.collection("recyclingBatches");
  if (typeof request.query.stage === "string" && stages.includes(request.query.stage as typeof stages[number])) {
    query = query.where("stage", "==", request.query.stage);
  }
  const snapshot = await query.limit(500).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.get("/recycling/batches/:id", authenticate, requireRoles(...operators), async (request, response) => {
  const batch = await batchRef(id(request.params.id));
  response.json({data: documentJson(batch.snapshot.id, batch.snapshot.data()!)});
});

router.post("/recycling/batches", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({
    itemIds: z.array(z.string().trim().min(1)).min(1).max(500),
    facilityId: z.string().trim().min(1).max(200),
    facilityName: z.string().trim().min(1).max(200),
  }).parse(request.body);
  const uniqueIds = [...new Set(input.itemIds)];
  const itemRefs = uniqueIds.map((itemId) => db.collection("inventoryItems").doc(itemId));
  const items = await db.getAll(...itemRefs);
  if (items.some((item) => !item.exists)) throw new ApiError(404, "One or more inventory items were not found.", "not_found");
  if (items.some((item) => item.get("recyclingBatchId"))) throw new ApiError(409, "One or more items already belong to a recycling batch.", "conflict");
  const inputWeightKg = items.reduce((sum, item) => sum + number(item.get("weight")), 0);
  if (inputWeightKg <= 0) throw new ApiError(422, "Batch input weight must be positive.", "validation_error");
  const ref = db.collection("recyclingBatches").doc();
  const write = db.batch();
  write.set(ref, {
    batchCode: `REC-${ref.id.substring(0, 8).toUpperCase()}`,
    facilityId: input.facilityId,
    facilityName: input.facilityName,
    itemIds: uniqueIds,
    itemCodes: items.map((item) => String(item.get("itemCode") ?? item.id)),
    inputWeightKg,
    recoveredWeightKg: 0,
    hazardousWeightKg: 0,
    disposedWeightKg: 0,
    processingLossKg: 0,
    stage: "created",
    completionVerified: false,
    verificationNotes: "",
    createdBy: request.user!.uid,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  for (const item of items) {
    write.update(item.ref, {processingStatus: "assignedForRecycling", recyclingBatchId: ref.id, updatedAt: FieldValue.serverTimestamp()});
    write.set(item.ref.collection("history").doc(), {action: "recyclingBatchAssigned", details: `Assigned to ${ref.id} at ${input.facilityName}`, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  }
  await write.commit();
  response.status(201).json({data: {id: ref.id, batchCode: `REC-${ref.id.substring(0, 8).toUpperCase()}`, inputWeightKg}});
});

router.patch("/recycling/batches/:id/facility", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({facilityId: z.string().trim().min(1).max(200), facilityName: z.string().trim().min(1).max(200)}).parse(request.body);
  const batch = await batchRef(id(request.params.id));
  await batch.ref.update({...input, updatedAt: FieldValue.serverTimestamp()});
  response.json({data: {id: batch.ref.id, ...input}});
});

router.patch("/recycling/batches/:id/stage", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({stage: z.enum(stages)}).parse(request.body);
  const batch = await batchRef(id(request.params.id));
  const current = stages.indexOf(String(batch.snapshot.get("stage")) as typeof stages[number]);
  const next = stages.indexOf(input.stage);
  if (next < current && input.stage !== "hazardousHandling") throw new ApiError(409, "Processing stages cannot move backwards.", "invalid_state");
  if (input.stage === "completed") throw new ApiError(409, "Use completion verification to complete a batch.", "invalid_state");
  const write = db.batch();
  write.update(batch.ref, {stage: input.stage, updatedAt: FieldValue.serverTimestamp()});
  write.set(batch.ref.collection("processRecords").doc(), {type: "stageUpdated", material: "", component: input.stage, quantity: 0, weightKg: 0, notes: `Processing stage changed to ${input.stage}`, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  await write.commit();
  response.json({data: {id: batch.ref.id, stage: input.stage}});
});

router.get("/recycling/batches/:id/process-records", authenticate, requireRoles(...operators), async (request, response) => {
  const batch = await batchRef(id(request.params.id));
  const snapshot = await batch.ref.collection("processRecords").orderBy("createdAt", "desc").limit(500).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.post("/recycling/batches/:id/process-records", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({type: z.string().trim().min(1).max(100), material: z.string().trim().max(200).default(""), component: z.string().trim().max(200).default(""), quantity: z.number().int().nonnegative(), weightKg: z.number().nonnegative(), notes: z.string().trim().max(2000).default("")}).parse(request.body);
  const batch = await batchRef(id(request.params.id));
  const ref = await batch.ref.collection("processRecords").add({...input, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  response.status(201).json({data: {id: ref.id}});
});

router.post("/recycling/batches/:id/outputs", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({kind: z.enum(["recovered", "hazardous"]), material: z.string().trim().min(1).max(200), component: z.string().trim().max(200).default(""), quantity: z.number().int().nonnegative().default(0), weightKg: z.number().positive(), notes: z.string().trim().max(2000).default("")}).parse(request.body);
  const ref = db.collection("recyclingBatches").doc(id(request.params.id));
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw new ApiError(404, "Recycling batch not found.", "not_found");
    if (accounted(snapshot.data()!) + input.weightKg > number(snapshot.get("inputWeightKg")) + 0.001) throw new ApiError(409, "Output weight exceeds the available batch balance.", "mass_balance_exceeded");
    const field = input.kind === "recovered" ? "recoveredWeightKg" : "hazardousWeightKg";
    const stage = input.kind === "recovered" ? "materialRecovery" : "hazardousHandling";
    transaction.update(ref, {[field]: FieldValue.increment(input.weightKg), stage, updatedAt: FieldValue.serverTimestamp()});
    transaction.set(ref.collection("processRecords").doc(), {type: input.kind === "recovered" ? "materialRecovered" : "hazardousMaterialHandled", material: input.material, component: input.component, quantity: input.quantity, weightKg: input.weightKg, notes: input.notes, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  });
  response.status(201).json({data: {id: ref.id, kind: input.kind, weightKg: input.weightKg}});
});

router.post("/recycling/batches/:id/losses", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({weightKg: z.number().positive(), reason: z.string().trim().min(1).max(2000)}).parse(request.body);
  const ref = db.collection("recyclingBatches").doc(id(request.params.id));
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw new ApiError(404, "Recycling batch not found.", "not_found");
    if (accounted(snapshot.data()!) + input.weightKg > number(snapshot.get("inputWeightKg")) + 0.001) throw new ApiError(409, "Loss exceeds the available batch balance.", "mass_balance_exceeded");
    transaction.update(ref, {processingLossKg: FieldValue.increment(input.weightKg), updatedAt: FieldValue.serverTimestamp()});
    transaction.set(ref.collection("processRecords").doc(), {type: "processingLoss", material: "", component: "", quantity: 0, weightKg: input.weightKg, notes: input.reason, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  });
  response.status(201).json({data: {id: ref.id, weightKg: input.weightKg}});
});

router.get("/recycling/batches/:id/disposals", authenticate, requireRoles(...operators), async (request, response) => {
  const batch = await batchRef(id(request.params.id));
  const snapshot = await batch.ref.collection("finalDisposals").orderBy("createdAt", "desc").limit(500).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.post("/recycling/batches/:id/disposals", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({material: z.string().trim().min(1).max(200), weightKg: z.number().positive(), facility: z.string().trim().min(1).max(300), method: z.string().trim().min(1).max(300), manifestNumber: z.string().trim().min(1).max(200)}).parse(request.body);
  const ref = db.collection("recyclingBatches").doc(id(request.params.id));
  const disposal = ref.collection("finalDisposals").doc();
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw new ApiError(404, "Recycling batch not found.", "not_found");
    if (accounted(snapshot.data()!) + input.weightKg > number(snapshot.get("inputWeightKg")) + 0.001) throw new ApiError(409, "Disposal weight exceeds the available batch balance.", "mass_balance_exceeded");
    transaction.update(ref, {disposedWeightKg: FieldValue.increment(input.weightKg), stage: "finalDisposal", updatedAt: FieldValue.serverTimestamp()});
    transaction.set(disposal, {...input, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  });
  response.status(201).json({data: {id: disposal.id}});
});

router.patch("/recycling/batches/:id/verify", authenticate, requireRoles(...supervisors), async (request, response) => {
  const input = z.object({notes: z.string().trim().min(1).max(3000)}).parse(request.body);
  const ref = db.collection("recyclingBatches").doc(id(request.params.id));
  let itemIds: string[] = [];
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw new ApiError(404, "Recycling batch not found.", "not_found");
    const inputWeight = number(snapshot.get("inputWeightKg"));
    const balance = accounted(snapshot.data()!);
    if (balance > inputWeight + 0.001) throw new ApiError(409, "Recorded outputs exceed the batch input weight.", "mass_balance_exceeded");
    if (inputWeight - balance > inputWeight * 0.02) throw new ApiError(409, "Account for all but at most 2% of the input weight.", "mass_balance_incomplete");
    itemIds = (snapshot.get("itemIds") ?? []).map(String);
    transaction.update(ref, {stage: "completed", completionVerified: true, verificationNotes: input.notes, verifiedBy: request.user!.uid, verifiedAt: FieldValue.serverTimestamp(), completedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
    for (const itemId of itemIds) {
      const itemRef = db.collection("inventoryItems").doc(itemId);
      transaction.update(itemRef, {processingStatus: "recovered", updatedAt: FieldValue.serverTimestamp()});
      transaction.set(itemRef.collection("history").doc(), {action: "recyclingCompleted", details: `Recycling completed in ${ref.id}`, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
    }
  });
  const items = itemIds.length ? await db.getAll(...itemIds.map((itemId) => db.collection("inventoryItems").doc(itemId))) : [];
  const affectedUserIds = [...new Set(items.flatMap((item) => [item.get("userId"), item.get("sourceUserId")]).filter(Boolean).map(String))];
  void publishNotificationEvent({event: "recycling_completed", affectedUserIds, data: {batchId: ref.id, itemIds}});
  response.json({data: {id: ref.id, stage: "completed", completionVerified: true}});
});

router.get("/recycling/batches/:id/certificate", authenticate, requireRoles(...operators), async (request, response) => {
  const batch = await batchRef(id(request.params.id));
  if (batch.snapshot.get("completionVerified") !== true) throw new ApiError(409, "The batch must be verified before a certificate is generated.", "invalid_state");
  const data = batch.snapshot.data()!;
  response.json({data: {certificateNumber: `ECO-REC-${batch.ref.id.toUpperCase()}`, batchId: batch.ref.id, batchCode: data.batchCode, facilityName: data.facilityName, inputWeightKg: number(data.inputWeightKg), recoveredWeightKg: number(data.recoveredWeightKg), hazardousWeightKg: number(data.hazardousWeightKg), disposedWeightKg: number(data.disposedWeightKg), processingLossKg: number(data.processingLossKg), recoveryEfficiencyPercent: number(data.inputWeightKg) ? number(data.recoveredWeightKg) / number(data.inputWeightKg) * 100 : 0, verifiedBy: data.verifiedBy, verifiedAt: documentJson(batch.ref.id, {value: data.verifiedAt}).value}});
});

router.get("/recycling/reports/summary", authenticate, requireRoles(...operators), async (_request, response) => {
  const snapshot = await db.collection("recyclingBatches").limit(1000).get();
  const totals = snapshot.docs.reduce((value, doc) => {
    const data = doc.data();
    value.inputWeightKg += number(data.inputWeightKg); value.recoveredWeightKg += number(data.recoveredWeightKg);
    value.hazardousWeightKg += number(data.hazardousWeightKg); value.disposedWeightKg += number(data.disposedWeightKg);
    value.processingLossKg += number(data.processingLossKg); if (data.completionVerified === true) value.completedBatches++;
    return value;
  }, {totalBatches: snapshot.size, completedBatches: 0, inputWeightKg: 0, recoveredWeightKg: 0, hazardousWeightKg: 0, disposedWeightKg: 0, processingLossKg: 0});
  response.json({data: {...totals, recoveryEfficiencyPercent: totals.inputWeightKg ? totals.recoveredWeightKg / totals.inputWeightKg * 100 : 0}});
});

export default router;
