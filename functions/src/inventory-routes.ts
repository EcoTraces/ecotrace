import {Router} from "express";
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

const itemSchema = z.object({
  deviceType: z.string().trim().min(1).max(120), brand: z.string().trim().max(120).default(""),
  model: z.string().trim().max(120).default(""), serialNumber: z.string().trim().max(160).default(""),
  condition: z.enum(conditions), weight: z.number().nonnegative(), source: z.string().trim().min(1).max(300),
  location: z.string().trim().min(1).max(300), imageUrls: z.array(z.string().url()).max(5).default([]),
});
const assessmentSchema = z.object({
  category: z.enum(categories), materials: z.record(z.string(), z.number().min(0).max(100)),
  hazards: z.array(z.string().trim().min(1).max(200)).max(30), reusability: z.number().int().min(0).max(100),
  repairability: z.number().int().min(0).max(100), recommendation: z.enum(recommendations),
  recoveryValue: z.number().nonnegative(), confidence: z.number().min(0).max(1), notes: z.string().trim().max(2000).default(""),
});

function id(value: string | string[]) { return Array.isArray(value) ? value[0] : value; }
async function itemRef(itemId: string) {
  const ref = db.collection("inventoryItems").doc(itemId);
  if (!(await ref.get()).exists) throw new ApiError(404, "Inventory item not found.", "not_found");
  return ref;
}

router.get("/inventory/items", authenticate, async (_request, response) => {
  const snapshot = await db.collection("inventoryItems").limit(500).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});
router.get("/inventory/items/by-code/:code", authenticate, async (request, response) => {
  const snapshot = await db.collection("inventoryItems").where("itemCode", "==", id(request.params.code)).limit(1).get();
  if (snapshot.empty) throw new ApiError(404, "Inventory item not found.", "not_found");
  response.json({data: documentJson(snapshot.docs[0].id, snapshot.docs[0].data())});
});
router.post("/inventory/items", authenticate, requireRoles(...operators), async (request, response) => {
  const input = itemSchema.parse(request.body);
  const ref = db.collection("inventoryItems").doc();
  const code = `ECO-${new Date().getUTCFullYear()}-${ref.id.slice(0, 8).toUpperCase()}`;
  const batch = db.batch();
  batch.set(ref, {...input, itemCode: code, currentLocation: input.location, processingStatus: "registered", batchId: null, barcodeValue: code, createdBy: request.user!.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  batch.set(ref.collection("history").doc(), {action: "registered", details: `Item registered at ${input.location}`, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  await batch.commit();
  response.status(201).json({data: {id: ref.id, itemCode: code}});
});
router.get("/inventory/items/:id/history", authenticate, async (request, response) => {
  const ref = await itemRef(id(request.params.id));
  const snapshot = await ref.collection("history").orderBy("createdAt", "desc").limit(200).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});
router.patch("/inventory/items/:id/state", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({status: z.enum(statuses), location: z.string().trim().min(1).max(300)}).parse(request.body);
  const ref = await itemRef(id(request.params.id));
  const batch = db.batch();
  batch.update(ref, {processingStatus: input.status, currentLocation: input.location, updatedAt: FieldValue.serverTimestamp()});
  batch.set(ref.collection("history").doc(), {action: "statusUpdated", details: `${input.status} at ${input.location}`, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
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
  await ref.set({batchCode: `BAT-${ref.id.slice(0, 8).toUpperCase()}`, name: input.name, currentLocation: input.location, processingStatus: "registered", itemCount: 0, totalWeight: 0, createdBy: request.user!.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.status(201).json({data: {id: ref.id}});
});
router.patch("/inventory/items/:id/batch", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({batchId: z.string().trim().min(1)}).parse(request.body);
  const ref = await itemRef(id(request.params.id));
  if (!(await db.collection("inventoryBatches").doc(input.batchId).get()).exists) throw new ApiError(404, "Inventory batch not found.", "not_found");
  const batch = db.batch();
  batch.update(ref, {batchId: input.batchId, updatedAt: FieldValue.serverTimestamp()});
  batch.set(ref.collection("history").doc(), {action: "batchAssigned", details: `Assigned to batch ${input.batchId}`, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  await batch.commit();
  response.json({data: {id: ref.id, batchId: input.batchId}});
});

router.get("/inventory/items/:id/assessments", authenticate, async (request, response) => {
  const ref = await itemRef(id(request.params.id));
  const snapshot = await ref.collection("assessments").orderBy("createdAt", "desc").limit(100).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});
router.post("/inventory/items/:id/assessments", authenticate, requireRoles(...operators), async (request, response) => {
  const input = assessmentSchema.parse(request.body); const ref = await itemRef(id(request.params.id));
  const assessment = ref.collection("assessments").doc(); const batch = db.batch();
  batch.set(assessment, {...input, status: "pendingSupervisor", createdBy: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  batch.set(ref.collection("history").doc(), {action: "assessmentSubmitted", details: `${input.category}: ${input.recommendation}`, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  await batch.commit(); response.status(201).json({data: {id: assessment.id}});
});
router.patch("/inventory/items/:id/assessments/:assessmentId/review", authenticate, requireRoles(...reviewers), async (request, response) => {
  const input = z.object({approved: z.boolean(), reason: z.string().trim().max(1000).nullable().optional()}).parse(request.body);
  const ref = (await itemRef(id(request.params.id))).collection("assessments").doc(id(request.params.assessmentId));
  if (!(await ref.get()).exists) throw new ApiError(404, "Assessment not found.", "not_found");
  await ref.update({status: input.approved ? "approved" : "rejected", reviewReason: input.reason ?? null, reviewedBy: request.user!.uid, reviewedAt: FieldValue.serverTimestamp()});
  response.json({data: {id: ref.id, status: input.approved ? "approved" : "rejected"}});
});

router.get("/inventory/items/:id/traceability", authenticate, async (request, response) => {
  const ref = await itemRef(id(request.params.id)); const snapshot = await ref.collection("traceability").orderBy("createdAt", "desc").limit(200).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});
router.post("/inventory/items/:id/traceability", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({type: z.string().trim().min(1).max(100), destination: z.string().trim().min(1).max(300), actor: z.string().trim().max(160).default(""), notes: z.string().trim().max(2000).default(""), updateLocation: z.boolean().default(true)}).parse(request.body);
  const ref = await itemRef(id(request.params.id)); const snapshot = await ref.get(); const from = String(snapshot.get("currentLocation") ?? ""); const event = ref.collection("traceability").doc(); const batch = db.batch();
  if (input.updateLocation) batch.update(ref, {currentLocation: input.destination, updatedAt: FieldValue.serverTimestamp()});
  batch.set(event, {type: input.type, from, to: input.destination, actor: input.actor || request.user!.uid, notes: input.notes, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  batch.set(ref.collection("history").doc(), {action: input.type, details: `${from} -> ${input.destination}: ${input.notes}`, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  await batch.commit(); response.status(201).json({data: {id: event.id}});
});

export default router;
