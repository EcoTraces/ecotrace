import {Router} from "express";
import {FieldValue} from "firebase-admin/firestore";
import {z} from "zod";
import {authenticate, requireRoles} from "./auth.js";
import {ApiError} from "./errors.js";
import {db} from "./firebase.js";
import {documentJson} from "./firestore-json.js";
import {publishNotificationEvent} from "./push-events.js";

const router = Router();
const operators = [
  "administrator",
  "superAdministrator",
  "collectionCentreOperator",
  "environmentalOfficer",
] as const;
const categories = ["computers", "phones", "televisions", "appliances", "batteries", "accessories", "other"] as const;

function parameter(value: string | string[]): string {
  return Array.isArray(value) ? value[0] : value;
}

async function accessibleCentre(id: string, uid: string, role: string) {
  const reference = db.collection("collectionCentres").doc(id);
  const snapshot = await reference.get();
  if (!snapshot.exists) throw new ApiError(404, "Collection centre not found.", "not_found");
  const privileged = ["administrator", "superAdministrator", "environmentalOfficer"].includes(role);
  const staffIds = (snapshot.get("staffIds") ?? []) as string[];
  if (!privileged && !staffIds.includes(uid)) {
    throw new ApiError(403, "You are not assigned to this collection centre.", "forbidden");
  }
  return {reference, snapshot};
}

router.get("/collection-centres/:id", authenticate, requireRoles(...operators), async (request, response) => {
  const {snapshot} = await accessibleCentre(parameter(request.params.id), request.user!.uid, request.user!.role);
  response.json({data: documentJson(snapshot.id, snapshot.data()!)});
});

for (const resource of ["storageSections", "receivingRecords", "stockMovements", "staffAssignments", "safetyInspections", "capacityAlerts"] as const) {
  router.get("/collection-centres/:id/" + resource, authenticate, requireRoles(...operators), async (request, response) => {
    const {reference} = await accessibleCentre(parameter(request.params.id), request.user!.uid, request.user!.role);
    const snapshot = await reference.collection(resource).limit(100).get();
    response.json({data: snapshot.docs.map((document) => documentJson(document.id, document.data()))});
  });
}

router.get("/collection-centres/:id/dashboard", authenticate, requireRoles(...operators), async (request, response) => {
  const {reference, snapshot: centre} = await accessibleCentre(parameter(request.params.id), request.user!.uid, request.user!.role);
  const [records, movements, sections, inspections, staff] = await Promise.all([
    reference.collection("receivingRecords").limit(500).get(),
    reference.collection("stockMovements").limit(500).get(),
    reference.collection("storageSections").limit(100).get(),
    reference.collection("safetyInspections").limit(100).get(),
    reference.collection("staffAssignments").where("active", "==", true).limit(100).get(),
  ]);
  const capacityKg = Number(centre.get("capacityKg") ?? 0);
  const currentStockKg = Number(centre.get("currentStockKg") ?? 0);
  const verified = records.docs.filter((document) => document.get("verified") === true).length;
  const receivedWeightKg = records.docs.reduce((sum, document) => sum + Number(document.get("verifiedWeightKg") ?? document.get("recordedWeightKg") ?? 0), 0);
  const checkedOutWeightKg = movements.docs.filter((document) => document.get("type") === "checkOut").reduce((sum, document) => sum + Number(document.get("weightKg") ?? 0), 0);
  const inspectionScores = inspections.docs.map((document) => Number(document.get("score") ?? 0));
  response.json({data: {
    centreId: centre.id,
    capacityKg,
    currentStockKg,
    availableCapacityKg: Math.max(0, capacityKg - currentStockKg),
    utilizationPercent: capacityKg > 0 ? currentStockKg / capacityKg * 100 : 0,
    capacityAlert: capacityKg > 0 && currentStockKg / capacityKg * 100 >= Number(centre.get("capacityAlertPercent") ?? 80),
    receivingRecords: records.size,
    receivedWeightKg,
    verificationRate: records.size > 0 ? verified / records.size * 100 : 0,
    checkedOutWeightKg,
    storageSections: sections.size,
    activeStaff: staff.size,
    safetyInspections: inspections.size,
    averageSafetyScore: inspectionScores.length > 0 ? inspectionScores.reduce((sum, score) => sum + score, 0) / inspectionScores.length : null,
  }});
});

router.post("/collection-centres/:id/sections", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({
    name: z.string().trim().min(2).max(100),
    category: z.enum(categories),
    capacityKg: z.number().positive(),
    restricted: z.boolean().default(false),
  }).parse(request.body);
  const {reference} = await accessibleCentre(parameter(request.params.id), request.user!.uid, request.user!.role);
  const [centre, existingSections] = await Promise.all([
    reference.get(),
    reference.collection("storageSections").limit(100).get(),
  ]);
  const configuredCapacity = existingSections.docs.reduce((sum, document) => sum + Number(document.get("capacityKg") ?? 0), 0);
  if (configuredCapacity + input.capacityKg > Number(centre.get("capacityKg") ?? 0)) {
    throw new ApiError(409, "Storage section capacities exceed the centre capacity.", "section_capacity_exceeded");
  }
  if (existingSections.docs.some((document) => String(document.get("name") ?? "").toLowerCase() === input.name.toLowerCase())) {
    throw new ApiError(409, "A storage section with this name already exists.", "duplicate_section");
  }
  const section = await reference.collection("storageSections").add({
    ...input,
    currentStockKg: 0,
    createdBy: request.user!.uid,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  response.status(201).json({data: {id: section.id}});
});

router.post("/collection-centres/:id/staff", authenticate, requireRoles("administrator", "superAdministrator"), async (request, response) => {
  const input = z.object({userId: z.string().trim().min(1), role: z.string().trim().min(2).max(80)}).parse(request.body);
  const {reference} = await accessibleCentre(parameter(request.params.id), request.user!.uid, request.user!.role);
  const user = await db.collection("users").doc(input.userId).get();
  if (!user.exists) throw new ApiError(404, "Staff user not found.", "not_found");
  if (user.get("accountStatus") !== "active") throw new ApiError(409, "Only active users can be assigned.", "inactive_user");
  const batch = db.batch();
  batch.set(reference.collection("staffAssignments").doc(input.userId), {
    ...input,
    active: true,
    assignedBy: request.user!.uid,
    assignedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  batch.update(reference, {staffIds: FieldValue.arrayUnion(input.userId), updatedAt: FieldValue.serverTimestamp()});
  await batch.commit();
  void publishNotificationEvent({event: "centre_staff_assigned", recipientId: input.userId, data: {centreId: reference.id, role: input.role}});
  response.status(201).json({data: {userId: input.userId, active: true}});
});

router.patch("/collection-centres/:id/staff/:userId", authenticate, requireRoles("administrator", "superAdministrator"), async (request, response) => {
  const {active} = z.object({active: z.boolean()}).parse(request.body);
  const userId = parameter(request.params.userId);
  const {reference} = await accessibleCentre(parameter(request.params.id), request.user!.uid, request.user!.role);
  const assignment = reference.collection("staffAssignments").doc(userId);
  if (!(await assignment.get()).exists) throw new ApiError(404, "Staff assignment not found.", "not_found");
  const batch = db.batch();
  batch.update(assignment, {active, updatedBy: request.user!.uid, updatedAt: FieldValue.serverTimestamp()});
  batch.update(reference, {
    staffIds: active ? FieldValue.arrayUnion(userId) : FieldValue.arrayRemove(userId),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  response.json({data: {userId, active}});
});

router.post("/collection-centres/:id/check-ins", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({
    reference: z.string().trim().max(100).default(""),
    category: z.enum(categories),
    itemCount: z.number().int().positive(),
    weightKg: z.number().positive(),
    sectionId: z.string().trim().min(1),
    staffId: z.string().trim().min(1),
    notes: z.string().trim().max(1000).default(""),
  }).parse(request.body);
  const {reference: centreRef} = await accessibleCentre(parameter(request.params.id), request.user!.uid, request.user!.role);
  if (input.staffId !== request.user!.uid) throw new ApiError(403, "staffId must match the authenticated user.", "forbidden");
  const sectionRef = centreRef.collection("storageSections").doc(input.sectionId);
  const recordRef = centreRef.collection("receivingRecords").doc();
  let capacityAlertRaised = false;
  await db.runTransaction(async (transaction) => {
    const [centre, section] = await Promise.all([transaction.get(centreRef), transaction.get(sectionRef)]);
    if (!section.exists) throw new ApiError(404, "Storage section not found.", "not_found");
    const centreStock = Number(centre.get("currentStockKg") ?? 0);
    const centreCapacity = Number(centre.get("capacityKg") ?? 0);
    const sectionStock = Number(section.get("currentStockKg") ?? 0);
    const sectionCapacity = Number(section.get("capacityKg") ?? 0);
    if (section.get("category") !== input.category) throw new ApiError(409, "The item category does not match the selected storage section.", "section_category_mismatch");
    const supportedCategories = (centre.get("supportedCategories") ?? []) as string[];
    if (!supportedCategories.includes(input.category)) throw new ApiError(409, "This centre does not accept the selected waste category.", "unsupported_category");
    if (centreStock + input.weightKg > centreCapacity) throw new ApiError(409, "This check-in exceeds centre capacity.", "centre_capacity_exceeded");
    if (sectionStock + input.weightKg > sectionCapacity) throw new ApiError(409, "This check-in exceeds section capacity.", "section_capacity_exceeded");
    transaction.set(recordRef, {
      reference: input.reference || recordRef.id,
      category: input.category,
      itemCount: input.itemCount,
      recordedWeightKg: input.weightKg,
      verifiedWeightKg: null,
      verified: false,
      sectionId: input.sectionId,
      staffId: input.staffId,
      notes: input.notes,
      receivedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(centreRef.collection("stockMovements").doc(), {
      type: "checkIn",
      weightKg: input.weightKg,
      sectionId: input.sectionId,
      destination: section.get("name") ?? "",
      staffId: input.staffId,
      notes: "Receiving record " + recordRef.id,
      createdAt: FieldValue.serverTimestamp(),
    });
    transaction.update(centreRef, {currentStockKg: FieldValue.increment(input.weightKg), updatedAt: FieldValue.serverTimestamp()});
    transaction.update(sectionRef, {currentStockKg: FieldValue.increment(input.weightKg), updatedAt: FieldValue.serverTimestamp()});
    const alertPercent = Number(centre.get("capacityAlertPercent") ?? 80);
    const beforePercent = centreCapacity > 0 ? centreStock / centreCapacity * 100 : 0;
    const afterPercent = centreCapacity > 0 ? (centreStock + input.weightKg) / centreCapacity * 100 : 0;
    capacityAlertRaised = beforePercent < alertPercent && afterPercent >= alertPercent;
    if (capacityAlertRaised) transaction.set(centreRef.collection("capacityAlerts").doc(), {
      type: "thresholdReached", thresholdPercent: alertPercent, utilizationPercent: afterPercent,
      currentStockKg: centreStock + input.weightKg, capacityKg: centreCapacity,
      acknowledged: false, createdAt: FieldValue.serverTimestamp(), createdBy: request.user!.uid,
    });
  });
  if (capacityAlertRaised) void publishNotificationEvent({event: "centre_capacity_alert", affectedUserIds: [request.user!.uid], data: {centreId: centreRef.id}});
  response.status(201).json({data: {id: recordRef.id}});
});

router.patch("/collection-centres/:id/receiving/:recordId/verify", authenticate, requireRoles(...operators), async (request, response) => {
  const {verifiedWeightKg} = z.object({verifiedWeightKg: z.number().positive()}).parse(request.body);
  const {reference: centreRef} = await accessibleCentre(parameter(request.params.id), request.user!.uid, request.user!.role);
  const recordRef = centreRef.collection("receivingRecords").doc(parameter(request.params.recordId));
  await db.runTransaction(async (transaction) => {
    const record = await transaction.get(recordRef);
    if (!record.exists) throw new ApiError(404, "Receiving record not found.", "not_found");
    const sectionRef = centreRef.collection("storageSections").doc(String(record.get("sectionId")));
    const [centre, section] = await Promise.all([transaction.get(centreRef), transaction.get(sectionRef)]);
    if (!section.exists) throw new ApiError(404, "Storage section not found.", "not_found");
    const currentWeight = Number(record.get("verifiedWeightKg") ?? record.get("recordedWeightKg") ?? 0);
    const difference = verifiedWeightKg - currentWeight;
    const centreResult = Number(centre.get("currentStockKg") ?? 0) + difference;
    const sectionResult = Number(section.get("currentStockKg") ?? 0) + difference;
    if (centreResult < 0 || sectionResult < 0) throw new ApiError(409, "Verification would create negative stock.", "negative_stock");
    if (centreResult > Number(centre.get("capacityKg") ?? 0) || sectionResult > Number(section.get("capacityKg") ?? 0)) {
      throw new ApiError(409, "Verified weight exceeds available capacity.", "capacity_exceeded");
    }
    transaction.update(recordRef, {verifiedWeightKg, verified: true, verifiedBy: request.user!.uid, verifiedAt: FieldValue.serverTimestamp()});
    transaction.update(centreRef, {currentStockKg: FieldValue.increment(difference), updatedAt: FieldValue.serverTimestamp()});
    transaction.update(sectionRef, {currentStockKg: FieldValue.increment(difference), updatedAt: FieldValue.serverTimestamp()});
  });
  response.json({data: {id: recordRef.id, verifiedWeightKg, verified: true}});
});

router.post("/collection-centres/:id/check-outs", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({
    sectionId: z.string().trim().min(1),
    weightKg: z.number().positive(),
    destination: z.string().trim().min(2).max(300),
    staffId: z.string().trim().min(1),
    notes: z.string().trim().max(1000).default(""),
  }).parse(request.body);
  const {reference: centreRef} = await accessibleCentre(parameter(request.params.id), request.user!.uid, request.user!.role);
  if (input.staffId !== request.user!.uid) throw new ApiError(403, "staffId must match the authenticated user.", "forbidden");
  const sectionRef = centreRef.collection("storageSections").doc(input.sectionId);
  const movementRef = centreRef.collection("stockMovements").doc();
  await db.runTransaction(async (transaction) => {
    const [centre, section] = await Promise.all([transaction.get(centreRef), transaction.get(sectionRef)]);
    if (!section.exists) throw new ApiError(404, "Storage section not found.", "not_found");
    if (input.weightKg > Number(centre.get("currentStockKg") ?? 0) || input.weightKg > Number(section.get("currentStockKg") ?? 0)) {
      throw new ApiError(409, "Check-out weight exceeds recorded stock.", "insufficient_stock");
    }
    transaction.update(centreRef, {currentStockKg: FieldValue.increment(-input.weightKg), updatedAt: FieldValue.serverTimestamp()});
    transaction.update(sectionRef, {currentStockKg: FieldValue.increment(-input.weightKg), updatedAt: FieldValue.serverTimestamp()});
    transaction.set(movementRef, {...input, type: "checkOut", createdAt: FieldValue.serverTimestamp()});
  });
  response.status(201).json({data: {id: movementRef.id}});
});

router.post("/collection-centres/:id/inspections", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({
    inspectorId: z.string().trim().min(1),
    checks: z.record(z.string(), z.boolean()),
    notes: z.string().trim().max(1000).default(""),
  }).parse(request.body);
  const {reference} = await accessibleCentre(parameter(request.params.id), request.user!.uid, request.user!.role);
  if (input.inspectorId !== request.user!.uid) throw new ApiError(403, "inspectorId must match the authenticated user.", "forbidden");
  const values = Object.values(input.checks);
  const score = values.length === 0 ? 0 : Math.round(values.filter(Boolean).length / values.length * 100);
  const status = score === 100 ? "passed" : score >= 70 ? "actionRequired" : "failed";
  const inspection = await reference.collection("safetyInspections").add({
    ...input,
    score,
    status,
    createdBy: request.user!.uid,
    inspectedAt: FieldValue.serverTimestamp(),
  });
  if (status !== "passed") void publishNotificationEvent({event: "centre_safety_alert", affectedUserIds: [request.user!.uid], data: {centreId: reference.id, inspectionId: inspection.id, score, status}});
  response.status(201).json({data: {id: inspection.id, score, status}});
});

export default router;
