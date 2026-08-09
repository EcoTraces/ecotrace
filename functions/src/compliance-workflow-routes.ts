import {Router} from "express";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {z} from "zod";
import {authenticate, requireRoles} from "./auth.js";
import {ApiError} from "./errors.js";
import {db} from "./firebase.js";
import {documentJson} from "./firestore-json.js";

const router = Router();
const managers = ["environmentalOfficer", "administrator", "superAdministrator"] as const;
const id = (value: string | string[]) => Array.isArray(value) ? value[0] : value;
const list = (collection: string) => async (_request: unknown, response: any) => {
  const snapshot = await db.collection(collection).limit(500).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
};

router.get("/compliance/documents", authenticate, requireRoles(...managers), list("complianceDocuments"));
router.post("/compliance/documents", authenticate, requireRoles(...managers), async (request, response) => {
  const input = z.object({
    type: z.string().trim().min(1), title: z.string().trim().min(2),
    referenceNumber: z.string().trim().min(1), entityName: z.string().trim().default(""),
    regulatoryBodyId: z.string().trim().default(""), regulatoryBodyName: z.string().trim().default(""),
    status: z.string().trim().default("valid"), documentUrls: z.array(z.string().url()).max(10).default([]),
    issuedAt: z.coerce.date().nullable().default(null), expiresAt: z.coerce.date().nullable().default(null),
    notes: z.string().trim().max(4000).default(""),
  }).parse(request.body);
  const ref = await db.collection("complianceDocuments").add({...input,
    issuedAt: input.issuedAt ? Timestamp.fromDate(input.issuedAt) : null,
    expiresAt: input.expiresAt ? Timestamp.fromDate(input.expiresAt) : null,
    createdBy: request.user!.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  });
  response.status(201).json({data: {id: ref.id}});
});
router.patch("/compliance/documents/:id/status", authenticate, requireRoles(...managers), async (request, response) => {
  const status = z.object({status: z.string().trim().min(1)}).parse(request.body).status;
  await db.collection("complianceDocuments").doc(id(request.params.id)).update({status,
    ...(status === "pendingReview" ? {submittedAt: FieldValue.serverTimestamp()} : {}),
    updatedAt: FieldValue.serverTimestamp()});
  response.json({data: {id: id(request.params.id), status}});
});

router.get("/compliance/requirements", authenticate, requireRoles(...managers), list("complianceRequirements"));
router.post("/compliance/requirements", authenticate, requireRoles(...managers), async (request, response) => {
  const input = z.object({category: z.string().trim().default("General"), title: z.string().trim().min(2),
    description: z.string().trim().max(4000).default(""), mandatory: z.boolean().default(true), active: z.boolean().default(true)}).parse(request.body);
  const ref = await db.collection("complianceRequirements").add({...input, createdBy: request.user!.uid,
    createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.status(201).json({data: {id: ref.id}});
});

router.patch("/compliance/inspections/:id/report", authenticate, requireRoles(...managers), async (request, response) => {
  const input = z.object({status: z.string().trim().min(1), checklist: z.record(z.string(), z.boolean()),
    score: z.number().min(0).max(100), findings: z.string().trim().max(4000), recommendations: z.string().trim().max(4000),
    reportUrls: z.array(z.string().url()).max(10).default([])}).parse(request.body);
  const ref = db.collection("complianceInspections").doc(id(request.params.id));
  if (!(await ref.get()).exists) throw new ApiError(404, "Inspection not found.", "not_found");
  await ref.update({...input, completedBy: request.user!.uid, completedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.json({data: {id: ref.id}});
});
router.patch("/compliance/violations/:id/corrective-action", authenticate, requireRoles(...managers), async (request, response) => {
  const input = z.object({plan: z.string().trim().min(2), owner: z.string().trim().min(1), dueAt: z.coerce.date()}).parse(request.body);
  const ref = db.collection("complianceViolations").doc(id(request.params.id));
  await ref.update({status: "correctiveAction", correctiveActionPlan: input.plan, correctiveActionOwner: input.owner,
    correctiveActionDueAt: Timestamp.fromDate(input.dueAt), updatedAt: FieldValue.serverTimestamp()});
  await db.collection("correctiveActionPlans").add({violationId: ref.id, title: input.plan, description: input.plan,
    owner: input.owner, dueAt: Timestamp.fromDate(input.dueAt), status: "open", createdBy: request.user!.uid,
    createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.json({data: {id: ref.id}});
});
router.patch("/compliance/violations/:id/resolve", authenticate, requireRoles(...managers), async (request, response) => {
  const evidence = z.object({evidence: z.string().trim().min(2)}).parse(request.body).evidence;
  const ref = db.collection("complianceViolations").doc(id(request.params.id));
  await ref.update({status: "resolved", resolutionEvidence: evidence, resolvedBy: request.user!.uid,
    resolvedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.json({data: {id: ref.id}});
});
router.patch("/compliance/penalties/:id/status", authenticate, requireRoles(...managers), async (request, response) => {
  const status = z.object({status: z.string().trim().min(1)}).parse(request.body).status;
  await db.collection("penaltyRecords").doc(id(request.params.id)).update({status, updatedAt: FieldValue.serverTimestamp()});
  response.json({data: {id: id(request.params.id), status}});
});

router.post("/compliance/expiry-alerts/scan", authenticate, requireRoles(...managers), async (_request, response) => {
  const sources = await Promise.all([
    db.collection("complianceDocuments").limit(500).get(), db.collection("complianceLicences").limit(500).get(),
    db.collection("recyclerCertifications").limit(500).get(), db.collection("environmentalCertificates").limit(500).get(),
  ]);
  const now = Date.now(); const horizon = now + 90 * 86400000;
  const alerts = sources.flatMap((snapshot) => snapshot.docs).flatMap((doc) => {
    const raw = doc.get("expiresAt"); const date = raw?.toDate ? raw.toDate() : raw ? new Date(raw) : null;
    if (!date || date.getTime() > horizon) return [];
    return [{id: doc.id, title: String(doc.get("title") ?? doc.get("licenseNumber") ?? doc.get("certificateNumber") ?? doc.id),
      dueAt: date.toISOString(), expired: date.getTime() < now, daysRemaining: Math.ceil((date.getTime() - now) / 86400000)}];
  });
  response.json({data: alerts.sort((a, b) => a.daysRemaining - b.daysRemaining)});
});

export default router;
