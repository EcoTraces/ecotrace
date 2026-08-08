import {Router} from "express";
import {FieldValue} from "firebase-admin/firestore";
import {z} from "zod";
import {authenticate, requireRoles} from "./auth.js";
import {db} from "./firebase.js";
import {documentJson} from "./firestore-json.js";
import {ApiError} from "./errors.js";
import {publishNotificationEvent} from "./push-events.js";

const router = Router();
const administrators = ["administrator", "superAdministrator"] as const;
const organizationTypes = ["business", "institution", "recycler", "collectionCompany", "repairProvider"] as const;
const organizationStatuses = ["draft", "pendingVerification", "approved", "rejected", "suspended"] as const;
const memberRoles = ["owner", "manager", "staff", "viewer"] as const;
function id(value: string | string[]) { return Array.isArray(value) ? value[0] : value; }
function elevated(role: string) { return ["administrator", "superAdministrator"].includes(role); }

const organizationSchema = z.object({
  name: z.string().trim().min(2).max(300),
  type: z.enum(organizationTypes),
  registrationNumber: z.string().trim().min(2).max(150),
  contactName: z.string().trim().min(2).max(200),
  contactEmail: z.string().trim().email(),
  contactPhone: z.string().trim().min(5).max(50),
  address: z.string().trim().min(2).max(500),
  website: z.string().url().or(z.literal("")).default(""),
  serviceAreas: z.array(z.string().trim().min(2).max(200)).min(1).max(100),
});

async function accessibleOrganization(organizationId: string, uid: string, role: string, ownerRequired = false) {
  const ref = db.collection("organizations").doc(organizationId);
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new ApiError(404, "Organization not found.", "not_found");
  const owner = snapshot.get("ownerId") === uid;
  const member = (snapshot.get("memberIds") as string[] | undefined)?.includes(uid) ?? false;
  if (!elevated(role) && (ownerRequired ? !owner : !member)) throw new ApiError(403, "You cannot access this organization.", "forbidden");
  return {ref, snapshot, owner};
}

router.get("/organizations", authenticate, async (request, response) => {
  let query: FirebaseFirestore.Query = elevated(request.user!.role) ? db.collection("organizations") : db.collection("organizations").where("memberIds", "array-contains", request.user!.uid);
  if (typeof request.query.status === "string") query = query.where("status", "==", request.query.status);
  if (typeof request.query.type === "string") query = query.where("type", "==", request.query.type);
  const snapshot = await query.limit(Math.min(Number(request.query.limit ?? 300), 1000)).get();
  const search = typeof request.query.search === "string" ? request.query.search.toLowerCase() : "";
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data())).filter((item) => !search || `${item.name} ${item.registrationNumber} ${item.contactEmail}`.toLowerCase().includes(search))});
});

router.post("/organizations", authenticate, async (request, response) => {
  const input = organizationSchema.parse(request.body);
  const duplicate = await db.collection("organizations").where("registrationNumber", "==", input.registrationNumber).limit(1).get();
  if (!duplicate.empty) throw new ApiError(409, "An organization with this registration number already exists.", "duplicate_registration");
  const ref = db.collection("organizations").doc();
  const batch = db.batch();
  batch.set(ref, {...input, contactEmail: input.contactEmail.toLowerCase(), status: "pendingVerification", ownerId: request.user!.uid, memberIds: [request.user!.uid], verificationScore: 0, rejectionReason: null, createdAt: FieldValue.serverTimestamp(), submittedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  batch.set(ref.collection("members").doc(request.user!.uid), {userId: request.user!.uid, organizationRole: "owner", status: "active", joinedAt: FieldValue.serverTimestamp()});
  await batch.commit();
  void publishNotificationEvent({event: "organization_submitted", data: {organizationId: ref.id, ownerId: request.user!.uid, organizationName: input.name}});
  response.status(201).json({data: {id: ref.id, status: "pendingVerification"}});
});

router.get("/organizations/:id", authenticate, async (request, response) => {
  const organization = await accessibleOrganization(id(request.params.id), request.user!.uid, request.user!.role);
  response.json({data: documentJson(organization.snapshot.id, organization.snapshot.data()!)});
});

router.patch("/organizations/:id", authenticate, async (request, response) => {
  const input = organizationSchema.partial().omit({type: true, registrationNumber: true}).parse(request.body);
  const organization = await accessibleOrganization(id(request.params.id), request.user!.uid, request.user!.role, true);
  if (["suspended"].includes(String(organization.snapshot.get("status"))) && !elevated(request.user!.role)) throw new ApiError(409, "A suspended organization cannot be edited.", "invalid_state");
  await organization.ref.update({...input, ...(input.contactEmail ? {contactEmail: input.contactEmail.toLowerCase()} : {}), updatedAt: FieldValue.serverTimestamp(), updatedBy: request.user!.uid});
  response.json({data: {id: organization.ref.id}});
});

router.patch("/organizations/:id/submit", authenticate, async (request, response) => {
  const organization = await accessibleOrganization(id(request.params.id), request.user!.uid, request.user!.role, true);
  if (!["draft", "rejected"].includes(String(organization.snapshot.get("status")))) throw new ApiError(409, "Only draft or rejected organizations can be submitted.", "invalid_state");
  await organization.ref.update({status: "pendingVerification", rejectionReason: null, submittedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.json({data: {id: organization.ref.id, status: "pendingVerification"}});
});

router.patch("/organizations/:id/review", authenticate, requireRoles(...administrators), async (request, response) => {
  const input = z.object({decision: z.enum(["approve", "reject"]), reason: z.string().trim().max(2000).default(""), verificationScore: z.number().min(0).max(100).default(100)}).refine((value) => value.decision === "approve" || value.reason.length >= 2, {message: "A rejection reason is required."}).parse(request.body);
  const organization = await accessibleOrganization(id(request.params.id), request.user!.uid, request.user!.role);
  if (organization.snapshot.get("status") !== "pendingVerification") throw new ApiError(409, "The organization is not awaiting verification.", "invalid_state");
  const status = input.decision === "approve" ? "approved" : "rejected";
  await organization.ref.update({status, verificationScore: input.verificationScore, rejectionReason: input.decision === "reject" ? input.reason : null, reviewedBy: request.user!.uid, reviewedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  void publishNotificationEvent({event: "organization_reviewed", data: {organizationId: organization.ref.id, ownerId: organization.snapshot.get("ownerId"), status, reason: input.reason}});
  response.json({data: {id: organization.ref.id, status}});
});

router.patch("/organizations/:id/status", authenticate, requireRoles(...administrators), async (request, response) => {
  const input = z.object({status: z.enum(organizationStatuses), reason: z.string().trim().max(2000).default("")}).parse(request.body);
  const organization = await accessibleOrganization(id(request.params.id), request.user!.uid, request.user!.role);
  await organization.ref.update({status: input.status, statusReason: input.reason, statusChangedBy: request.user!.uid, statusChangedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.json({data: {id: organization.ref.id, status: input.status}});
});

router.put("/organizations/:id/service-areas", authenticate, async (request, response) => {
  const input = z.object({serviceAreas: z.array(z.string().trim().min(2).max(200)).min(1).max(100)}).parse(request.body);
  const organization = await accessibleOrganization(id(request.params.id), request.user!.uid, request.user!.role, true);
  await organization.ref.update({...input, updatedAt: FieldValue.serverTimestamp(), updatedBy: request.user!.uid});
  response.json({data: {id: organization.ref.id, serviceAreas: input.serviceAreas}});
});

router.get("/organizations/:id/branches", authenticate, async (request, response) => {
  const organization = await accessibleOrganization(id(request.params.id), request.user!.uid, request.user!.role);
  const snapshot = await organization.ref.collection("branches").orderBy("createdAt").get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.post("/organizations/:id/branches", authenticate, async (request, response) => {
  const input = z.object({name: z.string().trim().min(2).max(200), address: z.string().trim().min(2).max(500), contactName: z.string().trim().max(200).default(""), contactPhone: z.string().trim().max(50).default(""), serviceAreas: z.array(z.string().trim().min(2).max(200)).default([])}).parse(request.body);
  const organization = await accessibleOrganization(id(request.params.id), request.user!.uid, request.user!.role, true);
  const ref = await organization.ref.collection("branches").add({...input, active: true, createdAt: FieldValue.serverTimestamp(), createdBy: request.user!.uid});
  response.status(201).json({data: {id: ref.id}});
});

router.patch("/organizations/:id/branches/:branchId", authenticate, async (request, response) => {
  const input = z.object({name: z.string().trim().min(2).max(200).optional(), address: z.string().trim().min(2).max(500).optional(), contactName: z.string().trim().max(200).optional(), contactPhone: z.string().trim().max(50).optional(), active: z.boolean().optional(), serviceAreas: z.array(z.string().trim().min(2).max(200)).optional()}).parse(request.body);
  const organization = await accessibleOrganization(id(request.params.id), request.user!.uid, request.user!.role, true);
  const ref = organization.ref.collection("branches").doc(id(request.params.branchId));
  await ref.set({...input, updatedAt: FieldValue.serverTimestamp(), updatedBy: request.user!.uid}, {merge: true});
  response.json({data: {id: ref.id}});
});

router.delete("/organizations/:id/branches/:branchId", authenticate, async (request, response) => {
  const organization = await accessibleOrganization(id(request.params.id), request.user!.uid, request.user!.role, true);
  const ref = organization.ref.collection("branches").doc(id(request.params.branchId));
  await ref.set({active: false, archivedAt: FieldValue.serverTimestamp(), archivedBy: request.user!.uid}, {merge: true});
  response.json({data: {id: ref.id, active: false}});
});

router.get("/organizations/:id/members", authenticate, async (request, response) => {
  const organization = await accessibleOrganization(id(request.params.id), request.user!.uid, request.user!.role);
  const snapshot = await organization.ref.collection("members").get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.post("/organizations/:id/invitations", authenticate, async (request, response) => {
  const input = z.object({email: z.string().trim().email(), organizationRole: z.enum(memberRoles).exclude(["owner"]), branchId: z.string().trim().max(200).default("")}).parse(request.body);
  const organization = await accessibleOrganization(id(request.params.id), request.user!.uid, request.user!.role, true);
  const existing = await db.collection("organizationInvitations").where("organizationId", "==", organization.ref.id).where("email", "==", input.email.toLowerCase()).where("status", "==", "pending").limit(1).get();
  if (!existing.empty) throw new ApiError(409, "This email already has a pending invitation.", "duplicate_invitation");
  const ref = await db.collection("organizationInvitations").add({...input, email: input.email.toLowerCase(), organizationId: organization.ref.id, organizationName: organization.snapshot.get("name"), status: "pending", invitedBy: request.user!.uid, createdAt: FieldValue.serverTimestamp(), expiresAt: new Date(Date.now() + 7 * 86400000)});
  response.status(201).json({data: {id: ref.id}});
});

router.get("/organization-invitations", authenticate, async (request, response) => {
  const email = request.user!.email?.toLowerCase();
  if (!email) return response.json({data: []});
  const snapshot = await db.collection("organizationInvitations").where("email", "==", email).where("status", "==", "pending").limit(100).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.patch("/organization-invitations/:id/respond", authenticate, async (request, response) => {
  const input = z.object({decision: z.enum(["accept", "decline"])}).parse(request.body);
  const invitationRef = db.collection("organizationInvitations").doc(id(request.params.id));
  await db.runTransaction(async (transaction) => {
    const invitation = await transaction.get(invitationRef);
    if (!invitation.exists || invitation.get("status") !== "pending") throw new ApiError(409, "The invitation is no longer pending.", "invalid_state");
    if (String(invitation.get("email")).toLowerCase() !== request.user!.email?.toLowerCase()) throw new ApiError(403, "This invitation belongs to another user.", "forbidden");
    const organizationRef = db.collection("organizations").doc(String(invitation.get("organizationId")));
    if (input.decision === "accept") {
      transaction.set(organizationRef.collection("members").doc(request.user!.uid), {userId: request.user!.uid, organizationRole: invitation.get("organizationRole"), branchId: invitation.get("branchId") ?? "", status: "active", joinedAt: FieldValue.serverTimestamp()});
      transaction.update(organizationRef, {memberIds: FieldValue.arrayUnion(request.user!.uid), updatedAt: FieldValue.serverTimestamp()});
    }
    transaction.update(invitationRef, {status: input.decision === "accept" ? "accepted" : "declined", respondedBy: request.user!.uid, respondedAt: FieldValue.serverTimestamp()});
  });
  response.json({data: {id: invitationRef.id, status: input.decision === "accept" ? "accepted" : "declined"}});
});

router.patch("/organizations/:id/members/:uid", authenticate, async (request, response) => {
  const input = z.object({organizationRole: z.enum(memberRoles).exclude(["owner"]).optional(), status: z.enum(["active", "suspended"]).optional(), branchId: z.string().trim().max(200).optional()}).parse(request.body);
  const organization = await accessibleOrganization(id(request.params.id), request.user!.uid, request.user!.role, true);
  const uid = id(request.params.uid);
  if (uid === organization.snapshot.get("ownerId")) throw new ApiError(409, "The owner role cannot be changed here.", "owner_protected");
  await organization.ref.collection("members").doc(uid).set({...input, updatedAt: FieldValue.serverTimestamp(), updatedBy: request.user!.uid}, {merge: true});
  response.json({data: {uid}});
});

router.delete("/organizations/:id/members/:uid", authenticate, async (request, response) => {
  const organization = await accessibleOrganization(id(request.params.id), request.user!.uid, request.user!.role, true);
  const uid = id(request.params.uid);
  if (uid === organization.snapshot.get("ownerId")) throw new ApiError(409, "The organization owner cannot be removed.", "owner_protected");
  const batch = db.batch();
  batch.delete(organization.ref.collection("members").doc(uid));
  batch.update(organization.ref, {memberIds: FieldValue.arrayRemove(uid), updatedAt: FieldValue.serverTimestamp()});
  await batch.commit();
  response.json({data: {uid, removed: true}});
});

router.get("/organizations/:id/documents", authenticate, async (request, response) => {
  const organization = await accessibleOrganization(id(request.params.id), request.user!.uid, request.user!.role);
  const snapshot = await organization.ref.collection("documents").orderBy("uploadedAt", "desc").get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.post("/organizations/:id/documents", authenticate, async (request, response) => {
  const input = z.object({name: z.string().trim().min(1).max(500), documentType: z.enum(["registration", "licence", "tax", "certificate", "insurance", "other"]), fileUrl: z.string().url(), publicId: z.string().trim().min(1).max(500), mimeType: z.string().trim().min(1).max(200), expiresAt: z.coerce.date().nullable().default(null)}).parse(request.body);
  const organization = await accessibleOrganization(id(request.params.id), request.user!.uid, request.user!.role, true);
  const ref = await organization.ref.collection("documents").add({...input, verificationStatus: "pending", uploadedBy: request.user!.uid, uploadedAt: FieldValue.serverTimestamp(), expiresAt: input.expiresAt});
  response.status(201).json({data: {id: ref.id}});
});

router.patch("/organizations/:id/documents/:documentId/verify", authenticate, requireRoles(...administrators), async (request, response) => {
  const input = z.object({decision: z.enum(["verify", "reject"]), notes: z.string().trim().max(2000).default("")}).parse(request.body);
  const organization = await accessibleOrganization(id(request.params.id), request.user!.uid, request.user!.role);
  const ref = organization.ref.collection("documents").doc(id(request.params.documentId));
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new ApiError(404, "Organization document not found.", "not_found");
  const verificationStatus = input.decision === "verify" ? "verified" : "rejected";
  await ref.update({verificationStatus, verificationNotes: input.notes, verifiedBy: request.user!.uid, verifiedAt: FieldValue.serverTimestamp()});
  response.json({data: {id: ref.id, verificationStatus}});
});

router.get("/organizations/:id/status", authenticate, async (request, response) => {
  const organization = await accessibleOrganization(id(request.params.id), request.user!.uid, request.user!.role);
  const [members, branches, documents] = await Promise.all([organization.ref.collection("members").count().get(), organization.ref.collection("branches").where("active", "==", true).count().get(), organization.ref.collection("documents").get()]);
  const verifiedDocuments = documents.docs.filter((doc) => doc.get("verificationStatus") === "verified").length;
  response.json({data: {id: organization.ref.id, status: organization.snapshot.get("status"), verificationScore: organization.snapshot.get("verificationScore") ?? 0, rejectionReason: organization.snapshot.get("rejectionReason") ?? null, members: members.data().count, activeBranches: branches.data().count, documents: documents.size, verifiedDocuments, documentCompletionRate: documents.size ? verifiedDocuments / documents.size * 100 : 0, reviewedAt: organization.snapshot.get("reviewedAt") ?? null}});
});

export default router;
