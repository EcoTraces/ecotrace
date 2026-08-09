import { Router } from "express";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { z } from "zod";
import { authenticate, requireRoles } from "./auth.js";
import { db } from "./firebase.js";
import { documentJson } from "./firestore-json.js";

const router = Router();
function id(value: string | string[]) {
  return Array.isArray(value) ? value[0] : value;
}

const users = [
  "household",
  "business",
  "institution",
  "collector",
  "driver",
  "collectionCentreOperator",
  "repairTechnician",
  "recycler",
  "environmentalOfficer",
  "administrator",
  "superAdministrator",
] as const;
const managers = [
  "environmentalOfficer",
  "administrator",
  "superAdministrator",
] as const;
const isManager = (role: string) => (managers as readonly string[]).includes(role);

router.get(
  "/documents",
  authenticate,
  requireRoles(...users),
  async (request, response) => {
    const snapshot = await db.collection("documents").limit(500).get();
    response.json({
      data: snapshot.docs
        .filter((doc) => isManager(request.user!.role) || doc.get("ownerId") === request.user!.uid)
        .map((doc) => documentJson(doc.id, doc.data())),
    });
  },
);

router.post(
  "/documents",
  authenticate,
  requireRoles(...managers),
  async (request, response) => {
    const input = z
      .object({
        title: z.string().trim().min(2).max(300),
        category: z.string().trim().min(2).max(200),
        description: z.string().trim().max(4000).default(""),
        documentType: z
          .enum([
            "licence",
            "certificate",
            "contract",
            "inspectionReport",
            "identityDocument",
            "policy",
            "other",
          ])
          .default("other"),
        fileUrl: z.string().url().default(""),
        fileName: z.string().trim().min(1).max(500).default(""),
        mimeType: z.string().trim().min(1).max(200).default(""),
        currentVersion: z.number().int().min(1).default(1),
        status: z
          .enum(["draft", "pendingApproval", "approved", "archived"])
          .default("draft"),
        ownerId: z.string().trim().min(1).default(""),
        ownerName: z.string().trim().default(""),
        accessLevel: z
          .enum(["owner", "staff", "governance", "administrators"])
          .default("owner"),
        referenceNumber: z.string().trim().default(""),
        approverId: z.string().trim().min(1).default(""),
        expiresAt: z.coerce.date().nullable().default(null),
        tags: z.array(z.string().trim().min(1)).default([]),
        secureAccess: z.boolean().default(true),
      })
      .parse(request.body);

    const ref = await db.collection("documents").add({
      ...input,
      fileName: input.fileName,
      mimeType: input.mimeType,
      url: input.fileUrl,
      currentVersion: input.currentVersion,
      referenceNumber: input.referenceNumber,
      ownerName: input.ownerName,
      expiresAt: input.expiresAt ? Timestamp.fromDate(input.expiresAt) : null,
      createdBy: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      auditTrail: [
        {
          action: "created",
          actorId: request.user!.uid,
          createdAt: FieldValue.serverTimestamp(),
        },
      ],
    });
    const batch = db.batch();
    batch.set(ref.collection("versions").doc(String(input.currentVersion)), {
      version: input.currentVersion, fileName: input.fileName, mimeType: input.mimeType,
      url: input.fileUrl, changeNotes: "Initial upload", uploadedBy: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(),
    });
    batch.set(ref.collection("auditTrail").doc(), {action: "created", actorId: request.user!.uid,
      details: "Initial document upload", createdAt: FieldValue.serverTimestamp()});
    await batch.commit();

    response.status(201).json({ data: { id: ref.id } });
  },
);

router.get(
  "/documents/:id",
  authenticate,
  requireRoles(...users),
  async (request, response) => {
    const snapshot = await db
      .collection("documents")
      .doc(id(request.params.id))
      .get();
    if (!snapshot.exists) {
      response.status(404).json({
        error: { code: "not_found", message: "Document not found." },
      });
      return;
    }
    if (!isManager(request.user!.role) && snapshot.get("ownerId") !== request.user!.uid) {
      response.status(403).json({error: {code: "forbidden", message: "You cannot access this document."}});
      return;
    }
    response.json({ data: documentJson(snapshot.id, snapshot.data()!) });
  },
);

router.patch(
  "/documents/:id/archive",
  authenticate,
  requireRoles(...managers),
  async (request, response) => {
    const ref = db.collection("documents").doc(id(request.params.id));
    const snapshot = await ref.get();
    if (!snapshot.exists) {
      response.status(404).json({
        error: { code: "not_found", message: "Document not found." },
      });
      return;
    }
    await ref.update({
      status: "archived",
      updatedAt: FieldValue.serverTimestamp(),
      auditTrail: FieldValue.arrayUnion({
        action: "archived",
        actorId: request.user!.uid,
        createdAt: FieldValue.serverTimestamp(),
      }),
    });
    await ref.collection("auditTrail").add({action: "archived", actorId: request.user!.uid,
      details: "Document archived", createdAt: FieldValue.serverTimestamp()});
    response.json({ data: { id: ref.id } });
  },
);

router.post(
  "/documents/:id/versions",
  authenticate,
  requireRoles(...managers),
  async (request, response) => {
    const input = z
      .object({
        fileUrl: z.string().url(),
        fileName: z.string().trim().min(1).max(500),
        mimeType: z.string().trim().min(1).max(200),
        changeNotes: z.string().trim().max(2000).default(""),
        version: z.number().int().min(1),
      })
      .parse(request.body);
    const ref = db.collection("documents").doc(id(request.params.id));
    const snapshot = await ref.get();
    if (!snapshot.exists) {
      response.status(404).json({
        error: { code: "not_found", message: "Document not found." },
      });
      return;
    }
    await db.runTransaction(async (tx) => {
      tx.update(ref, {
        currentVersion: input.version,
        fileName: input.fileName,
        mimeType: input.mimeType,
        url: input.fileUrl,
        status: "pendingApproval",
        updatedAt: FieldValue.serverTimestamp(),
      });
      tx.set(ref.collection("versions").doc(String(input.version)), {
        version: input.version,
        fileName: input.fileName,
        mimeType: input.mimeType,
        url: input.fileUrl,
        changeNotes: input.changeNotes,
        uploadedBy: request.user!.uid,
        createdAt: FieldValue.serverTimestamp(),
      });
      tx.set(ref.collection("auditTrail").doc(), {action: "versionAdded", actorId: request.user!.uid,
        details: input.changeNotes, createdAt: FieldValue.serverTimestamp()});
      tx.update(ref, {
        auditTrail: FieldValue.arrayUnion({
          action: "versionAdded",
          actorId: request.user!.uid,
          createdAt: FieldValue.serverTimestamp(),
        }),
      });
    });
    response.status(201).json({ data: { id: ref.id, version: input.version } });
  },
);

router.get(
  "/documents/:id/versions",
  authenticate,
  requireRoles(...users),
  async (request, response) => {
    const ref = db.collection("documents").doc(id(request.params.id));
    const snapshot = await ref.get();
    if (!snapshot.exists) {
      response.status(404).json({
        error: { code: "not_found", message: "Document not found." },
      });
      return;
    }
    const versions = await ref
      .collection("versions")
      .orderBy("version", "desc")
      .get();
    response.json({
      data: versions.docs.map((doc) => documentJson(doc.id, doc.data())),
    });
  },
);

router.get(
  "/documents/:id/audit",
  authenticate,
  requireRoles(...users),
  async (request, response) => {
    const ref = db.collection("documents").doc(id(request.params.id));
    const snapshot = await ref.get();
    if (!snapshot.exists) {
      response.status(404).json({
        error: { code: "not_found", message: "Document not found." },
      });
      return;
    }
    const auditTrail = await ref
      .collection("auditTrail")
      .orderBy("createdAt", "desc")
      .get();
    response.json({
      data: auditTrail.docs.map((doc) => documentJson(doc.id, doc.data())),
    });
  },
);

router.patch(
  "/documents/:id/approve",
  authenticate,
  requireRoles(...managers),
  async (request, response) => {
    const input = z.object({
      approved: z.boolean().default(true),
      notes: z.string().trim().max(2000).default(""),
    }).parse(request.body);
    const ref = db.collection("documents").doc(id(request.params.id));
    const snapshot = await ref.get();
    if (!snapshot.exists) {
      response.status(404).json({
        error: { code: "not_found", message: "Document not found." },
      });
      return;
    }
    await ref.update({
      status: input.approved ? "approved" : "rejected",
      approverId: request.user!.uid,
      approvalNotes: input.notes,
      updatedAt: FieldValue.serverTimestamp(),
      auditTrail: FieldValue.arrayUnion({
        action: input.approved ? "approved" : "rejected",
        actorId: request.user!.uid,
        createdAt: FieldValue.serverTimestamp(),
      }),
    });
    await ref.collection("auditTrail").add({action: input.approved ? "approved" : "rejected",
      actorId: request.user!.uid, details: input.notes, createdAt: FieldValue.serverTimestamp()});
    response.json({ data: { id: ref.id } });
  },
);

router.get(
  "/documents/bypage",
  authenticate,
  requireRoles(...users),
  async (request, response) => {
    const page = Number(request.query.page ?? 1);
    const size = Math.min(Number(request.query.size ?? 20), 100);
    const offset = (page - 1) * size;
    const snapshot = await db
      .collection("documents")
      .orderBy("createdAt", "desc")
      .offset(offset)
      .limit(size)
      .get();
    response.json({
      data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data())),
      meta: { page, size },
    });
  },
);

router.get(
  "/documents/expiring",
  authenticate,
  requireRoles(...users),
  async (_request, response) => {
    const snapshot = await db.collection("documents").limit(500).get();
    const expiring = snapshot.docs
      .filter((doc) => {
        const data = doc.data();
        const expiresAt = data.expiresAt;
        if (!expiresAt) return false;
        const expiresDate = expiresAt.toDate
          ? expiresAt.toDate()
          : new Date(expiresAt);
        return expiresDate.getTime() - Date.now() <= 60 * 24 * 60 * 60 * 1000;
      })
      .map((doc) => documentJson(doc.id, doc.data()));
    response.json({ data: expiring });
  },
);

export default router;
