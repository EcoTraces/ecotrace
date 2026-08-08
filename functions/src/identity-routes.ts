import {Router} from "express";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {z} from "zod";
import {authenticate, requireRoles} from "./auth.js";
import {auth, db} from "./firebase.js";
import {documentJson} from "./firestore-json.js";
import {ApiError} from "./errors.js";
import {appendAuditRecord} from "./audit-routes.js";

const router = Router();
const administrators = ["administrator", "superAdministrator"] as const;
const selfServiceRoles = ["household", "business", "institution"] as const;

function parameter(value: string | string[]) { return Array.isArray(value) ? value[0] : value; }

router.post("/identity/bootstrap", authenticate, async (request, response) => {
  const input = z.object({
    displayName: z.string().trim().min(2).max(200),
    role: z.enum(selfServiceRoles),
    termsVersion: z.string().trim().min(1).max(50),
    privacyVersion: z.string().trim().min(1).max(50),
    acceptedTerms: z.literal(true),
    acceptedPrivacy: z.literal(true),
  }).parse(request.body);
  const ref = db.collection("users").doc(request.user!.uid);
  const existing = await ref.get();
  if (existing.exists && existing.get("role") && existing.get("role") !== input.role) throw new ApiError(409, "The account already has a different role.", "role_conflict");
  const record = await auth.getUser(request.user!.uid);
  await Promise.all([
    auth.updateUser(record.uid, {displayName: input.displayName}),
    ref.set({email: record.email ?? request.user!.email ?? "", displayName: input.displayName, role: input.role, accountStatus: "active", emailVerified: record.emailVerified, phoneVerified: Boolean(record.phoneNumber), termsAcceptedAt: FieldValue.serverTimestamp(), termsVersion: input.termsVersion, privacyAcceptedAt: FieldValue.serverTimestamp(), privacyVersion: input.privacyVersion, createdAt: existing.exists ? existing.get("createdAt") ?? FieldValue.serverTimestamp() : FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}, {merge: true}),
  ]);
  response.status(existing.exists ? 200 : 201).json({data: {uid: record.uid, role: input.role}});
});

router.get("/identity/profile", authenticate, async (request, response) => {
  const [record, profile] = await Promise.all([auth.getUser(request.user!.uid), db.collection("users").doc(request.user!.uid).get()]);
  response.json({data: {uid: record.uid, email: record.email, displayName: record.displayName, phoneNumber: record.phoneNumber, photoUrl: record.photoURL, emailVerified: record.emailVerified, phoneVerified: Boolean(record.phoneNumber), disabled: record.disabled, role: request.user!.role, accountStatus: profile.get("accountStatus") ?? (record.disabled ? "suspended" : "active"), profile: profile.exists ? documentJson(profile.id, profile.data()!) : null}});
});

router.patch("/identity/profile", authenticate, async (request, response) => {
  const input = z.object({displayName: z.string().trim().min(2).max(200).optional(), phone: z.string().trim().max(50).optional(), photoUrl: z.string().url().or(z.literal("")).optional(), address: z.string().trim().max(500).optional(), preferredLanguage: z.string().trim().min(2).max(20).optional(), notificationEmail: z.string().email().optional()}).parse(request.body);
  const authChanges = {displayName: input.displayName, photoURL: input.photoUrl || undefined};
  await Promise.all([auth.updateUser(request.user!.uid, authChanges), db.collection("users").doc(request.user!.uid).set({...input, updatedAt: FieldValue.serverTimestamp()}, {merge: true})]);
  response.json({data: {uid: request.user!.uid}});
});

router.post("/identity/verification/sync", authenticate, async (request, response) => {
  const record = await auth.getUser(request.user!.uid);
  const values = {emailVerified: record.emailVerified, phoneVerified: Boolean(record.phoneNumber), phoneNumber: record.phoneNumber ?? "", verificationSyncedAt: FieldValue.serverTimestamp()};
  await db.collection("users").doc(record.uid).set(values, {merge: true});
  response.json({data: {...values, verificationSyncedAt: new Date().toISOString()}});
});

router.get("/identity/providers", authenticate, async (request, response) => {
  const record = await auth.getUser(request.user!.uid);
  response.json({data: record.providerData.map((provider) => ({providerId: provider.providerId, uid: provider.uid, email: provider.email, displayName: provider.displayName, phoneNumber: provider.phoneNumber}))});
});

router.get("/identity/mfa", authenticate, async (request, response) => {
  const record = await auth.getUser(request.user!.uid);
  response.json({data: {enabled: Boolean(record.multiFactor?.enrolledFactors.length), factors: (record.multiFactor?.enrolledFactors ?? []).map((factor) => ({uid: factor.uid, factorId: factor.factorId, displayName: factor.displayName, enrollmentTime: factor.enrollmentTime}))}});
});

router.delete("/identity/mfa", authenticate, async (request, response) => {
  await auth.updateUser(request.user!.uid, {multiFactor: {enrolledFactors: null}});
  await auth.revokeRefreshTokens(request.user!.uid);
  response.json({data: {enabled: false, sessionsRevoked: true}});
});

const sessionSchema = z.object({deviceId: z.string().trim().min(8).max(200), deviceName: z.string().trim().min(1).max(200), platform: z.enum(["android", "ios", "web", "windows", "macos", "linux", "unknown"]), appVersion: z.string().trim().max(50).default(""), pushTokenId: z.string().trim().max(300).default("")});

router.post("/identity/sessions", authenticate, async (request, response) => {
  const input = sessionSchema.parse(request.body);
  const ref = db.collection("users").doc(request.user!.uid).collection("sessions").doc(input.deviceId);
  await ref.set({...input, ipAddress: request.ip, userAgent: request.header("user-agent") ?? "", active: true, lastSeenAt: FieldValue.serverTimestamp(), createdAt: FieldValue.serverTimestamp()}, {merge: true});
  await appendAuditRecord({action: "login", resourceType: "authenticationSession", resourceId: ref.id, actorId: request.user!.uid, actorRole: request.user!.role, ipAddress: request.ip, deviceInformation: request.header("user-agent") ?? "", metadata: {platform: input.platform, deviceName: input.deviceName}});
  response.status(201).json({data: {id: ref.id}});
});

router.get("/identity/sessions", authenticate, async (request, response) => {
  const snapshot = await db.collection("users").doc(request.user!.uid).collection("sessions").orderBy("lastSeenAt", "desc").limit(100).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.delete("/identity/sessions/:id", authenticate, async (request, response) => {
  const id = parameter(request.params.id);
  await db.collection("users").doc(request.user!.uid).collection("sessions").doc(id).set({active: false, revokedAt: FieldValue.serverTimestamp()}, {merge: true});
  await auth.revokeRefreshTokens(request.user!.uid);
  response.json({data: {id, revoked: true}});
});

router.post("/identity/sessions/revoke-all", authenticate, async (request, response) => {
  const sessions = await db.collection("users").doc(request.user!.uid).collection("sessions").where("active", "==", true).get();
  const batch = db.batch();
  sessions.docs.forEach((doc) => batch.set(doc.ref, {active: false, revokedAt: FieldValue.serverTimestamp()}, {merge: true}));
  await Promise.all([batch.commit(), auth.revokeRefreshTokens(request.user!.uid)]);
  response.json({data: {revoked: sessions.size}});
});

router.get("/identity/login-history", authenticate, async (request, response) => {
  const limit = Math.min(Number(request.query.limit ?? 100), 500);
  const snapshot = await db.collection("auditLogs").where("actorId", "==", request.user!.uid).where("action", "==", "login").orderBy("occurredAt", "desc").limit(limit).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.put("/identity/consents", authenticate, async (request, response) => {
  const input = z.object({termsAccepted: z.literal(true), privacyAccepted: z.literal(true), termsVersion: z.string().trim().min(1).max(50), privacyVersion: z.string().trim().min(1).max(50), marketingAccepted: z.boolean().default(false)}).parse(request.body);
  await db.collection("users").doc(request.user!.uid).set({...input, termsAcceptedAt: FieldValue.serverTimestamp(), privacyAcceptedAt: FieldValue.serverTimestamp(), consentUpdatedAt: FieldValue.serverTimestamp()}, {merge: true});
  response.json({data: {accepted: true, termsVersion: input.termsVersion, privacyVersion: input.privacyVersion}});
});

router.get("/identity/permissions", authenticate, async (request, response) => {
  const role = await db.collection("systemRoles").doc(request.user!.role).get();
  response.json({data: {role: request.user!.role, permissions: role.get("permissions") ?? [], configured: role.exists}});
});

router.get("/identity/deletion-request", authenticate, async (request, response) => {
  const snapshot = await db.collection("accountDeletionRequests").doc(request.user!.uid).get();
  response.json({data: snapshot.exists ? documentJson(snapshot.id, snapshot.data()!) : null});
});

router.post("/identity/deletion-request", authenticate, async (request, response) => {
  const input = z.object({reason: z.string().trim().min(2).max(2000), confirmation: z.literal("DELETE MY ACCOUNT")}).parse(request.body);
  const executeAfter = Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000);
  await db.collection("accountDeletionRequests").doc(request.user!.uid).set({userId: request.user!.uid, email: request.user!.email ?? "", reason: input.reason, status: "pending", requestedAt: FieldValue.serverTimestamp(), executeAfter, updatedAt: FieldValue.serverTimestamp()});
  response.status(201).json({data: {status: "pending", executeAfter: executeAfter.toDate().toISOString()}});
});

router.delete("/identity/deletion-request", authenticate, async (request, response) => {
  const ref = db.collection("accountDeletionRequests").doc(request.user!.uid);
  const snapshot = await ref.get();
  if (!snapshot.exists || snapshot.get("status") !== "pending") throw new ApiError(409, "There is no pending deletion request.", "invalid_state");
  await ref.update({status: "cancelled", cancelledAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.json({data: {status: "cancelled"}});
});

router.get("/identity/deletion-requests", authenticate, requireRoles(...administrators), async (request, response) => {
  let query: FirebaseFirestore.Query = db.collection("accountDeletionRequests");
  if (typeof request.query.status === "string") query = query.where("status", "==", request.query.status);
  const snapshot = await query.limit(500).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.patch("/identity/deletion-requests/:uid", authenticate, requireRoles(...administrators), async (request, response) => {
  const uid = parameter(request.params.uid);
  const input = z.object({decision: z.enum(["approve", "reject"]), notes: z.string().trim().max(2000).default("")}).parse(request.body);
  const ref = db.collection("accountDeletionRequests").doc(uid);
  const snapshot = await ref.get();
  if (!snapshot.exists || snapshot.get("status") !== "pending") throw new ApiError(409, "The deletion request is not pending.", "invalid_state");
  if (input.decision === "approve") {
    await auth.revokeRefreshTokens(uid);
    await auth.deleteUser(uid);
    await db.collection("users").doc(uid).set({accountStatus: "deleted", deletedAt: FieldValue.serverTimestamp(), personalDataErasurePending: true}, {merge: true});
  }
  await ref.update({status: input.decision === "approve" ? "approved" : "rejected", notes: input.notes, reviewedBy: request.user!.uid, reviewedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.json({data: {uid, status: input.decision === "approve" ? "approved" : "rejected"}});
});

export default router;
