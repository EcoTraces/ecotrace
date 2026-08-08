import {Router} from "express";
import {FieldValue} from "firebase-admin/firestore";
import {z} from "zod";
import {authenticate, requireRoles} from "./auth.js";
import {auth, db} from "./firebase.js";
import {documentJson} from "./firestore-json.js";
import {ApiError} from "./errors.js";
import type {EcoTraceRole} from "./types.js";

const router = Router();
const administrators = ["administrator", "superAdministrator"] as const;
const superAdministrators = ["superAdministrator"] as const;
const roles: EcoTraceRole[] = ["household", "business", "institution", "collector", "driver", "collectionCentreOperator", "repairTechnician", "recycler", "environmentalOfficer", "administrator", "superAdministrator"];
const catalogNames = ["wasteCategories", "itemConditions", "pickupFees", "serviceAreas", "rewardRules", "notificationTemplates", "supportedLanguages"] as const;

const catalogSchema = z.object({name: z.string().trim().min(1).max(200), code: z.string().trim().min(1).max(100), active: z.boolean().default(true), description: z.string().trim().max(1000).default(""), value: z.unknown().optional(), metadata: z.record(z.string(), z.unknown()).default({})});

router.get("/administration/dashboard", authenticate, requireRoles(...administrators), async (_request, response) => {
  const collections = ["users", "pickupRequests", "vehicles", "collectionCentres", "partners", "incidents", "auditLogs"];
  const counts = await Promise.all(collections.map(async (name) => ({name, count: (await db.collection(name).count().get()).data().count})));
  response.json({data: {counts: Object.fromEntries(counts.map(({name, count}) => [name, count])), generatedAt: new Date().toISOString()}});
});

router.get("/administration/users", authenticate, requireRoles(...administrators), async (request, response) => {
  const result = await auth.listUsers(Math.min(Number(request.query.limit ?? 500), 1000), typeof request.query.pageToken === "string" ? request.query.pageToken : undefined);
  const profiles = await Promise.all(result.users.map((user) => db.collection("users").doc(user.uid).get()));
  response.json({data: result.users.map((user, index) => ({uid: user.uid, email: user.email, displayName: user.displayName, disabled: user.disabled, emailVerified: user.emailVerified, customClaims: user.customClaims ?? {}, profile: profiles[index].exists ? documentJson(profiles[index].id, profiles[index].data()!) : null})), nextPageToken: result.pageToken ?? null});
});

router.patch("/administration/users/:uid", authenticate, requireRoles(...administrators), async (request, response) => {
  const input = z.object({displayName: z.string().trim().min(1).max(200).optional(), disabled: z.boolean().optional(), accountStatus: z.enum(["active", "suspended", "disabled"]).optional()}).parse(request.body);
  const uid = String(request.params.uid);
  await auth.updateUser(uid, {displayName: input.displayName, disabled: input.disabled ?? input.accountStatus === "disabled"});
  await db.collection("users").doc(uid).set({...input, updatedAt: FieldValue.serverTimestamp(), updatedBy: request.user!.uid}, {merge: true});
  response.json({data: {uid}});
});

router.put("/administration/users/:uid/role", authenticate, requireRoles(...superAdministrators), async (request, response) => {
  const input = z.object({role: z.enum(roles as [EcoTraceRole, ...EcoTraceRole[]])}).parse(request.body);
  const uid = String(request.params.uid);
  const user = await auth.getUser(uid);
  await auth.setCustomUserClaims(uid, {...user.customClaims, role: input.role});
  await db.collection("users").doc(uid).set({role: input.role, claimSyncPending: false, updatedAt: FieldValue.serverTimestamp(), updatedBy: request.user!.uid}, {merge: true});
  response.json({data: {uid, role: input.role}});
});

router.get("/administration/roles", authenticate, requireRoles(...administrators), async (_request, response) => {
  const snapshot = await db.collection("systemRoles").get();
  const configured = new Map(snapshot.docs.map((doc) => [doc.id, documentJson(doc.id, doc.data())]));
  response.json({data: roles.map((role) => configured.get(role) ?? {id: role, name: role, permissions: [], system: true})});
});

router.put("/administration/roles/:role", authenticate, requireRoles(...superAdministrators), async (request, response) => {
  const role = String(request.params.role);
  if (!roles.includes(role as EcoTraceRole)) throw new ApiError(400, "Unknown system role.", "validation_error");
  const input = z.object({name: z.string().trim().min(1).max(200), permissions: z.array(z.string().trim().min(1).max(150)).max(300), description: z.string().trim().max(1000).default("")}).parse(request.body);
  await db.collection("systemRoles").doc(role).set({...input, system: true, updatedAt: FieldValue.serverTimestamp(), updatedBy: request.user!.uid}, {merge: true});
  response.json({data: {id: role}});
});

router.get("/administration/permissions", authenticate, requireRoles(...administrators), async (_request, response) => {
  const snapshot = await db.collection("systemPermissions").get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.put("/administration/permissions/:code", authenticate, requireRoles(...superAdministrators), async (request, response) => {
  const code = String(request.params.code);
  const input = z.object({description: z.string().trim().min(1).max(1000), module: z.string().trim().min(1).max(100), active: z.boolean().default(true)}).parse(request.body);
  await db.collection("systemPermissions").doc(code).set({...input, code, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  response.json({data: {code}});
});

for (const catalog of catalogNames) {
  router.get(`/administration/catalogs/${catalog}`, authenticate, requireRoles(...administrators), async (_request, response) => { const snapshot = await db.collection("systemConfiguration").doc(catalog).collection("items").get(); response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))}); });
  router.post(`/administration/catalogs/${catalog}`, authenticate, requireRoles(...administrators), async (request, response) => { const input = catalogSchema.parse(request.body); const ref = db.collection("systemConfiguration").doc(catalog).collection("items").doc(); await ref.set({...input, createdAt: FieldValue.serverTimestamp(), createdBy: request.user!.uid}); response.status(201).json({data: {id: ref.id}}); });
  router.put(`/administration/catalogs/${catalog}/:id`, authenticate, requireRoles(...administrators), async (request, response) => { const input = catalogSchema.partial().parse(request.body); const ref = db.collection("systemConfiguration").doc(catalog).collection("items").doc(String(request.params.id)); await ref.set({...input, updatedAt: FieldValue.serverTimestamp(), updatedBy: request.user!.uid}, {merge: true}); response.json({data: {id: ref.id}}); });
  router.delete(`/administration/catalogs/${catalog}/:id`, authenticate, requireRoles(...administrators), async (request, response) => { const ref = db.collection("systemConfiguration").doc(catalog).collection("items").doc(String(request.params.id)); await ref.update({active: false, archivedAt: FieldValue.serverTimestamp(), archivedBy: request.user!.uid}); response.json({data: {id: ref.id, active: false}}); });
}

const configurationNames = ["environmentalFormulas", "systemSettings", "integrations"] as const;
for (const name of configurationNames) {
  router.get(`/administration/configuration/${name}`, authenticate, requireRoles(...administrators), async (_request, response) => { const snapshot = await db.collection("systemConfiguration").doc(name).get(); const data = snapshot.exists ? documentJson(snapshot.id, snapshot.data()!) : {id: name, values: {}}; if (name === "integrations" && "values" in data) data.values = Object.fromEntries(Object.entries(data.values as Record<string, unknown>).map(([key, value]) => [key, typeof value === "object" && value ? {...value as object, secret: undefined, apiKey: undefined} : value])); response.json({data}); });
  router.put(`/administration/configuration/${name}`, authenticate, requireRoles(...administrators), async (request, response) => { const input = z.object({values: z.record(z.string(), z.unknown())}).parse(request.body); await db.collection("systemConfiguration").doc(name).set({...input, updatedAt: FieldValue.serverTimestamp(), updatedBy: request.user!.uid}, {merge: true}); response.json({data: {id: name}}); });
}

router.get("/administration/health", authenticate, requireRoles(...administrators), async (_request, response) => {
  const started = Date.now();
  const firestore = await db.collection("systemMetadata").doc("health").get().then(() => "operational").catch(() => "degraded");
  const configuration = await db.collection("systemConfiguration").limit(1).get().then((snapshot) => snapshot.empty ? "degraded" : "operational").catch(() => "degraded");
  response.json({data: {status: firestore === "operational" ? "operational" : "degraded", services: {authentication: "operational", firestore, configuration}, uptimeSeconds: Math.floor(process.uptime()), responseTimeMs: Date.now() - started, nodeVersion: process.version, checkedAt: new Date().toISOString()}});
});

export default router;
