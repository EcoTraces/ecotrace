import {Router} from "express";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {z} from "zod";
import {authenticate, requireRoles} from "./auth.js";
import {ApiError} from "./errors.js";
import {db} from "./firebase.js";
import {documentJson} from "./firestore-json.js";
import {publishNotificationEvent} from "./push-events.js";

const router = Router();
const managers = ["environmentalOfficer", "administrator", "superAdministrator"] as const;
const operators = ["collectionCentreOperator", "repairTechnician", "recycler", "environmentalOfficer", "administrator", "superAdministrator"] as const;
const serviceCategories = ["recycling", "repair", "refurbishment", "materialBuyer", "transport", "hazardousDisposal", "collectionCentre", "other"] as const;

function id(value: string | string[]) { return Array.isArray(value) ? value[0] : value; }
function number(value: unknown) { return Number(value ?? 0); }
async function partnerRecord(partnerId: string) {
  const ref = db.collection("partners").doc(partnerId); const snapshot = await ref.get();
  if (!snapshot.exists) throw new ApiError(404, "Partner not found.", "not_found");
  return {ref, snapshot};
}

router.get("/partners", authenticate, requireRoles(...operators), async (request, response) => {
  let query: FirebaseFirestore.Query = db.collection("partners");
  if (typeof request.query.status === "string") query = query.where("status", "==", request.query.status);
  if (typeof request.query.serviceCategory === "string") query = query.where("serviceCategories", "array-contains", request.query.serviceCategory);
  const snapshot = await query.limit(500).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.get("/partners/:id", authenticate, requireRoles(...operators), async (request, response) => {
  const partner = await partnerRecord(id(request.params.id));
  response.json({data: documentJson(partner.snapshot.id, partner.snapshot.data()!)});
});

router.post("/partners", authenticate, requireRoles(...managers), async (request, response) => {
  const input = z.object({name: z.string().trim().min(2).max(300), registrationNumber: z.string().trim().min(2).max(100).optional(), type: z.string().trim().max(80).default("serviceProvider"), contactName: z.string().trim().min(2).max(200), contactEmail: z.string().trim().email(), contactPhone: z.string().trim().min(5).max(50), address: z.string().trim().min(2).max(500), serviceCategories: z.array(z.enum(serviceCategories)).min(1), serviceAreas: z.array(z.string().trim().min(2).max(200)).min(1), facilityCapacityKg: z.number().nonnegative(), pricingInformation: z.string().trim().max(2000).default(""), paymentMethod: z.string().trim().max(100).default(""), payeeName: z.string().trim().max(200).default(""), paymentTerms: z.string().trim().max(1000).default(""), paymentCurrency: z.string().trim().length(3).default("SLE")}).parse(request.body);
  if (input.registrationNumber) {
    const duplicate = await db.collection("partners").where("registrationNumber", "==", input.registrationNumber).limit(1).get();
    if (!duplicate.empty) throw new ApiError(409, "A partner with this registration number already exists.", "conflict");
  }
  const ref = db.collection("partners").doc();
  await ref.set({...input, registrationNumber: input.registrationNumber ?? `REG-${ref.id.substring(0, 8).toUpperCase()}`, currency: input.paymentCurrency, partnerCode: `PTR-${ref.id.substring(0, 8).toUpperCase()}`, status: "pendingVerification", licenceVerified: false, licenceStatus: "pending", suspensionReason: "", complianceScore: 0, performanceRating: 0, ratingCount: 0, completedServiceCount: 0, onTimeServiceCount: 0, totalSpend: 0, activeContractCount: 0, pricing: {}, paymentInformation: {}, createdBy: request.user!.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.status(201).json({data: {id: ref.id, partnerCode: `PTR-${ref.id.substring(0, 8).toUpperCase()}`}});
});

router.patch("/partners/:id/profile", authenticate, requireRoles(...managers), async (request, response) => {
  const input = z.object({contactName: z.string().trim().min(2).max(200).optional(), contactEmail: z.string().trim().email().optional(), contactPhone: z.string().trim().min(5).max(50).optional(), address: z.string().trim().min(2).max(500).optional(), serviceCategories: z.array(z.enum(serviceCategories)).min(1).optional(), serviceAreas: z.array(z.string().trim().min(2).max(200)).min(1).optional(), facilityCapacityKg: z.number().nonnegative().optional()}).refine((value) => Object.keys(value).length > 0, "At least one profile field is required.").parse(request.body);
  const partner = await partnerRecord(id(request.params.id)); await partner.ref.update({...input, updatedBy: request.user!.uid, updatedAt: FieldValue.serverTimestamp()});
  response.json({data: {id: partner.ref.id}});
});

router.post("/partners/:id/documents", authenticate, requireRoles(...managers), async (request, response) => {
  const input = z.object({type: z.enum(["operatingLicence", "recyclerCertificate", "taxCertificate", "insurance", "environmentalPermit", "other"]), number: z.string().trim().min(1).max(150), issuedAt: z.coerce.date(), expiresAt: z.coerce.date(), documentUrl: z.string().url()}).parse(request.body);
  if (input.expiresAt <= input.issuedAt) throw new ApiError(400, "Document expiry must be after its issue date.", "invalid_argument");
  const partner = await partnerRecord(id(request.params.id)); const ref = partner.ref.collection("documents").doc();
  await ref.set({...input, issuedAt: Timestamp.fromDate(input.issuedAt), expiresAt: Timestamp.fromDate(input.expiresAt), verificationStatus: "pending", createdBy: request.user!.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.status(201).json({data: {id: ref.id}});
});

router.get("/partners/:id/documents", authenticate, requireRoles(...operators), async (request, response) => {
  const partner = await partnerRecord(id(request.params.id)); const snapshot = await partner.ref.collection("documents").limit(300).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.patch("/partners/:id/documents/:documentId/verify", authenticate, requireRoles(...managers), async (request, response) => {
  const input = z.object({decision: z.enum(["verified", "rejected"]), notes: z.string().trim().max(1000).default("")}).parse(request.body);
  const partner = await partnerRecord(id(request.params.id)); const ref = partner.ref.collection("documents").doc(id(request.params.documentId)); const document = await ref.get();
  if (!document.exists) throw new ApiError(404, "Partner document not found.", "not_found");
  const batch = db.batch(); batch.update(ref, {verificationStatus: input.decision, verificationNotes: input.notes, verifiedBy: request.user!.uid, verifiedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  if (document.get("type") === "operatingLicence") batch.update(partner.ref, {licenceVerified: input.decision === "verified", licenceStatus: input.decision, status: input.decision === "verified" ? "active" : "pendingVerification", updatedAt: FieldValue.serverTimestamp()});
  await batch.commit(); response.json({data: {id: ref.id, verificationStatus: input.decision}});
});

router.post("/partners/:id/contracts", authenticate, requireRoles(...managers), async (request, response) => {
  const input = z.object({contractNumber: z.string().trim().max(100).optional(), title: z.string().trim().min(2).max(300), serviceCategories: z.array(z.enum(serviceCategories)).min(1), startsAt: z.coerce.date(), endsAt: z.coerce.date(), value: z.number().nonnegative(), currency: z.string().trim().length(3).default("SLE"), documentUrl: z.string().url(), paymentTerms: z.string().trim().min(2).max(1000), slaTargetHours: z.number().nonnegative().default(0), minimumQualityRating: z.number().min(0).max(5).default(0)}).parse(request.body);
  if (input.endsAt <= input.startsAt) throw new ApiError(400, "Contract end must be after its start.", "invalid_argument");
  const partner = await partnerRecord(id(request.params.id)); if (partner.snapshot.get("status") !== "active") throw new ApiError(409, "Only active partners can receive contracts.", "invalid_state");
  const ref = partner.ref.collection("contracts").doc(); const batch = db.batch();
  batch.set(ref, {...input, contractNumber: input.contractNumber || `CON-${ref.id.substring(0, 8).toUpperCase()}`, startAt: Timestamp.fromDate(input.startsAt), endAt: Timestamp.fromDate(input.endsAt), startsAt: Timestamp.fromDate(input.startsAt), endsAt: Timestamp.fromDate(input.endsAt), contractValue: input.value, terms: input.paymentTerms, status: "active", createdBy: request.user!.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  batch.update(partner.ref, {activeContractCount: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp()}); await batch.commit();
  response.status(201).json({data: {id: ref.id}});
});

router.get("/partners/:id/contracts", authenticate, requireRoles(...operators), async (request, response) => {
  const partner = await partnerRecord(id(request.params.id)); const snapshot = await partner.ref.collection("contracts").limit(300).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.get("/partners/:id/service-records", authenticate, requireRoles(...operators), async (request, response) => {
  const partner = await partnerRecord(id(request.params.id)); const snapshot = await partner.ref.collection("serviceRecords").orderBy("completedAt", "desc").limit(300).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.post("/partners/:id/service-records", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({reference: z.string().trim().min(1).max(200), serviceCategory: z.string().trim().min(1).max(100), targetHours: z.number().nonnegative(), actualHours: z.number().nonnegative(), qualityRating: z.number().min(1).max(5), serviceCost: z.number().nonnegative(), notes: z.string().trim().max(2000).default("")}).parse(request.body);
  const partner = await partnerRecord(id(request.params.id));
  if (partner.snapshot.get("status") !== "active") throw new ApiError(409, "Only active partners can complete services.", "invalid_state");
  const count = number(partner.snapshot.get("completedServiceCount")); const previousRating = number(partner.snapshot.get("performanceRating")); const metSla = input.targetHours <= 0 || input.actualHours <= input.targetHours;
  const ref = partner.ref.collection("serviceRecords").doc(); const batch = db.batch();
  batch.set(ref, {...input, metSla, recordedBy: request.user!.uid, completedAt: FieldValue.serverTimestamp()});
  batch.update(partner.ref, {completedServiceCount: count + 1, performanceRating: (previousRating * count + input.qualityRating) / (count + 1), ...(metSla ? {onTimeServiceCount: FieldValue.increment(1)} : {}), totalSpend: FieldValue.increment(input.serviceCost), updatedAt: FieldValue.serverTimestamp()});
  await batch.commit(); response.status(201).json({data: {id: ref.id, metSla}});
});

router.get("/partners/:id/compliance-records", authenticate, requireRoles(...operators), async (request, response) => {
  const partner = await partnerRecord(id(request.params.id)); const snapshot = await partner.ref.collection("complianceRecords").orderBy("createdAt", "desc").limit(300).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.patch("/partners/:id/licence", authenticate, requireRoles(...managers), async (request, response) => {
  const input = z.object({approved: z.boolean(), notes: z.string().trim().max(1000).default("")}).parse(request.body);
  const partner = await partnerRecord(id(request.params.id));
  if (input.approved) {
    const verified = await partner.ref.collection("documents").where("verificationStatus", "==", "verified").limit(1).get();
    if (verified.empty) throw new ApiError(409, "Verify at least one partner document before approving the licence.", "invalid_state");
  }
  await partner.ref.update({licenceVerified: input.approved, licenceStatus: input.approved ? "verified" : "rejected", status: input.approved ? "active" : "pendingVerification", licenceVerificationNotes: input.notes, licenceVerifiedBy: request.user!.uid, licenceVerifiedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  void publishNotificationEvent({event: "partner_licence_reviewed", body: `Partner licence ${input.approved ? "approved" : "rejected"}.`, data: {partnerId: partner.ref.id, approved: input.approved}});
  response.json({data: {id: partner.ref.id, licenceStatus: input.approved ? "verified" : "rejected"}});
});

router.patch("/partners/:id/commercial", authenticate, requireRoles(...managers), async (request, response) => {
  const input = z.object({pricing: z.record(z.string(), z.number().nonnegative()).default({}), pricingInformation: z.string().trim().max(2000).default(""), currency: z.string().trim().length(3).default("SLE"), facilityCapacityKg: z.number().nonnegative().optional(), paymentMethod: z.string().trim().max(100).default(""), payeeName: z.string().trim().max(200).default(""), paymentTerms: z.string().trim().max(1000).default(""), paymentInformation: z.object({accountName: z.string().trim().min(2).max(200), bankName: z.string().trim().min(2).max(200), accountReference: z.string().trim().min(2).max(200), mobileMoneyProvider: z.string().trim().max(100).default(""), mobileMoneyNumber: z.string().trim().max(50).default("")})}).parse(request.body);
  const partner = await partnerRecord(id(request.params.id)); await partner.ref.update({...input, updatedBy: request.user!.uid, updatedAt: FieldValue.serverTimestamp()});
  response.json({data: {id: partner.ref.id}});
});

router.post("/partners/:id/ratings", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({score: z.number().min(1).max(5), category: z.enum(["quality", "timeliness", "compliance", "communication", "overall"]), comments: z.string().trim().max(1000).default(""), referenceId: z.string().trim().max(200).default("")}).parse(request.body);
  const partner = await partnerRecord(id(request.params.id)); const oldCount = number(partner.snapshot.get("ratingCount")); const oldRating = number(partner.snapshot.get("performanceRating")); const newRating = (oldRating * oldCount + input.score) / (oldCount + 1); const ref = partner.ref.collection("ratings").doc(); const batch = db.batch();
  batch.set(ref, {...input, ratedBy: request.user!.uid, createdAt: FieldValue.serverTimestamp()}); batch.update(partner.ref, {performanceRating: newRating, ratingCount: oldCount + 1, updatedAt: FieldValue.serverTimestamp()}); await batch.commit();
  response.status(201).json({data: {id: ref.id, performanceRating: newRating}});
});

router.post("/partners/:id/compliance-records", authenticate, requireRoles(...managers), async (request, response) => {
  const input = z.object({checklistName: z.string().trim().min(2).max(300), passedItems: z.number().int().nonnegative(), totalItems: z.number().int().positive(), violations: z.array(z.string().trim().min(2).max(500)).default([]), correctiveActionDueAt: z.coerce.date().nullable().default(null), notes: z.string().trim().max(2000).default("")}).refine((value) => value.passedItems <= value.totalItems, "Passed items cannot exceed total items.").parse(request.body);
  const partner = await partnerRecord(id(request.params.id)); const score = input.passedItems / input.totalItems * 100; const ref = partner.ref.collection("complianceRecords").doc(); const batch = db.batch();
  batch.set(ref, {...input, correctiveActionDueAt: input.correctiveActionDueAt ? Timestamp.fromDate(input.correctiveActionDueAt) : null, score, recordedBy: request.user!.uid, createdAt: FieldValue.serverTimestamp()}); batch.update(partner.ref, {complianceScore: score, updatedAt: FieldValue.serverTimestamp()}); await batch.commit();
  response.status(201).json({data: {id: ref.id, complianceScore: score}});
});

router.post("/partners/:id/slas", authenticate, requireRoles(...managers), async (request, response) => {
  const input = z.object({name: z.string().trim().min(2).max(300), responseTimeHours: z.number().positive(), completionTimeHours: z.number().positive(), minimumCompletionRatePercent: z.number().min(0).max(100), minimumQualityScore: z.number().min(0).max(100), startsAt: z.coerce.date(), endsAt: z.coerce.date()}).parse(request.body);
  if (input.endsAt <= input.startsAt) throw new ApiError(400, "SLA end must be after its start.", "invalid_argument");
  const partner = await partnerRecord(id(request.params.id)); const ref = await partner.ref.collection("slas").add({...input, startsAt: Timestamp.fromDate(input.startsAt), endsAt: Timestamp.fromDate(input.endsAt), status: "active", createdBy: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  response.status(201).json({data: {id: ref.id}});
});

router.patch("/partners/:id/status", authenticate, requireRoles(...managers), async (request, response) => {
  const input = z.object({status: z.enum(["active", "suspended", "terminated"]), reason: z.string().trim().min(2).max(1000)}).parse(request.body);
  const partner = await partnerRecord(id(request.params.id)); await partner.ref.update({status: input.status, statusReason: input.reason, suspensionReason: input.status === "suspended" ? input.reason : "", statusChangedBy: request.user!.uid, statusChangedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  void publishNotificationEvent({event: "partner_status_changed", body: `Partner status changed to ${input.status}.`, data: {partnerId: partner.ref.id, status: input.status}});
  response.json({data: {id: partner.ref.id, status: input.status}});
});

router.get("/partners/alerts/document-expiry", authenticate, requireRoles(...managers), async (request, response) => {
  const days = z.coerce.number().int().min(1).max(365).default(30).parse(request.query.days); const threshold = Timestamp.fromMillis(Date.now() + days * 86400000);
  const partners = await db.collection("partners").limit(500).get(); const alerts: unknown[] = [];
  for (const partner of partners.docs) { const documents = await partner.ref.collection("documents").where("expiresAt", "<=", threshold).limit(100).get(); for (const doc of documents.docs) alerts.push({partnerId: partner.id, partnerName: partner.get("name"), document: documentJson(doc.id, doc.data())}); }
  response.json({data: alerts});
});

router.get("/partners/reports/summary", authenticate, requireRoles(...managers), async (_request, response) => {
  const snapshot = await db.collection("partners").limit(1000).get(); const byStatus: Record<string, number> = {}; const byService: Record<string, number> = {}; let totalCapacityKg = 0; let ratings = 0; let compliance = 0;
  for (const doc of snapshot.docs) { const data = doc.data(); const status = String(data.status ?? "unknown"); byStatus[status] = (byStatus[status] ?? 0) + 1; for (const service of data.serviceCategories ?? []) byService[String(service)] = (byService[String(service)] ?? 0) + 1; totalCapacityKg += number(data.facilityCapacityKg); ratings += number(data.performanceRating); compliance += number(data.complianceScore); }
  response.json({data: {totalPartners: snapshot.size, activePartners: byStatus.active ?? 0, totalCapacityKg, averageRating: snapshot.size ? ratings / snapshot.size : 0, averageComplianceScore: snapshot.size ? compliance / snapshot.size : 0, byStatus, byService}});
});

export default router;
