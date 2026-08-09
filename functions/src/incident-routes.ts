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

const incidentTypeSchema = z.preprocess(
  (value) => {
    if (typeof value !== "string") return "other";
    return (
      {
        hazard: "hazardousExposure",
        risk: "operationalRisk",
      }[value] ?? value
    );
  },
  z.enum([
    "accident",
    "hazardousExposure",
    "injury",
    "equipmentDamage",
    "nearMiss",
    "fire",
    "spill",
    "security",
    "operationalRisk",
    "other",
  ]),
);

const incidentSeveritySchema = z.preprocess(
  (value) => {
    if (typeof value !== "string") return "moderate";
    return (
      {
        medium: "moderate",
      }[value] ?? value
    );
  },
  z.enum(["low", "moderate", "high", "critical"]),
);

const incidentStatusSchema = z.preprocess(
  (value) => {
    if (typeof value !== "string") return "reported";
    return (
      {
        open: "reported",
      }[value] ?? value
    );
  },
  z.enum([
    "reported",
    "immediateResponse",
    "investigating",
    "correctiveAction",
    "followUp",
    "closed",
  ]),
);

router.get(
  "/incidents",
  authenticate,
  requireRoles(...users),
  async (_request, response) => {
    const snapshot = await db.collection("incidents").limit(500).get();
    response.json({
      data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data())),
    });
  },
);

router.post(
  "/incidents",
  authenticate,
  requireRoles(...users),
  async (request, response) => {
    const input = z
      .object({
        title: z.string().trim().min(2).max(300),
        description: z.string().trim().min(5).max(4000),
        incidentType: z
          .enum([
            "accident",
            "hazard",
            "hazardousExposure",
            "injury",
            "equipmentDamage",
            "nearMiss",
            "fire",
            "spill",
            "security",
            "risk",
            "operationalRisk",
            "other",
          ])
          .default("risk"),
        location: z.string().trim().min(2).max(400).default(""),
        latitude: z.number().min(-90).max(90).nullable().default(null),
        longitude: z.number().min(-180).max(180).nullable().default(null),
        reportedBy: z.string().trim().min(1).max(200).default(""),
        staffInvolved: z.array(z.string().trim().min(1)).default([]),
        injuryDetails: z.string().trim().max(2000).default(""),
        hazardType: z.string().trim().max(200).default(""),
        immediateResponseAction: z.string().trim().max(2000).default(""),
        investigationStatus: incidentStatusSchema.default("reported"),
        severity: incidentSeveritySchema.default("moderate"),
        rootCause: z.string().trim().max(4000).default(""),
        correctiveAction: z.string().trim().max(4000).default(""),
        followUpMonitoring: z.string().trim().max(4000).default(""),
        emergencyContacts: z.array(z.string().trim().min(1)).default([]),
        photoUrls: z.array(z.string().url()).default([]),
        occurredAt: z.coerce.date().nullable().default(null),
      })
      .parse(request.body);

    const ref = await db.collection("incidents").add({
      ...input,
      occurredAt: input.occurredAt
        ? Timestamp.fromDate(input.occurredAt)
        : null,
      createdBy: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    response.status(201).json({ data: { id: ref.id } });
  },
);

router.get(
  "/safety/emergency-contacts",
  authenticate,
  requireRoles(...users),
  async (_request, response) => {
    const snapshot = await db.collection("emergencyContacts").limit(500).get();
    response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
  },
);

router.post(
  "/safety/emergency-contacts",
  authenticate,
  requireRoles(...managers),
  async (request, response) => {
    const input = z.object({name: z.string().trim().min(2).max(200), role: z.string().trim().min(2).max(200),
      phone: z.string().trim().min(3).max(40), email: z.string().trim().email().or(z.literal("")),
      region: z.string().trim().min(2).max(200), active: z.boolean().default(true)}).parse(request.body);
    const ref = await db.collection("emergencyContacts").add({...input, createdBy: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
    response.status(201).json({data: {id: ref.id}});
  },
);

router.get(
  "/incidents/:id",
  authenticate,
  requireRoles(...users),
  async (request, response) => {
    const snapshot = await db
      .collection("incidents")
      .doc(id(request.params.id))
      .get();
    if (!snapshot.exists) {
      response.status(404).json({
        error: { code: "not_found", message: "Incident not found." },
      });
      return;
    }
    response.json({ data: documentJson(snapshot.id, snapshot.data()!) });
  },
);

router.patch(
  "/incidents/:id/investigate",
  authenticate,
  requireRoles(...managers),
  async (request, response) => {
    const ref = db.collection("incidents").doc(id(request.params.id));
    const snapshot = await ref.get();
    if (!snapshot.exists) {
      response.status(404).json({
        error: { code: "not_found", message: "Incident not found." },
      });
      return;
    }
    await ref.update({
      investigationStatus: "investigating",
      investigatorId: request.user!.uid,
      investigationStartedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    response.json({ data: { id: ref.id } });
  },
);

router.patch(
  "/incidents/:id/root-cause",
  authenticate,
  requireRoles(...managers),
  async (request, response) => {
    const input = z
      .object({
        rootCause: z.string().trim().max(4000).default(""),
        correctiveAction: z.string().trim().max(4000).default(""),
        correctiveOwner: z.string().trim().max(200).default(""),
        correctiveDueAt: z.coerce.date().nullable().default(null),
      })
      .parse(request.body);
    const ref = db.collection("incidents").doc(id(request.params.id));
    const snapshot = await ref.get();
    if (!snapshot.exists) {
      response.status(404).json({
        error: { code: "not_found", message: "Incident not found." },
      });
      return;
    }
    await ref.update({
      investigationStatus: "correctiveAction",
      rootCause: input.rootCause,
      correctiveAction: input.correctiveAction,
      correctiveOwner: input.correctiveOwner,
      correctiveDueAt: input.correctiveDueAt
        ? Timestamp.fromDate(input.correctiveDueAt)
        : null,
      updatedAt: FieldValue.serverTimestamp(),
    });
    response.json({ data: { id: ref.id } });
  },
);

router.post(
  "/incidents/:id/follow-ups",
  authenticate,
  requireRoles(...managers),
  async (request, response) => {
    const input = z
      .object({
        findings: z.string().trim().min(1).max(4000),
        riskRemaining: z.boolean().default(false),
      })
      .parse(request.body);
    const ref = db.collection("incidents").doc(id(request.params.id));
    const snapshot = await ref.get();
    if (!snapshot.exists) {
      response.status(404).json({
        error: { code: "not_found", message: "Incident not found." },
      });
      return;
    }
    await db.runTransaction(async (tx) => {
      tx.set(ref.collection("followUps").doc(), {
        findings: input.findings,
        riskRemaining: input.riskRemaining,
        recordedBy: request.user!.uid,
        recordedAt: FieldValue.serverTimestamp(),
      });
      tx.update(ref, {
        investigationStatus: input.riskRemaining
          ? "followUp"
          : "correctiveAction",
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
    response.json({ data: { id: ref.id } });
  },
);

router.get(
  "/incidents/:id/follow-ups",
  authenticate,
  requireRoles(...users),
  async (request, response) => {
    const ref = db.collection("incidents").doc(id(request.params.id));
    const snapshot = await ref.get();
    if (!snapshot.exists) {
      response.status(404).json({
        error: { code: "not_found", message: "Incident not found." },
      });
      return;
    }
    const followUps = await ref
      .collection("followUps")
      .orderBy("recordedAt", "desc")
      .limit(200)
      .get();
    response.json({
      data: followUps.docs.map((doc) => documentJson(doc.id, doc.data())),
    });
  },
);

router.patch(
  "/incidents/:id/close",
  authenticate,
  requireRoles(...managers),
  async (request, response) => {
    const ref = db.collection("incidents").doc(id(request.params.id));
    const snapshot = await ref.get();
    if (!snapshot.exists) {
      response.status(404).json({
        error: { code: "not_found", message: "Incident not found." },
      });
      return;
    }
    await ref.update({
      investigationStatus: "closed",
      updatedAt: FieldValue.serverTimestamp(),
      closedAt: FieldValue.serverTimestamp(),
      closureNotes: request.body?.closureNotes ?? "",
    });
    response.json({ data: { id: ref.id } });
  },
);

router.get(
  "/incidents/statistics",
  authenticate,
  requireRoles(...managers),
  async (_request, response) => {
    const snapshot = await db.collection("incidents").limit(500).get();
    const incidents = snapshot.docs.map((doc) => doc.data());
    const summary = {
      total: incidents.length,
      open: incidents.filter(
        (incident) => incident.investigationStatus !== "closed",
      ).length,
      closed: incidents.filter(
        (incident) => incident.investigationStatus === "closed",
      ).length,
      critical: incidents.filter((incident) => incident.severity === "critical")
        .length,
    };
    response.json({ data: summary });
  },
);

router.get(
  "/incidents/emergency-contacts",
  authenticate,
  requireRoles(...users),
  async (_request, response) => {
    const snapshot = await db.collection("emergencyContacts").limit(500).get();
    response.json({
      data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data())),
    });
  },
);

router.post(
  "/incidents/emergency-contacts",
  authenticate,
  requireRoles(...managers),
  async (request, response) => {
    const input = z.object({
      name: z.string().trim().min(2).max(200),
      role: z.string().trim().min(2).max(200),
      phone: z.string().trim().min(3).max(40),
      email: z.string().trim().email().or(z.literal("")),
      region: z.string().trim().min(2).max(200),
      active: z.boolean().default(true),
    }).parse(request.body);
    const ref = await db.collection("emergencyContacts").add({
      ...input,
      createdBy: request.user!.uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    response.status(201).json({ data: { id: ref.id } });
  },
);

export default router;
