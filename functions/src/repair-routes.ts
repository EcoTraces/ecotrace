import {Router} from "express";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {z} from "zod";
import {authenticate, requireRoles} from "./auth.js";
import {ApiError} from "./errors.js";
import {db} from "./firebase.js";
import {documentJson} from "./firestore-json.js";
import {publishNotificationEvent} from "./push-events.js";

const router = Router();
const technicians = ["repairTechnician", "administrator", "superAdministrator"] as const;
const supervisors = ["administrator", "superAdministrator"] as const;
const statuses = ["awaitingAssessment", "diagnosed", "approved", "repairInProgress", "qualityTesting", "completed", "rejected", "unrepairable"] as const;
const grades = ["gradeA", "gradeB", "gradeC", "partsOnly"] as const;

function id(value: string | string[]) { return Array.isArray(value) ? value[0] : value; }
async function jobRef(jobId: string) {
  const ref = db.collection("repairJobs").doc(jobId);
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new ApiError(404, "Repair job not found.", "not_found");
  return {ref, snapshot};
}
async function assertTechnicianAccess(jobId: string, uid: string, role: string) {
  const job = await jobRef(jobId);
  if (role === "repairTechnician" && job.snapshot.get("technicianId") !== uid) {
    throw new ApiError(403, "This repair job is assigned to another technician.", "permission_denied");
  }
  return job;
}
function assertStatus(snapshot: FirebaseFirestore.DocumentSnapshot, allowed: readonly string[], action: string) {
  const current = String(snapshot.get("status") ?? "");
  if (!allowed.includes(current)) throw new ApiError(409, `${action} is not allowed while the repair is ${current}.`, "invalid_state");
}
async function assertActiveTechnician(technicianId: string) {
  const technician = await db.collection("users").doc(technicianId).get();
  if (!technician.exists) throw new ApiError(404, "Repair technician not found.", "technician_not_found");
  if (technician.get("role") !== "repairTechnician") throw new ApiError(409, "The selected user is not a repair technician.", "invalid_technician_role");
  if (technician.get("accountStatus") !== "active") throw new ApiError(409, "The selected repair technician is not active.", "inactive_technician");
}
function progress(batch: FirebaseFirestore.WriteBatch, ref: FirebaseFirestore.DocumentReference, type: string, details: string, percent: number, actorId: string) {
  batch.set(ref.collection("progress").doc(), {type, details, progressPercent: percent, actorId, createdAt: FieldValue.serverTimestamp()});
}

router.get("/repairs", authenticate, requireRoles(...technicians), async (request, response) => {
  let query: FirebaseFirestore.Query = db.collection("repairJobs");
  if (request.user!.role === "repairTechnician") query = query.where("technicianId", "==", request.user!.uid);
  if (typeof request.query.status === "string" && statuses.includes(request.query.status as typeof statuses[number])) query = query.where("status", "==", request.query.status);
  const snapshot = await query.limit(500).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.get("/repairs/summary", authenticate, requireRoles(...technicians), async (request, response) => {
  let query: FirebaseFirestore.Query = db.collection("repairJobs");
  if (request.user!.role === "repairTechnician") query = query.where("technicianId", "==", request.user!.uid);
  const snapshot = await query.limit(1000).get();
  const jobs = snapshot.docs;
  const byStatus = Object.fromEntries(statuses.map((status) => [status, jobs.filter((job) => job.get("status") === status).length]));
  const completed = jobs.filter((job) => job.get("status") === "completed");
  response.json({data: {
    total: jobs.length,
    byStatus,
    estimatedRepairCost: jobs.reduce((sum, job) => sum + Number(job.get("estimatedRepairCost") ?? 0), 0),
    actualPartsCost: jobs.reduce((sum, job) => sum + Number(job.get("actualPartsCost") ?? 0), 0),
    refurbishedInventory: completed.length,
    activeWarranties: completed.filter((job) => job.get("warrantyEnd")?.toDate?.().getTime() > Date.now()).length,
    donationApproved: completed.filter((job) => job.get("dispositionApproved") === true && job.get("disposition") === "donation").length,
    resaleApproved: completed.filter((job) => job.get("dispositionApproved") === true && job.get("disposition") === "resale").length,
  }});
});

router.get("/repairs/refurbished-inventory", authenticate, requireRoles(...technicians), async (request, response) => {
  let query: FirebaseFirestore.Query = db.collection("repairJobs").where("status", "==", "completed");
  if (request.user!.role === "repairTechnician") query = query.where("technicianId", "==", request.user!.uid);
  const snapshot = await query.limit(500).get();
  response.json({data: snapshot.docs.map((document) => documentJson(document.id, document.data()))});
});

router.get("/repairs/:id", authenticate, requireRoles(...technicians), async (request, response) => {
  const job = await assertTechnicianAccess(id(request.params.id), request.user!.uid, request.user!.role);
  response.json({data: documentJson(job.snapshot.id, job.snapshot.data()!)});
});

router.post("/repairs", authenticate, requireRoles(...technicians), async (request, response) => {
  const input = z.object({itemId: z.string().trim().min(1), assessmentNotes: z.string().trim().min(1).max(3000), technicianId: z.string().trim().default("")}).parse(request.body);
  const itemRef = db.collection("inventoryItems").doc(input.itemId); const item = await itemRef.get();
  if (!item.exists) throw new ApiError(404, "Inventory item not found.", "not_found");
  if (!["repairable", "refurbishable"].includes(String(item.get("condition") ?? ""))) throw new ApiError(409, "Only repairable or refurbishable inventory can enter repair assessment.", "invalid_item_condition");
  if (["repairing", "refurbished", "assignedForRecycling", "recycling", "recovered", "disposed"].includes(String(item.get("processingStatus") ?? ""))) throw new ApiError(409, "The inventory item is already in a terminal or conflicting workflow.", "invalid_item_state");
  const existing = await db.collection("repairJobs").where("itemId", "==", input.itemId).get();
  if (existing.docs.some((doc) => !["completed", "rejected", "unrepairable"].includes(String(doc.get("status"))))) throw new ApiError(409, "This item already has an active repair job.", "conflict");
  const ref = db.collection("repairJobs").doc(); const batch = db.batch();
  const technicianId = request.user!.role === "repairTechnician" ? request.user!.uid : input.technicianId;
  if (technicianId) await assertActiveTechnician(technicianId);
  batch.set(ref, {itemId: input.itemId, itemCode: item.get("itemCode") ?? "", deviceName: `${item.get("brand") ?? ""} ${item.get("model") ?? ""}`.trim(), status: "awaitingAssessment", assessmentNotes: input.assessmentNotes, diagnosis: "", faults: [], technicianId, estimatedRepairCost: 0, actualPartsCost: 0, progressPercent: 0, qualityChecks: {}, qualityNotes: "", refurbishmentGrade: null, warrantyStart: null, warrantyEnd: null, disposition: "pending", dispositionApproved: false, resalePrice: null, donationRecipient: "", createdBy: request.user!.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  batch.update(itemRef, {processingStatus: "inspecting", updatedAt: FieldValue.serverTimestamp()});
  batch.set(itemRef.collection("history").doc(), {action: "repairAssessmentCreated", details: `Repair job ${ref.id} created`, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  progress(batch, ref, "assessmentCreated", input.assessmentNotes, 0, request.user!.uid); await batch.commit();
  response.status(201).json({data: {id: ref.id}});
});

router.patch("/repairs/:id/assignment", authenticate, requireRoles(...supervisors), async (request, response) => {
  const input = z.object({technicianId: z.string().trim().min(1)}).parse(request.body); const job = await jobRef(id(request.params.id)); const batch = db.batch();
  assertStatus(job.snapshot, ["awaitingAssessment", "diagnosed", "approved", "repairInProgress"], "Technician assignment");
  await assertActiveTechnician(input.technicianId);
  batch.update(job.ref, {technicianId: input.technicianId, updatedAt: FieldValue.serverTimestamp()}); progress(batch, job.ref, "technicianAssigned", `Assigned to ${input.technicianId}`, Number(job.snapshot.get("progressPercent") ?? 0), request.user!.uid); await batch.commit();
  void publishNotificationEvent({event: "repair_technician_assigned", recipientId: input.technicianId, data: {repairJobId: job.ref.id}});
  response.json({data: {id: job.ref.id, technicianId: input.technicianId}});
});

router.patch("/repairs/:id/diagnosis", authenticate, requireRoles(...technicians), async (request, response) => {
  const input = z.object({diagnosis: z.string().trim().min(1).max(3000), faults: z.array(z.string().trim().min(1).max(300)).min(1).max(50), estimatedRepairCost: z.number().nonnegative()}).parse(request.body); const job = await assertTechnicianAccess(id(request.params.id), request.user!.uid, request.user!.role); const batch = db.batch();
  assertStatus(job.snapshot, ["awaitingAssessment", "diagnosed"], "Diagnosis");
  if (!job.snapshot.get("technicianId")) throw new ApiError(409, "Assign a technician before diagnosis.", "technician_required");
  batch.update(job.ref, {...input, status: "diagnosed", diagnosedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}); progress(batch, job.ref, "diagnosed", `${input.faults.length} fault(s); estimate ${input.estimatedRepairCost}`, Number(job.snapshot.get("progressPercent") ?? 0), request.user!.uid); await batch.commit(); response.json({data: {id: job.ref.id, status: "diagnosed"}});
});

router.patch("/repairs/:id/review", authenticate, requireRoles(...supervisors), async (request, response) => {
  const input = z.object({approved: z.boolean(), notes: z.string().trim().max(2000).default("")}).parse(request.body); const job = await jobRef(id(request.params.id)); const itemRef = db.collection("inventoryItems").doc(String(job.snapshot.get("itemId"))); const status = input.approved ? "approved" : "rejected"; const batch = db.batch();
  assertStatus(job.snapshot, ["diagnosed"], "Repair review");
  batch.update(job.ref, {status, repairApproved: input.approved, repairApprovedBy: request.user!.uid, repairApprovalNotes: input.notes, repairApprovedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}); batch.update(itemRef, {processingStatus: input.approved ? "assignedForRepair" : "inspecting", updatedAt: FieldValue.serverTimestamp()}); progress(batch, job.ref, input.approved ? "repairApproved" : "repairRejected", input.notes, Number(job.snapshot.get("progressPercent") ?? 0), request.user!.uid); await batch.commit(); response.json({data: {id: job.ref.id, status}});
  void publishNotificationEvent({event: "repair_reviewed", recipientId: String(job.snapshot.get("technicianId")), data: {repairJobId: job.ref.id, status}});
});

router.patch("/repairs/:id/start", authenticate, requireRoles(...technicians), async (request, response) => {
  const job = await assertTechnicianAccess(id(request.params.id), request.user!.uid, request.user!.role); if (job.snapshot.get("status") !== "approved") throw new ApiError(409, "Only approved repairs can be started.", "invalid_state"); const batch = db.batch(); batch.update(job.ref, {status: "repairInProgress", progressPercent: 10, repairStartedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}); batch.update(db.collection("inventoryItems").doc(String(job.snapshot.get("itemId"))), {processingStatus: "repairing", updatedAt: FieldValue.serverTimestamp()}); progress(batch, job.ref, "repairStarted", "Repair work started", 10, request.user!.uid); await batch.commit(); response.json({data: {id: job.ref.id, status: "repairInProgress"}});
});

router.get("/repairs/:id/parts", authenticate, requireRoles(...technicians), async (request, response) => { const job = await assertTechnicianAccess(id(request.params.id), request.user!.uid, request.user!.role); const snapshot = await job.ref.collection("parts").orderBy("recordedAt", "desc").limit(200).get(); response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))}); });
router.post("/repairs/:id/parts", authenticate, requireRoles(...technicians), async (request, response) => {
  const input = z.object({name: z.string().trim().min(1).max(200), partNumber: z.string().trim().max(120).default(""), quantity: z.number().int().positive(), unitCost: z.number().nonnegative()}).parse(request.body); const job = await assertTechnicianAccess(id(request.params.id), request.user!.uid, request.user!.role); assertStatus(job.snapshot, ["repairInProgress"], "Recording spare parts"); const part = job.ref.collection("parts").doc(); const batch = db.batch(); batch.set(part, {...input, recordedBy: request.user!.uid, recordedAt: FieldValue.serverTimestamp()}); batch.update(job.ref, {actualPartsCost: FieldValue.increment(input.quantity * input.unitCost), updatedAt: FieldValue.serverTimestamp()}); await batch.commit(); response.status(201).json({data: {id: part.id}});
});

router.get("/repairs/:id/progress", authenticate, requireRoles(...technicians), async (request, response) => { const job = await assertTechnicianAccess(id(request.params.id), request.user!.uid, request.user!.role); const snapshot = await job.ref.collection("progress").orderBy("createdAt", "desc").limit(300).get(); response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))}); });
router.patch("/repairs/:id/progress", authenticate, requireRoles(...technicians), async (request, response) => {
  const input = z.object({progressPercent: z.number().int().min(10).max(95), details: z.string().trim().min(1).max(2000)}).parse(request.body); const job = await assertTechnicianAccess(id(request.params.id), request.user!.uid, request.user!.role); assertStatus(job.snapshot, ["repairInProgress"], "Progress updates"); const current = Number(job.snapshot.get("progressPercent") ?? 0); if (input.progressPercent <= current) throw new ApiError(409, "Progress must increase.", "invalid_state"); const batch = db.batch(); batch.update(job.ref, {progressPercent: input.progressPercent, updatedAt: FieldValue.serverTimestamp()}); progress(batch, job.ref, "progressUpdated", input.details, input.progressPercent, request.user!.uid); await batch.commit(); response.json({data: {id: job.ref.id, progressPercent: input.progressPercent}});
});

router.patch("/repairs/:id/quality-testing", authenticate, requireRoles(...technicians), async (request, response) => { const job = await assertTechnicianAccess(id(request.params.id), request.user!.uid, request.user!.role); assertStatus(job.snapshot, ["repairInProgress"], "Quality testing"); const batch = db.batch(); batch.update(job.ref, {status: "qualityTesting", progressPercent: 95, qualityTestingStartedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}); progress(batch, job.ref, "qualityTestingStarted", "Repair submitted for quality control", 95, request.user!.uid); await batch.commit(); response.json({data: {id: job.ref.id, status: "qualityTesting"}}); });
router.patch("/repairs/:id/quality-control", authenticate, requireRoles(...technicians), async (request, response) => {
  const input = z.object({checks: z.record(z.string(), z.boolean()).refine((x) => Object.keys(x).length > 0), notes: z.string().trim().max(2000).default(""), grade: z.enum(grades), warrantyMonths: z.number().int().min(0).max(120)}).superRefine((value, context) => { if (Object.values(value.checks).every(Boolean) && value.grade !== "partsOnly" && value.warrantyMonths < 1) context.addIssue({code: "custom", message: "A passing refurbished device requires a warranty."}); }).parse(request.body); const job = await assertTechnicianAccess(id(request.params.id), request.user!.uid, request.user!.role); assertStatus(job.snapshot, ["qualityTesting"], "Quality control"); const passed = Object.values(input.checks).every(Boolean); const start = new Date(); const end = new Date(start); end.setMonth(end.getMonth() + input.warrantyMonths); const batch = db.batch(); batch.update(job.ref, {status: passed ? "completed" : "repairInProgress", progressPercent: passed ? 100 : 80, qualityChecks: input.checks, qualityNotes: input.notes, qualityTestedBy: request.user!.uid, qualityTestedAt: FieldValue.serverTimestamp(), ...(passed ? {refurbishmentGrade: input.grade, warrantyStart: Timestamp.fromDate(start), warrantyEnd: Timestamp.fromDate(end), completedAt: FieldValue.serverTimestamp()} : {}), updatedAt: FieldValue.serverTimestamp()}); batch.update(db.collection("inventoryItems").doc(String(job.snapshot.get("itemId"))), {processingStatus: passed ? "refurbished" : "repairing", ...(passed ? {condition: "working"} : {}), updatedAt: FieldValue.serverTimestamp()}); progress(batch, job.ref, passed ? "qualityPassed" : "qualityFailed", input.notes, passed ? 100 : 80, request.user!.uid); await batch.commit(); if (passed) void publishNotificationEvent({event: "repair_completed", recipientId: String(job.snapshot.get("technicianId")), data: {repairJobId: job.ref.id, grade: input.grade}}); response.json({data: {id: job.ref.id, passed, status: passed ? "completed" : "repairInProgress"}});
});

router.patch("/repairs/:id/unrepairable", authenticate, requireRoles(...technicians), async (request, response) => { const input = z.object({reason: z.string().trim().min(1).max(2000)}).parse(request.body); const job = await assertTechnicianAccess(id(request.params.id), request.user!.uid, request.user!.role); assertStatus(job.snapshot, ["awaitingAssessment", "diagnosed", "approved", "repairInProgress", "qualityTesting"], "Marking an item unrepairable"); const batch = db.batch(); batch.update(job.ref, {status: "unrepairable", unrepairableReason: input.reason, unrepairableBy: request.user!.uid, closedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}); batch.update(db.collection("inventoryItems").doc(String(job.snapshot.get("itemId"))), {processingStatus: "assignedForRecycling", condition: "recyclable", updatedAt: FieldValue.serverTimestamp()}); progress(batch, job.ref, "markedUnrepairable", input.reason, Number(job.snapshot.get("progressPercent") ?? 0), request.user!.uid); await batch.commit(); void publishNotificationEvent({event: "repair_unrepairable", recipientId: String(job.snapshot.get("technicianId") || request.user!.uid), data: {repairJobId: job.ref.id, reason: input.reason}}); response.json({data: {id: job.ref.id, status: "unrepairable"}}); });
router.patch("/repairs/:id/warranty", authenticate, requireRoles(...supervisors), async (request, response) => { const input = z.object({warrantyEnd: z.coerce.date().refine((value) => value.getTime() > Date.now(), "Warranty expiry must be in the future.")}).parse(request.body); const job = await jobRef(id(request.params.id)); assertStatus(job.snapshot, ["completed"], "Warranty management"); const batch = db.batch(); batch.update(job.ref, {warrantyEnd: Timestamp.fromDate(input.warrantyEnd), updatedAt: FieldValue.serverTimestamp()}); progress(batch, job.ref, "warrantyUpdated", `Warranty valid until ${input.warrantyEnd.toISOString()}`, Number(job.snapshot.get("progressPercent") ?? 0), request.user!.uid); await batch.commit(); response.json({data: {id: job.ref.id}}); });
router.patch("/repairs/:id/disposition", authenticate, requireRoles(...supervisors), async (request, response) => { const input = z.object({disposition: z.enum(["donation", "resale"]), resalePrice: z.number().positive().nullable().optional(), donationRecipient: z.string().trim().max(300).default(""), notes: z.string().trim().max(2000).default("")}).superRefine((x, context) => { if (x.disposition === "resale" && x.resalePrice == null) context.addIssue({code: "custom", message: "A positive resale price is required."}); if (x.disposition === "donation" && !x.donationRecipient) context.addIssue({code: "custom", message: "Donation recipient is required."}); }).parse(request.body); const job = await jobRef(id(request.params.id)); assertStatus(job.snapshot, ["completed"], "Donation or resale approval"); const batch = db.batch(); batch.update(job.ref, {disposition: input.disposition, dispositionApproved: true, dispositionApprovedBy: request.user!.uid, dispositionApprovedAt: FieldValue.serverTimestamp(), dispositionNotes: input.notes, resalePrice: input.disposition === "resale" ? input.resalePrice : null, donationRecipient: input.disposition === "donation" ? input.donationRecipient : "", updatedAt: FieldValue.serverTimestamp()}); progress(batch, job.ref, "dispositionApproved", `${input.disposition}: ${input.notes}`, 100, request.user!.uid); await batch.commit(); void publishNotificationEvent({event: "repair_disposition_approved", recipientId: String(job.snapshot.get("technicianId")), data: {repairJobId: job.ref.id, disposition: input.disposition}}); response.json({data: {id: job.ref.id, disposition: input.disposition}}); });

export default router;
