import {createHash} from "node:crypto";
import {Router, type RequestHandler} from "express";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {z} from "zod";
import {authenticate, requireRoles} from "./auth.js";
import {db} from "./firebase.js";
import {documentJson} from "./firestore-json.js";
import {ApiError} from "./errors.js";

const router = Router();
const auditors = ["administrator", "superAdministrator", "environmentalOfficer"] as const;
const mutatingMethods = new Set(["POST", "PUT", "PATCH", "DELETE"]);

type AuditInput = {
  action: string;
  resourceType: string;
  resourceId?: string;
  outcome?: "success" | "failure";
  description?: string;
  metadata?: Record<string, unknown>;
  actorId?: string;
  actorRole?: string;
  ipAddress?: string;
  deviceInformation?: string;
};

function digest(value: Record<string, unknown>) {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

export async function appendAuditRecord(input: AuditInput) {
  const chainRef = db.collection("systemMetadata").doc("auditChain");
  const logRef = db.collection("auditLogs").doc();
  await db.runTransaction(async (transaction) => {
    const chain = await transaction.get(chainRef);
    const sequence = Number(chain.get("sequence") ?? 0) + 1;
    const previousHash = String(chain.get("lastHash") ?? "GENESIS");
    const occurredAt = Timestamp.now();
    const immutable = {
      id: logRef.id,
      sequence,
      previousHash,
      action: input.action,
      resourceType: input.resourceType,
      resourceId: input.resourceId ?? "",
      outcome: input.outcome ?? "success",
      description: input.description ?? "",
      metadata: input.metadata ?? {},
      actorId: input.actorId ?? "system",
      actorRole: input.actorRole ?? "system",
      ipAddress: input.ipAddress ?? "",
      deviceInformation: input.deviceInformation ?? "",
      occurredAt: occurredAt.toMillis(),
    };
    const hash = digest(immutable);
    transaction.create(logRef, {...immutable, occurredAt, hash});
    transaction.set(chainRef, {sequence, lastHash: hash, updatedAt: occurredAt});
  });
  return logRef.id;
}

export const auditMutations: RequestHandler = (request, response, next) => {
  if (!mutatingMethods.has(request.method) || request.path.startsWith("/audit")) return next();
  response.on("finish", () => {
    if (!request.user || response.statusCode >= 400) return;
    void appendAuditRecord({
      action: `${request.method.toLowerCase()}.${request.path.replace(/^\//, "").replace(/\//g, ".")}`,
      resourceType: request.path.split("/").filter(Boolean)[0] ?? "api",
      outcome: "success",
      description: `${request.method} ${request.originalUrl}`,
      actorId: request.user.uid,
      actorRole: request.user.role,
      ipAddress: request.ip,
      deviceInformation: request.header("user-agent") ?? "",
      metadata: {statusCode: response.statusCode},
    }).catch((error: unknown) => console.error("Unable to append audit record", error));
  });
  next();
};

const eventSchema = z.object({
  action: z.enum(["login", "logout", "create", "update", "delete", "approve", "reject", "payment", "itemMovement", "roleChange", "permissionChange", "configurationChange", "security", "system"]),
  resourceType: z.string().trim().min(1).max(100),
  resourceId: z.string().trim().max(200).default(""),
  outcome: z.enum(["success", "failure"]).default("success"),
  description: z.string().trim().max(1000).default(""),
  metadata: z.record(z.string(), z.unknown()).default({}),
});

router.post("/audit/events", authenticate, async (request, response) => {
  const input = eventSchema.parse(request.body);
  const id = await appendAuditRecord({...input, actorId: request.user!.uid, actorRole: request.user!.role, ipAddress: request.ip, deviceInformation: request.header("user-agent") ?? ""});
  response.status(201).json({data: {id}});
});

function filteredQuery(request: Parameters<RequestHandler>[0]) {
  let query: FirebaseFirestore.Query = db.collection("auditLogs");
  if (typeof request.query.actorId === "string") query = query.where("actorId", "==", request.query.actorId);
  if (typeof request.query.action === "string") query = query.where("action", "==", request.query.action);
  if (typeof request.query.resourceType === "string") query = query.where("resourceType", "==", request.query.resourceType);
  if (typeof request.query.outcome === "string") query = query.where("outcome", "==", request.query.outcome);
  if (typeof request.query.from === "string") query = query.where("occurredAt", ">=", Timestamp.fromDate(new Date(request.query.from)));
  if (typeof request.query.to === "string") query = query.where("occurredAt", "<=", Timestamp.fromDate(new Date(request.query.to)));
  return query.orderBy("occurredAt", "desc").limit(Math.min(Number(request.query.limit ?? 200), 1000));
}

router.get("/audit/events", authenticate, requireRoles(...auditors), async (request, response) => {
  const snapshot = await filteredQuery(request).get();
  const search = typeof request.query.search === "string" ? request.query.search.toLowerCase() : "";
  const data = snapshot.docs.map((doc) => documentJson(doc.id, doc.data())).filter((item) => !search || JSON.stringify(item).toLowerCase().includes(search));
  response.json({data});
});

router.get("/audit/export", authenticate, requireRoles(...auditors), async (request, response) => {
  const snapshot = await filteredQuery(request).get();
  const rows = snapshot.docs.map((doc) => documentJson(doc.id, doc.data()));
  if (request.query.format !== "csv") return response.json({data: rows, exportedAt: new Date().toISOString()});
  const columns = ["id", "sequence", "occurredAt", "actorId", "actorRole", "action", "resourceType", "resourceId", "outcome", "ipAddress", "deviceInformation", "hash"];
  const escape = (value: unknown) => `"${String(value ?? "").replace(/"/g, '""')}"`;
  response.type("text/csv").attachment("ecotrace-audit.csv").send([columns.join(","), ...rows.map((row) => columns.map((column) => escape(row[column])).join(","))].join("\n"));
});

router.get("/audit/integrity", authenticate, requireRoles(...auditors), async (_request, response) => {
  const snapshot = await db.collection("auditLogs").orderBy("sequence").limit(10000).get();
  let previousHash = "GENESIS";
  for (const doc of snapshot.docs) {
    const data = doc.data();
    const immutable = {id: doc.id, sequence: data.sequence, previousHash: data.previousHash, action: data.action, resourceType: data.resourceType, resourceId: data.resourceId, outcome: data.outcome, description: data.description, metadata: data.metadata, actorId: data.actorId, actorRole: data.actorRole, ipAddress: data.ipAddress, deviceInformation: data.deviceInformation, occurredAt: data.occurredAt.toMillis()};
    if (data.previousHash !== previousHash || data.hash !== digest(immutable)) throw new ApiError(409, `Audit chain integrity failed at sequence ${data.sequence}.`, "audit_integrity_failed");
    previousHash = data.hash;
  }
  response.json({data: {valid: true, recordsVerified: snapshot.size, lastHash: previousHash}});
});

export default router;
