import { Router } from "express";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { z } from "zod";
import { authenticate, requireRoles } from "./auth.js";
import { ApiError } from "./errors.js";
import { db } from "./firebase.js";
import { documentJson } from "./firestore-json.js";
import { publishNotificationEvent } from "./push-events.js";

async function administratorIds(): Promise<string[]> {
  const snapshot = await db
    .collection("users")
    .where("role", "in", ["administrator", "superAdministrator"])
    .limit(200)
    .get();
  return snapshot.docs.map((doc) => doc.id);
}

const router = Router();
const managers = [
  "environmentalOfficer",
  "administrator",
  "superAdministrator",
] as const;
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
function id(value: string | string[]) {
  return Array.isArray(value) ? value[0] : value;
}
function number(value: unknown) {
  return Number(value ?? 0);
}
async function regulatoryBodyRecord(idValue: string) {
  const ref = db.collection("regulatoryBodies").doc(idValue);
  const snapshot = await ref.get();
  if (!snapshot.exists) {
    throw new ApiError(404, "Regulatory body not found.", "not_found");
  }
  return { ref, snapshot };
}

router.get(
  "/compliance/regulatory-bodies",
  authenticate,
  requireRoles(...managers),
  async (_request, response) => {
    const snapshot = await db.collection("regulatoryBodies").limit(500).get();
    response.json({
      data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data())),
    });
  },
);

router.post(
  "/compliance/regulatory-bodies",
  authenticate,
  requireRoles(...managers),
  async (request, response) => {
    const input = z
      .object({
        name: z.string().trim().min(2).max(300),
        jurisdiction: z.string().trim().min(2).max(200),
        contactEmail: z.string().trim().email().optional().default(""),
        contactPhone: z.string().trim().max(40).optional().default(""),
        website: z.string().trim().url().optional().default(""),
        active: z.boolean().default(true),
      })
      .parse(request.body);
    const ref = await db.collection("regulatoryBodies").add({
      ...input,
      createdBy: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    response.status(201).json({ data: { id: ref.id } });
  },
);

router.get(
  "/compliance/licences",
  authenticate,
  requireRoles(...managers),
  async (_request, response) => {
    const snapshot = await db.collection("complianceLicences").limit(500).get();
    response.json({
      data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data())),
    });
  },
);

router.post(
  "/compliance/licences",
  authenticate,
  requireRoles(...managers),
  async (request, response) => {
    const input = z
      .object({
        entityId: z.string().trim().min(1),
        entityName: z.string().trim().default(""),
        entityType: z.enum(["partner", "centre", "organization", "person"]),
        licenseNumber: z.string().trim().min(2).max(100),
        category: z.string().trim().min(2).max(200),
        issuedAt: z.coerce.date(),
        expiresAt: z.coerce.date(),
        status: z
          .enum(["active", "expired", "pending", "suspended"])
          .default("active"),
        regulatoryBodyId: z.string().trim().min(1).default(""),
      })
      .parse(request.body);
    const ref = await db.collection("complianceLicences").add({
      ...input,
      issuedAt: Timestamp.fromDate(input.issuedAt),
      expiresAt: Timestamp.fromDate(input.expiresAt),
      createdBy: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    response.status(201).json({ data: { id: ref.id } });
  },
);

router.get(
  "/compliance/certifications",
  authenticate,
  requireRoles(...managers),
  async (_request, response) => {
    const snapshot = await db
      .collection("recyclerCertifications")
      .limit(500)
      .get();
    response.json({
      data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data())),
    });
  },
);

router.post(
  "/compliance/certifications",
  authenticate,
  requireRoles(...managers),
  async (request, response) => {
    const input = z
      .object({
        recyclerId: z.string().trim().min(1),
        certificateNumber: z.string().trim().min(2).max(100),
        certificationType: z.string().trim().min(2).max(200),
        issuedAt: z.coerce.date(),
        expiresAt: z.coerce.date(),
        status: z
          .enum(["active", "expired", "pending", "revoked"])
          .default("active"),
      })
      .parse(request.body);
    const ref = await db.collection("recyclerCertifications").add({
      ...input,
      issuedAt: Timestamp.fromDate(input.issuedAt),
      expiresAt: Timestamp.fromDate(input.expiresAt),
      createdBy: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    response.status(201).json({ data: { id: ref.id } });
  },
);

router.get(
  "/compliance/checklists",
  authenticate,
  requireRoles(...managers),
  async (_request, response) => {
    const snapshot = await db
      .collection("complianceChecklists")
      .limit(500)
      .get();
    response.json({
      data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data())),
    });
  },
);

router.post(
  "/compliance/checklists",
  authenticate,
  requireRoles(...managers),
  async (request, response) => {
    const input = z
      .object({
        title: z.string().trim().min(2).max(300),
        category: z.string().trim().min(2).max(200),
        items: z
          .array(
            z.object({
              label: z.string().trim().min(1),
              required: z.boolean().default(true),
              completed: z.boolean().default(false),
            }),
          )
          .default([]),
        assignedTo: z.string().trim().max(200).default(""),
        dueAt: z.coerce.date().nullable().default(null),
      })
      .parse(request.body);
    const ref = await db.collection("complianceChecklists").add({
      ...input,
      dueAt: input.dueAt ? Timestamp.fromDate(input.dueAt) : null,
      createdBy: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    response.status(201).json({ data: { id: ref.id } });
  },
);

router.get(
  "/compliance/inspections",
  authenticate,
  requireRoles(...managers),
  async (_request, response) => {
    const snapshot = await db
      .collection("complianceInspections")
      .limit(500)
      .get();
    response.json({
      data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data())),
    });
  },
);

router.post(
  "/compliance/inspections",
  authenticate,
  requireRoles(...managers),
  async (request, response) => {
    const input = z
      .object({
        entityId: z.string().trim().min(1),
        entityType: z.enum(["partner", "centre", "organization"]),
        regulatoryBodyId: z.string().trim().min(1),
        scheduledAt: z.coerce.date(),
        inspectorName: z.string().trim().min(2).max(200),
        findings: z.string().trim().max(4000).default(""),
        recommendations: z.string().trim().max(4000).default(""),
        checklist: z.record(z.string(), z.boolean()).default({}),
        reportUrls: z.array(z.string().url()).max(10).default([]),
        score: z.number().min(0).max(100).default(100),
        status: z
          .enum(["scheduled", "completed", "overdue", "cancelled"])
          .default("scheduled"),
      })
      .parse(request.body);
    const ref = await db.collection("complianceInspections").add({
      ...input,
      scheduledAt: Timestamp.fromDate(input.scheduledAt),
      createdBy: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    response.status(201).json({ data: { id: ref.id } });
  },
);

router.get(
  "/compliance/violations",
  authenticate,
  requireRoles(...managers),
  async (_request, response) => {
    const snapshot = await db
      .collection("complianceViolations")
      .limit(500)
      .get();
    response.json({
      data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data())),
    });
  },
);

router.post(
  "/compliance/violations",
  authenticate,
  requireRoles(...managers),
  async (request, response) => {
    const input = z
      .object({
        entityId: z.string().trim().min(1),
        entityName: z.string().trim().default(""),
        entityType: z.enum(["partner", "centre", "organization"]),
        violationType: z.string().trim().min(2).max(200),
        requirement: z.string().trim().default(""),
        referenceNumber: z.string().trim().default(""),
        description: z.string().trim().min(5).max(4000),
        severity: z
          .enum(["low", "medium", "high", "critical"])
          .default("medium"),
        detectedAt: z.coerce.date(),
        correctiveActionDueAt: z.coerce.date().nullable().default(null),
        status: z.string().trim().default("open"),
      })
      .parse(request.body);
    const ref = await db.collection("complianceViolations").add({
      ...input,
      detectedAt: Timestamp.fromDate(input.detectedAt),
      correctiveActionDueAt: input.correctiveActionDueAt
        ? Timestamp.fromDate(input.correctiveActionDueAt)
        : null,
      createdBy: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    void administratorIds().then((affectedUserIds) =>
      publishNotificationEvent({
        event: "compliance_violation_recorded",
        affectedUserIds,
        body: `${input.severity} severity violation recorded for ${input.entityName || input.entityId}: ${input.violationType}.`,
        data: {violationId: ref.id, entityId: input.entityId, severity: input.severity},
      }),
    );
    response.status(201).json({ data: { id: ref.id } });
  },
);

router.get(
  "/compliance/corrective-actions",
  authenticate,
  requireRoles(...managers),
  async (_request, response) => {
    const snapshot = await db
      .collection("correctiveActionPlans")
      .limit(500)
      .get();
    response.json({
      data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data())),
    });
  },
);

router.post(
  "/compliance/corrective-actions",
  authenticate,
  requireRoles(...managers),
  async (request, response) => {
    const input = z
      .object({
        violationId: z.string().trim().min(1),
        title: z.string().trim().min(2).max(300),
        description: z.string().trim().min(5).max(4000),
        owner: z.string().trim().min(1),
        dueAt: z.coerce.date(),
        status: z
          .enum(["open", "inProgress", "completed", "overdue"])
          .default("open"),
      })
      .parse(request.body);
    const ref = await db.collection("correctiveActionPlans").add({
      ...input,
      dueAt: Timestamp.fromDate(input.dueAt),
      createdBy: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    response.status(201).json({ data: { id: ref.id } });
  },
);

router.get(
  "/compliance/penalties",
  authenticate,
  requireRoles(...managers),
  async (_request, response) => {
    const snapshot = await db.collection("penaltyRecords").limit(500).get();
    response.json({
      data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data())),
    });
  },
);

router.post(
  "/compliance/penalties",
  authenticate,
  requireRoles(...managers),
  async (request, response) => {
    const input = z
      .object({
        entityId: z.string().trim().min(1),
        violationId: z.string().trim().default(""),
        entityType: z.enum(["partner", "centre", "organization"]),
        penaltyType: z.string().trim().min(2).max(200),
        referenceNumber: z.string().trim().default(""),
        amount: z.number().min(0),
        currency: z.string().trim().min(3).max(10).default("USD"),
        issuedAt: z.coerce.date(),
        dueAt: z.coerce.date().nullable().default(null),
        notes: z.string().trim().max(4000).default(""),
        status: z
          .enum(["issued", "paid", "appealed", "waived"])
          .default("issued"),
      })
      .parse(request.body);
    const ref = await db.collection("penaltyRecords").add({
      ...input,
      issuedAt: Timestamp.fromDate(input.issuedAt),
      dueAt: input.dueAt ? Timestamp.fromDate(input.dueAt) : null,
      createdBy: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    response.status(201).json({ data: { id: ref.id } });
  },
);

router.get(
  "/compliance/certificates",
  authenticate,
  requireRoles(...managers),
  async (_request, response) => {
    const snapshot = await db
      .collection("environmentalCertificates")
      .limit(500)
      .get();
    response.json({
      data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data())),
    });
  },
);

router.post(
  "/compliance/certificates",
  authenticate,
  requireRoles(...managers),
  async (request, response) => {
    const input = z
      .object({
        entityId: z.string().trim().min(1),
        certificateType: z.string().trim().min(2).max(200),
        certificateNumber: z.string().trim().min(2).max(100),
        issuedAt: z.coerce.date(),
        expiresAt: z.coerce.date(),
        status: z
          .enum(["active", "expired", "pending", "revoked"])
          .default("active"),
      })
      .parse(request.body);
    const ref = await db.collection("environmentalCertificates").add({
      ...input,
      issuedAt: Timestamp.fromDate(input.issuedAt),
      expiresAt: Timestamp.fromDate(input.expiresAt),
      createdBy: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    response.status(201).json({ data: { id: ref.id } });
  },
);

router.get(
  "/compliance/expiry-alerts",
  authenticate,
  requireRoles(...managers),
  async (_request, response) => {
    const snapshot = await db
      .collection("complianceExpiryAlerts")
      .limit(500)
      .get();
    response.json({
      data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data())),
    });
  },
);

router.post(
  "/compliance/expiry-alerts",
  authenticate,
  requireRoles(...managers),
  async (request, response) => {
    const input = z
      .object({
        entityId: z.string().trim().min(1),
        entityType: z.enum(["license", "certificate", "inspection"]),
        title: z.string().trim().min(2).max(300),
        dueAt: z.coerce.date(),
        severity: z
          .enum(["low", "medium", "high", "critical"])
          .default("medium"),
      })
      .parse(request.body);
    const ref = await db.collection("complianceExpiryAlerts").add({
      ...input,
      dueAt: Timestamp.fromDate(input.dueAt),
      createdBy: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    response.status(201).json({ data: { id: ref.id } });
  },
);

router.get(
  "/compliance/submissions",
  authenticate,
  requireRoles(...managers),
  async (_request, response) => {
    const snapshot = await db
      .collection("regulatorySubmissions")
      .limit(500)
      .get();
    response.json({
      data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data())),
    });
  },
);

router.post(
  "/compliance/submissions",
  authenticate,
  requireRoles(...managers),
  async (request, response) => {
    const input = z
      .object({
        entityId: z.string().trim().min(1),
        submissionType: z.string().trim().min(2).max(200),
        regulatoryBodyId: z.string().trim().min(1),
        submittedAt: z.coerce.date(),
        status: z
          .enum(["draft", "submitted", "accepted", "rejected"])
          .default("draft"),
        documentUrls: z.array(z.string().url()).max(10).default([]),
      })
      .parse(request.body);
    const ref = await db.collection("regulatorySubmissions").add({
      ...input,
      submittedAt: Timestamp.fromDate(input.submittedAt),
      createdBy: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    response.status(201).json({ data: { id: ref.id } });
  },
);

router.get(
  "/compliance/score",
  authenticate,
  requireRoles(...users),
  async (request, response) => {
    const snapshot = await db
      .collection("complianceScores")
      .doc(request.user!.uid)
      .get();
    response.json({
      data: snapshot.exists
        ? documentJson(snapshot.id, snapshot.data()!)
        : {
            id: request.user!.uid,
            overallScore: 0,
            rating: "unknown",
            lastUpdatedAt: null,
          },
    });
  },
);

router.put(
  "/compliance/score",
  authenticate,
  requireRoles(...managers),
  async (request, response) => {
    const input = z
      .object({
        entityId: z.string().trim().min(1),
        overallScore: z.number().min(0).max(100),
        rating: z
          .enum(["excellent", "good", "fair", "poor", "unknown"])
          .default("unknown"),
      })
      .parse(request.body);
    await db
      .collection("complianceScores")
      .doc(input.entityId)
      .set(
        {
          ...input,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    response.json({ data: { id: input.entityId } });
  },
);

router.get(
  "/compliance/audit-report",
  authenticate,
  requireRoles(...managers),
  async (_request, response) => {
    const [
      bodies,
      licences,
      inspections,
      violations,
      penalties,
      certificates,
      submissions,
    ] = await Promise.all([
      db.collection("regulatoryBodies").limit(500).get(),
      db.collection("complianceLicences").limit(500).get(),
      db.collection("complianceInspections").limit(500).get(),
      db.collection("complianceViolations").limit(500).get(),
      db.collection("penaltyRecords").limit(500).get(),
      db.collection("environmentalCertificates").limit(500).get(),
      db.collection("regulatorySubmissions").limit(500).get(),
    ]);
    response.json({
      data: {
        generatedAt: new Date().toISOString(),
        regulatoryBodies: bodies.size,
        licences: licences.size,
        inspections: inspections.size,
        violations: violations.size,
        penalties: penalties.size,
        certificates: certificates.size,
        submissions: submissions.size,
        complianceScore: violations.docs.length
          ? Math.max(0, 100 - violations.docs.length * 10)
          : 100,
        summary: {
          openViolations: violations.docs.filter(
            (doc) =>
              String(doc.get("severity") ?? "") === "high" ||
              String(doc.get("severity") ?? "") === "critical",
          ).length,
          activeLicences: licences.docs.filter(
            (doc) => String(doc.get("status") ?? "") === "active",
          ).length,
          pendingSubmissions: submissions.docs.filter(
            (doc) => String(doc.get("status") ?? "") === "draft",
          ).length,
        },
      },
    });
  },
);

export default router;
