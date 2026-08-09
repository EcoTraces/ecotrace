import {Router} from "express";
import {createHash} from "node:crypto";
import {FieldValue} from "firebase-admin/firestore";
import {z} from "zod";
import {authenticate, requireRoles} from "./auth.js";
import {ApiError} from "./errors.js";
import {db} from "./firebase.js";
import {documentJson} from "./firestore-json.js";

const router = Router();
const operators = ["administrator", "superAdministrator", "collector", "collectionCentreOperator", "repairTechnician", "recycler"] as const;
const reviewers = ["administrator", "superAdministrator", "environmentalOfficer"] as const;
const conditions = ["working", "repairable", "reusable", "refurbishable", "recyclable", "hazardous", "nonRecoverable"] as const;
const statuses = ["registered", "received", "inspecting", "sorted", "stored", "assignedForRepair", "repairing", "refurbished", "assignedForRecycling", "recycling", "recovered", "disposed", "quarantined"] as const;
const categories = ["mobilePhones", "laptops", "desktopComputers", "televisions", "printers", "batteries", "accessories", "networkingEquipment", "householdAppliances", "industrialElectronics"] as const;
const recommendations = ["reuse", "repair", "refurbish", "recycle", "hazardousDisposal", "finalDisposal"] as const;
const traceEventTypes = [
  "movement", "statusUpdated", "collectorAssigned", "facilityAssigned",
  "custodyTransfer", "receiptVerified", "damaged", "missing",
] as const;

const itemSchema = z.object({
  deviceType: z.string().trim().min(1).max(120), brand: z.string().trim().max(120).default(""),
  model: z.string().trim().max(120).default(""), serialNumber: z.string().trim().max(160).default(""),
  condition: z.enum(conditions), weight: z.number().nonnegative(), source: z.string().trim().min(1).max(300),
  sourceId: z.string().trim().max(160).nullable().optional(),
  location: z.string().trim().min(1).max(300), imageUrls: z.array(z.string().url()).max(5).default([]),
});
const itemUpdateSchema = z.object({
  deviceType: z.string().trim().min(1).max(120).optional(),
  brand: z.string().trim().max(120).optional(),
  model: z.string().trim().max(120).optional(),
  serialNumber: z.string().trim().max(160).optional(),
  condition: z.enum(conditions).optional(),
  weight: z.number().nonnegative().optional(),
  source: z.string().trim().min(1).max(300).optional(),
  sourceId: z.string().trim().max(160).nullable().optional(),
}).refine((input) => Object.keys(input).length > 0, {
  message: "At least one item field must be supplied.",
});
const assessmentSchema = z.object({
  category: z.enum(categories), materials: z.record(z.string(), z.number().min(0).max(100)),
  hazards: z.array(z.string().trim().min(1).max(200)).max(30), reusability: z.number().int().min(0).max(100),
  repairability: z.number().int().min(0).max(100), recommendation: z.enum(recommendations),
  assessedCondition: z.enum(conditions).optional(),
  recoveryValue: z.number().nonnegative(), confidence: z.number().min(0).max(1),
  origin: z.enum(["manual", "aiAssisted"]).default("manual"),
  notes: z.string().trim().max(2000).default(""),
}).superRefine((input, context) => {
  const total = Object.values(input.materials).reduce((sum, value) => sum + value, 0);
  if (Math.abs(total - 100) > 1) context.addIssue({
    code: "custom",
    path: ["materials"],
    message: "Material composition percentages must total 100% (±1%).",
  });
  if (input.recommendation === "hazardousDisposal" && input.hazards.length === 0) {
    context.addIssue({
      code: "custom",
      path: ["hazards"],
      message: "Hazardous disposal requires at least one identified hazard.",
    });
  }
});

function id(value: string | string[]) { return Array.isArray(value) ? value[0] : value; }
async function itemRef(itemId: string) {
  const ref = db.collection("inventoryItems").doc(itemId);
  if (!(await ref.get()).exists) throw new ApiError(404, "Inventory item not found.", "not_found");
  return ref;
}

async function ensureSerialNumberAvailable(serialNumber: string, exceptId = "") {
  const normalized = serialNumber.trim().toUpperCase();
  if (!normalized) return "";
  const [normalizedSnapshot, legacySnapshot] = await Promise.all([
    db.collection("inventoryItems")
      .where("serialNumberNormalized", "==", normalized).limit(2).get(),
    db.collection("inventoryItems")
      .where("serialNumber", "==", serialNumber.trim()).limit(2).get(),
  ]);
  if ([...normalizedSnapshot.docs, ...legacySnapshot.docs]
    .some((document) => document.id !== exceptId)) {
    throw new ApiError(409, "An inventory item with this serial number already exists.", "duplicate_serial_number");
  }
  return normalized;
}

async function assignItemToBatch(
  itemId: string,
  batchId: string | null,
  actorId: string,
) {
  const item = db.collection("inventoryItems").doc(itemId);
  await db.runTransaction(async (transaction) => {
    const itemSnapshot = await transaction.get(item);
    if (!itemSnapshot.exists) throw new ApiError(404, "Inventory item not found.", "not_found");
    const previousBatchId = String(itemSnapshot.get("batchId") ?? "");
    if (previousBatchId === (batchId ?? "")) return;
    const newBatch = batchId ? db.collection("inventoryBatches").doc(batchId) : null;
    const oldBatch = previousBatchId ? db.collection("inventoryBatches").doc(previousBatchId) : null;
    if (newBatch) {
      const newBatchSnapshot = await transaction.get(newBatch);
      if (!newBatchSnapshot.exists) throw new ApiError(404, "Inventory batch not found.", "not_found");
      if (newBatchSnapshot.get("closed") === true) {
        throw new ApiError(409, "The selected inventory batch is closed.", "batch_closed");
      }
    }
    const weight = Number(itemSnapshot.get("weight") ?? 0);
    if (oldBatch) transaction.update(oldBatch, {
      itemCount: FieldValue.increment(-1),
      totalWeight: FieldValue.increment(-weight),
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (newBatch) transaction.update(newBatch, {
      itemCount: FieldValue.increment(1),
      totalWeight: FieldValue.increment(weight),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(item, {
      batchId,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(item.collection("history").doc(), {
      action: batchId ? "batchAssigned" : "batchUnassigned",
      details: batchId ? `Assigned to batch ${batchId}` : `Removed from batch ${previousBatchId}`,
      actorId,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
}

function csvValue(value: unknown) {
  const text = value == null ? "" : String(value);
  return `"${text.replaceAll('"', '""')}"`;
}

function traceHash(value: Record<string, unknown>) {
  const canonical = Object.fromEntries(Object.entries(value).sort(([left], [right]) => left.localeCompare(right)));
  return createHash("sha256").update(JSON.stringify(canonical)).digest("hex");
}

router.get("/inventory/items", authenticate, async (request, response) => {
  const filters = z.object({
    query: z.string().trim().max(160).optional(),
    condition: z.enum(conditions).optional(),
    status: z.enum(statuses).optional(),
    batchId: z.string().trim().max(160).optional(),
    location: z.string().trim().max(300).optional(),
    limit: z.coerce.number().int().min(1).max(500).default(200),
  }).parse(request.query);
  let query: FirebaseFirestore.Query = db.collection("inventoryItems");
  if (filters.condition) query = query.where("condition", "==", filters.condition);
  if (filters.status) query = query.where("processingStatus", "==", filters.status);
  if (filters.batchId) query = query.where("batchId", "==", filters.batchId);
  const snapshot = await query.limit(500).get();
  const needle = filters.query?.toLowerCase();
  const locationNeedle = filters.location?.toLowerCase();
  const data = snapshot.docs
    .map((doc) => documentJson(doc.id, doc.data()))
    .filter((item) => !needle || [item.itemCode, item.deviceType, item.brand, item.model, item.serialNumber]
      .some((value) => String(value ?? "").toLowerCase().includes(needle)))
    .filter((item) => !locationNeedle || String(item.currentLocation ?? "").toLowerCase().includes(locationNeedle))
    .sort((a, b) => String(a.itemCode).localeCompare(String(b.itemCode)))
    .slice(0, filters.limit);
  response.json({data, meta: {count: data.length, limit: filters.limit}});
});
router.get("/inventory/summary", authenticate, async (_request, response) => {
  const [items, batches] = await Promise.all([
    db.collection("inventoryItems").limit(5000).get(),
    db.collection("inventoryBatches").limit(1000).get(),
  ]);
  const byCondition: Record<string, number> = {};
  const byStatus: Record<string, number> = {};
  let totalWeight = 0;
  for (const item of items.docs) {
    const condition = String(item.get("condition") ?? "unknown");
    const status = String(item.get("processingStatus") ?? "unknown");
    byCondition[condition] = (byCondition[condition] ?? 0) + 1;
    byStatus[status] = (byStatus[status] ?? 0) + 1;
    totalWeight += Number(item.get("weight") ?? 0);
  }
  response.json({data: {
    totalItems: items.size,
    totalWeightKg: Math.round(totalWeight * 1000) / 1000,
    batchedItems: items.docs.filter((item) => Boolean(item.get("batchId"))).length,
    batches: batches.size,
    byCondition,
    byStatus,
  }});
});
router.get("/inventory/export", authenticate, async (request, response) => {
  const {format} = z.object({format: z.enum(["csv", "json"]).default("csv")}).parse(request.query);
  const snapshot = await db.collection("inventoryItems").limit(5000).get();
  const data = snapshot.docs.map((doc) => documentJson(doc.id, doc.data()));
  if (format === "json") {
    response.setHeader("Content-Disposition", "attachment; filename=ecotrace-inventory.json");
    response.json({data});
    return;
  }
  const columns = ["id", "itemCode", "deviceType", "brand", "model", "serialNumber", "condition", "weight", "source", "currentLocation", "processingStatus", "batchId", "barcodeValue"];
  const rows = [columns.join(","), ...data.map((item) => columns.map((column) => csvValue(item[column])).join(","))];
  response.type("text/csv");
  response.setHeader("Content-Disposition", "attachment; filename=ecotrace-inventory.csv");
  response.send(rows.join("\r\n"));
});
router.get("/inventory/items/by-code/:code", authenticate, async (request, response) => {
  const code = id(request.params.code).trim().toUpperCase();
  let snapshot = await db.collection("inventoryItems").where("itemCode", "==", code).limit(1).get();
  if (snapshot.empty) snapshot = await db.collection("inventoryItems").where("barcodeValue", "==", code).limit(1).get();
  if (snapshot.empty) throw new ApiError(404, "Inventory item not found.", "not_found");
  response.json({data: documentJson(snapshot.docs[0].id, snapshot.docs[0].data())});
});
router.get("/inventory/items/:id", authenticate, async (request, response) => {
  const ref = await itemRef(id(request.params.id));
  const snapshot = await ref.get();
  response.json({data: documentJson(snapshot.id, snapshot.data()!)});
});
router.post("/inventory/items", authenticate, requireRoles(...operators), async (request, response) => {
  const input = itemSchema.parse(request.body);
  const serialNumberNormalized = await ensureSerialNumberAvailable(input.serialNumber);
  const ref = db.collection("inventoryItems").doc();
  const code = `ECO-${new Date().getUTCFullYear()}-${ref.id.slice(0, 8).toUpperCase()}`;
  const batch = db.batch();
  batch.set(ref, {...input, serialNumberNormalized, itemCode: code, currentLocation: input.location, processingStatus: "registered", batchId: null, barcodeValue: code, qrPayload: `ecotrace://inventory/${code}`, createdBy: request.user!.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  batch.set(ref.collection("history").doc(), {action: "registered", details: `Item registered at ${input.location}`, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  await batch.commit();
  response.status(201).json({data: {id: ref.id, itemCode: code}});
});
router.patch("/inventory/items/:id", authenticate, requireRoles(...operators), async (request, response) => {
  const input = itemUpdateSchema.parse(request.body);
  const ref = await itemRef(id(request.params.id));
  const before = await ref.get();
  const update: Record<string, unknown> = {...input, updatedAt: FieldValue.serverTimestamp()};
  if (input.serialNumber !== undefined) {
    update.serialNumberNormalized = await ensureSerialNumberAvailable(input.serialNumber, ref.id);
  }
  await db.runTransaction(async (transaction) => {
    if (input.weight !== undefined && before.get("batchId")) {
      const delta = input.weight - Number(before.get("weight") ?? 0);
      transaction.update(db.collection("inventoryBatches").doc(String(before.get("batchId"))), {
        totalWeight: FieldValue.increment(delta),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    transaction.update(ref, update);
    transaction.set(ref.collection("history").doc(), {
      action: "detailsUpdated",
      details: `Updated fields: ${Object.keys(input).join(", ")}`,
      actorId: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  response.json({data: {id: ref.id}});
});
router.patch("/inventory/items/:id/images", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({imageUrls: z.array(z.string().url()).max(5)}).parse(request.body);
  const ref = await itemRef(id(request.params.id));
  const batch = db.batch();
  batch.update(ref, {imageUrls: input.imageUrls, updatedAt: FieldValue.serverTimestamp()});
  batch.set(ref.collection("history").doc(), {
    action: "imagesUpdated",
    details: `${input.imageUrls.length} item image(s) attached`,
    actorId: request.user!.uid,
    createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  response.json({data: {id: ref.id, imageUrls: input.imageUrls}});
});
router.get("/inventory/items/:id/code", authenticate, async (request, response) => {
  const ref = await itemRef(id(request.params.id));
  const snapshot = await ref.get();
  const itemCode = String(snapshot.get("itemCode") ?? ref.id);
  response.json({data: {
    id: ref.id,
    itemCode,
    barcodeValue: snapshot.get("barcodeValue") ?? itemCode,
    qrPayload: snapshot.get("qrPayload") ?? `ecotrace://inventory/${itemCode}`,
  }});
});
router.get("/inventory/items/:id/history", authenticate, async (request, response) => {
  const ref = await itemRef(id(request.params.id));
  const snapshot = await ref.collection("history").orderBy("createdAt", "desc").limit(200).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});
router.patch("/inventory/items/:id/state", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({status: z.enum(statuses), location: z.string().trim().min(1).max(300)}).parse(request.body);
  const ref = await itemRef(id(request.params.id));
  const before = await ref.get();
  const batch = db.batch();
  batch.update(ref, {processingStatus: input.status, currentLocation: input.location, updatedAt: FieldValue.serverTimestamp()});
  batch.set(ref.collection("history").doc(), {action: "statusUpdated", details: `${String(before.get("processingStatus") ?? "unknown")} -> ${input.status}; ${String(before.get("currentLocation") ?? "unknown")} -> ${input.location}`, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  await batch.commit();
  response.json({data: {id: ref.id, ...input}});
});

router.get("/inventory/batches", authenticate, async (_request, response) => {
  const snapshot = await db.collection("inventoryBatches").limit(300).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});
router.post("/inventory/batches", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({name: z.string().trim().min(1).max(150), location: z.string().trim().min(1).max(300)}).parse(request.body);
  const ref = db.collection("inventoryBatches").doc();
  const batchCode = `BAT-${ref.id.slice(0, 8).toUpperCase()}`;
  await ref.set({batchCode, name: input.name, currentLocation: input.location, processingStatus: "registered", itemCount: 0, totalWeight: 0, closed: false, createdBy: request.user!.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.status(201).json({data: {id: ref.id, batchCode}});
});
router.get("/inventory/batches/:id", authenticate, async (request, response) => {
  const ref = db.collection("inventoryBatches").doc(id(request.params.id));
  const [snapshot, items] = await Promise.all([
    ref.get(),
    db.collection("inventoryItems").where("batchId", "==", ref.id).limit(500).get(),
  ]);
  if (!snapshot.exists) throw new ApiError(404, "Inventory batch not found.", "not_found");
  response.json({data: {
    ...documentJson(snapshot.id, snapshot.data()!),
    items: items.docs.map((item) => documentJson(item.id, item.data())),
  }});
});
router.patch("/inventory/batches/:id", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({
    name: z.string().trim().min(1).max(150).optional(),
    location: z.string().trim().min(1).max(300).optional(),
    status: z.enum(statuses).optional(),
    closed: z.boolean().optional(),
  }).refine((value) => Object.keys(value).length > 0).parse(request.body);
  const ref = db.collection("inventoryBatches").doc(id(request.params.id));
  if (!(await ref.get()).exists) throw new ApiError(404, "Inventory batch not found.", "not_found");
  await ref.update({
    ...(input.name !== undefined ? {name: input.name} : {}),
    ...(input.location !== undefined ? {currentLocation: input.location} : {}),
    ...(input.status !== undefined ? {processingStatus: input.status} : {}),
    ...(input.closed !== undefined ? {closed: input.closed} : {}),
    updatedAt: FieldValue.serverTimestamp(),
  });
  response.json({data: {id: ref.id}});
});
router.patch("/inventory/items/:id/batch", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({batchId: z.string().trim().min(1).nullable()}).parse(request.body);
  const itemId = id(request.params.id);
  await assignItemToBatch(itemId, input.batchId, request.user!.uid);
  response.json({data: {id: itemId, batchId: input.batchId}});
});
router.post("/inventory/batches/:id/items", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({itemIds: z.array(z.string().trim().min(1)).min(1).max(100)}).parse(request.body);
  const batchId = id(request.params.id);
  for (const itemId of [...new Set(input.itemIds)]) {
    await assignItemToBatch(itemId, batchId, request.user!.uid);
  }
  response.json({data: {batchId, assigned: [...new Set(input.itemIds)].length}});
});

router.get("/inventory/items/:id/assessments", authenticate, async (request, response) => {
  const ref = await itemRef(id(request.params.id));
  const snapshot = await ref.collection("assessments").orderBy("createdAt", "desc").limit(100).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});
router.post("/inventory/items/:id/assessments", authenticate, requireRoles(...operators), async (request, response) => {
  const input = assessmentSchema.parse(request.body); const ref = await itemRef(id(request.params.id));
  const [item, previous] = await Promise.all([ref.get(), ref.collection("assessments").get()]);
  const assessment = ref.collection("assessments").doc(); const batch = db.batch();
  batch.set(assessment, {
    ...input,
    assessedCondition: input.assessedCondition ?? item.get("condition"),
    status: "pendingSupervisor",
    version: previous.size + 1,
    currency: "SLE",
    imageUrlsAtAssessment: item.get("imageUrls") ?? [],
    createdBy: request.user!.uid,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  batch.update(ref, {processingStatus: "inspecting", updatedAt: FieldValue.serverTimestamp()});
  batch.set(ref.collection("history").doc(), {action: "assessmentSubmitted", details: `${input.category}: ${input.recommendation}`, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  await batch.commit(); response.status(201).json({data: {id: assessment.id}});
});
router.get("/inventory/items/:id/assessments/:assessmentId", authenticate, async (request, response) => {
  const ref = (await itemRef(id(request.params.id))).collection("assessments").doc(id(request.params.assessmentId));
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new ApiError(404, "Assessment not found.", "not_found");
  response.json({data: documentJson(snapshot.id, snapshot.data()!)});
});
router.patch("/inventory/items/:id/assessments/:assessmentId", authenticate, requireRoles(...operators), async (request, response) => {
  const input = assessmentSchema.partial().refine((value) => Object.keys(value).length > 0).parse(request.body);
  if (input.materials) {
    const total = Object.values(input.materials).reduce((sum, value) => sum + value, 0);
    if (Math.abs(total - 100) > 1) throw new ApiError(400, "Material composition must total 100% (±1%).", "invalid_material_composition");
  }
  const root = await itemRef(id(request.params.id));
  const ref = root.collection("assessments").doc(id(request.params.assessmentId));
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new ApiError(404, "Assessment not found.", "not_found");
  const administrator = ["administrator", "superAdministrator"].includes(request.user!.role);
  if (snapshot.get("status") !== "pendingSupervisor") {
    throw new ApiError(409, "Only pending assessments can be edited.", "assessment_not_pending");
  }
  if (!administrator && snapshot.get("createdBy") !== request.user!.uid) {
    throw new ApiError(403, "Only the assessor can edit this assessment.", "forbidden");
  }
  const batch = db.batch();
  batch.update(ref, {...input, updatedAt: FieldValue.serverTimestamp()});
  batch.set(root.collection("history").doc(), {
    action: "assessmentUpdated",
    details: `Assessment ${ref.id} updated`,
    actorId: request.user!.uid,
    createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  response.json({data: {id: ref.id, status: "pendingSupervisor"}});
});
router.patch("/inventory/items/:id/assessments/:assessmentId/review", authenticate, requireRoles(...reviewers), async (request, response) => {
  const input = z.object({approved: z.boolean(), reason: z.string().trim().max(1000).nullable().optional()}).superRefine((value, context) => {
    if (!value.approved && !value.reason?.trim()) context.addIssue({code: "custom", path: ["reason"], message: "A rejection reason is required."});
  }).parse(request.body);
  const root = await itemRef(id(request.params.id));
  const ref = root.collection("assessments").doc(id(request.params.assessmentId));
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new ApiError(404, "Assessment not found.", "not_found");
  if (snapshot.get("status") !== "pendingSupervisor") {
    throw new ApiError(409, "This assessment has already been reviewed.", "already_reviewed");
  }
  const status = input.approved ? "approved" : "rejected";
  const batch = db.batch();
  batch.update(ref, {
    status,
    reviewReason: input.reason ?? null,
    reviewedBy: request.user!.uid,
    reviewedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  if (input.approved) {
    const recommendation = String(snapshot.get("recommendation"));
    const assessedCondition = String(snapshot.get("assessedCondition") ?? "recyclable");
    batch.update(root, {
      approvedAssessmentId: ref.id,
      category: snapshot.get("category"),
      materialComposition: snapshot.get("materials"),
      identifiedHazards: snapshot.get("hazards"),
      condition: recommendation === "hazardousDisposal" ? "hazardous" : assessedCondition,
      treatmentRecommendation: recommendation,
      estimatedRecoveryValue: snapshot.get("recoveryValue"),
      classificationConfidence: snapshot.get("confidence"),
      processingStatus: recommendation === "hazardousDisposal" ? "quarantined" : "sorted",
      classifiedAt: FieldValue.serverTimestamp(),
      classifiedBy: request.user!.uid,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  batch.set(root.collection("history").doc(), {
    action: input.approved ? "assessmentApproved" : "assessmentRejected",
    details: input.approved ?
      `${snapshot.get("category")}: ${snapshot.get("recommendation")}` :
      String(input.reason),
    assessmentId: ref.id,
    actorId: request.user!.uid,
    createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  response.json({data: {id: ref.id, status}});
});

router.get("/inventory/items/:id/traceability", authenticate, async (request, response) => {
  const ref = await itemRef(id(request.params.id));
  const snapshot = await ref.collection("traceability").orderBy("createdAt", "desc").limit(500).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});
router.post("/inventory/items/:id/traceability", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({
    type: z.enum(traceEventTypes),
    destination: z.string().trim().min(1).max(300),
    actor: z.string().trim().max(160).default(""),
    custodianId: z.string().trim().max(160).nullable().optional(),
    facilityId: z.string().trim().max(160).nullable().optional(),
    status: z.enum(statuses).optional(),
    notes: z.string().trim().max(2000).default(""),
    evidenceUrls: z.array(z.string().url()).max(10).default([]),
    updateLocation: z.boolean().default(true),
  }).superRefine((value, context) => {
    if (value.type === "collectorAssigned" && !value.custodianId) context.addIssue({code: "custom", path: ["custodianId"], message: "A collector is required."});
    if (value.type === "facilityAssigned" && !value.facilityId) context.addIssue({code: "custom", path: ["facilityId"], message: "A facility is required."});
    if (value.type === "statusUpdated" && !value.status) context.addIssue({code: "custom", path: ["status"], message: "A processing status is required."});
    if (["damaged", "missing"].includes(value.type) && !value.notes) context.addIssue({code: "custom", path: ["notes"], message: "Exception details are required."});
  }).parse(request.body);
  const ref = await itemRef(id(request.params.id));
  const event = ref.collection("traceability").doc();
  let sequence = 0;
  let integrityHash = "";
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const from = String(snapshot.get("currentLocation") ?? "");
    sequence = Number(snapshot.get("traceSequence") ?? 0) + 1;
    const previousHash = String(snapshot.get("lastTraceHash") ?? "");
    const recordedAt = new Date().toISOString();
    const eventData = {
      ...input,
      from,
      to: input.destination,
      actor: input.actor || request.user!.uid,
      actorId: request.user!.uid,
      sequence,
      previousHash,
      recordedAt,
    };
    integrityHash = traceHash(eventData);
    const itemUpdate: Record<string, unknown> = {
      traceSequence: sequence,
      lastTraceHash: integrityHash,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (input.updateLocation) itemUpdate.currentLocation = input.destination;
    if (input.status) itemUpdate.processingStatus = input.status;
    if (input.custodianId !== undefined) itemUpdate.currentCustodianId = input.custodianId;
    if (input.facilityId !== undefined) itemUpdate.assignedFacilityId = input.facilityId;
    if (input.type === "receiptVerified") {
      itemUpdate.receiptVerified = true;
      itemUpdate.receivedBy = request.user!.uid;
      itemUpdate.receivedAt = FieldValue.serverTimestamp();
    }
    if (input.type === "damaged" || input.type === "missing") {
      itemUpdate.traceabilityException = input.type;
      itemUpdate.traceabilityExceptionNotes = input.notes;
      if (input.type === "damaged") itemUpdate.processingStatus = "quarantined";
    }
    transaction.update(ref, itemUpdate);
    transaction.set(event, {...eventData, integrityHash, createdAt: FieldValue.serverTimestamp()});
    transaction.set(ref.collection("history").doc(), {
      action: input.type,
      details: `${from} -> ${input.destination}: ${input.notes}`,
      traceEventId: event.id,
      actorId: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  response.status(201).json({data: {id: event.id, sequence, integrityHash}});
});
router.post("/inventory/items/:id/traceability/assign", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({
    assignmentType: z.enum(["collector", "facility"]),
    assigneeId: z.string().trim().min(1).max(160),
    assigneeName: z.string().trim().min(1).max(200),
    destination: z.string().trim().min(1).max(300),
    notes: z.string().trim().max(1000).default(""),
  }).parse(request.body);
  const itemId = id(request.params.id);
  const payload = {
    type: input.assignmentType === "collector" ? "collectorAssigned" : "facilityAssigned",
    destination: input.destination,
    actor: input.assigneeName,
    ...(input.assignmentType === "collector" ? {custodianId: input.assigneeId} : {facilityId: input.assigneeId}),
    notes: input.notes,
    updateLocation: false,
  };
  const ref = await itemRef(itemId);
  const event = ref.collection("traceability").doc();
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const sequence = Number(snapshot.get("traceSequence") ?? 0) + 1;
    const previousHash = String(snapshot.get("lastTraceHash") ?? "");
    const recordedAt = new Date().toISOString();
    const eventData = {
      ...payload,
      from: String(snapshot.get("currentLocation") ?? ""),
      to: input.destination,
      actorId: request.user!.uid,
      sequence,
      previousHash,
      recordedAt,
    };
    const integrityHash = traceHash(eventData);
    transaction.update(ref, {
      ...(input.assignmentType === "collector" ? {currentCustodianId: input.assigneeId, currentCustodianName: input.assigneeName} : {assignedFacilityId: input.assigneeId, assignedFacilityName: input.assigneeName}),
      traceSequence: sequence,
      lastTraceHash: integrityHash,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(event, {...eventData, integrityHash, createdAt: FieldValue.serverTimestamp()});
    transaction.set(ref.collection("history").doc(), {
      action: payload.type,
      details: `${input.assigneeName} assigned for ${input.destination}`,
      traceEventId: event.id,
      actorId: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  response.status(201).json({data: {id: event.id, itemId, ...payload}});
});
router.get("/inventory/items/:id/traceability/audit", authenticate, async (request, response) => {
  const ref = await itemRef(id(request.params.id));
  const [item, trace, history] = await Promise.all([
    ref.get(),
    ref.collection("traceability").orderBy("createdAt", "asc").limit(1000).get(),
    ref.collection("history").orderBy("createdAt", "asc").limit(1000).get(),
  ]);
  let previousHash = "";
  const integrityIssues: string[] = [];
  for (const document of trace.docs) {
    const data = document.data();
    if (!data.integrityHash) continue;
    const hashPayload = {...data};
    delete hashPayload.integrityHash;
    delete hashPayload.createdAt;
    if (String(data.previousHash ?? "") !== previousHash) integrityIssues.push(document.id);
    const calculated = traceHash(hashPayload);
    if (calculated !== data.integrityHash) integrityIssues.push(document.id);
    previousHash = String(data.integrityHash);
  }
  response.json({data: {
    item: documentJson(item.id, item.data()!),
    chainOfCustody: trace.docs.map((doc) => documentJson(doc.id, doc.data())),
    itemHistory: history.docs.map((doc) => documentJson(doc.id, doc.data())),
    integrityVerified: integrityIssues.length === 0,
    integrityIssues: [...new Set(integrityIssues)],
  }});
});
router.get("/inventory/items/:id/traceability/certificate", authenticate, async (request, response) => {
  const ref = await itemRef(id(request.params.id));
  const [item, events] = await Promise.all([
    ref.get(),
    ref.collection("traceability").orderBy("createdAt", "asc").limit(1000).get(),
  ]);
  response.json({data: {
    certificateNumber: `TRACE-${ref.id.substring(0, 10).toUpperCase()}`,
    issuedAt: new Date().toISOString(),
    item: documentJson(item.id, item.data()!),
    lifecycle: "Pickup -> Collection Centre -> Assessment -> Repair or Recycling -> Resource Recovery -> Final Disposal",
    chainOfCustody: events.docs.map((doc) => documentJson(doc.id, doc.data())),
    finalIntegrityHash: item.get("lastTraceHash") ?? null,
  }});
});

export default router;
