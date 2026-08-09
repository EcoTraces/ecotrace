import {Router} from "express";
import {z} from "zod";
import {authenticate, requireRoles} from "./auth.js";
import {ApiError} from "./errors.js";
import {db} from "./firebase.js";
import {documentJson} from "./firestore-json.js";

const router = Router();
const operators = [
  "administrator", "superAdministrator", "collector", "collectionCentreOperator",
  "repairTechnician", "recycler", "environmentalOfficer",
] as const;
const reviewers = ["administrator", "superAdministrator", "environmentalOfficer"] as const;
const categories = [
  "mobilePhones", "laptops", "desktopComputers", "televisions", "printers",
  "batteries", "accessories", "networkingEquipment", "householdAppliances",
  "industrialElectronics",
] as const;
const conditions = [
  "working", "repairable", "reusable", "refurbishable", "recyclable",
  "hazardous", "nonRecoverable",
] as const;
const recommendations = [
  "reuse", "repair", "refurbish", "recycle", "hazardousDisposal", "finalDisposal",
] as const;

const suggestionSchema = z.object({
  category: z.enum(categories),
  materials: z.record(z.string(), z.number().min(0).max(100)),
  hazards: z.array(z.string().trim().min(1).max(200)).max(30),
  assessedCondition: z.enum(conditions),
  reusability: z.number().int().min(0).max(100),
  repairability: z.number().int().min(0).max(100),
  recommendation: z.enum(recommendations),
  recoveryValue: z.number().nonnegative(),
  confidence: z.number().min(0).max(1),
  notes: z.string().trim().max(2000).default(""),
});

function id(value: string | string[]) {
  return Array.isArray(value) ? value[0] : value;
}

function categoryFor(text: string): (typeof categories)[number] {
  if (/phone|mobile|smartphone/.test(text)) return "mobilePhones";
  if (/laptop|notebook|macbook/.test(text)) return "laptops";
  if (/desktop|computer|cpu|workstation/.test(text)) return "desktopComputers";
  if (/television|\btv\b|monitor/.test(text)) return "televisions";
  if (/printer|scanner|copier/.test(text)) return "printers";
  if (/battery|ups|power bank/.test(text)) return "batteries";
  if (/router|switch|modem|network/.test(text)) return "networkingEquipment";
  if (/fridge|refrigerator|washer|microwave|appliance/.test(text)) return "householdAppliances";
  if (/industrial|generator|control panel|inverter/.test(text)) return "industrialElectronics";
  return "accessories";
}

function heuristicSuggestion(item: FirebaseFirestore.DocumentData) {
  const text = `${item.deviceType ?? ""} ${item.brand ?? ""} ${item.model ?? ""}`.toLowerCase();
  const category = categoryFor(text);
  const hazardous = item.condition === "hazardous" || category === "batteries";
  const materialProfiles: Record<string, Record<string, number>> = {
    mobilePhones: {metals: 35, plastics: 25, glass: 20, circuitBoards: 15, battery: 5},
    laptops: {metals: 40, plastics: 25, glass: 10, circuitBoards: 20, battery: 5},
    desktopComputers: {metals: 55, plastics: 20, circuitBoards: 20, other: 5},
    televisions: {glass: 45, plastics: 30, metals: 20, circuitBoards: 5},
    printers: {plastics: 55, metals: 30, circuitBoards: 10, other: 5},
    batteries: {batteryChemicals: 70, metals: 25, plastics: 5},
    networkingEquipment: {plastics: 40, metals: 25, circuitBoards: 30, other: 5},
    householdAppliances: {metals: 65, plastics: 25, glass: 5, other: 5},
    industrialElectronics: {metals: 55, circuitBoards: 30, plastics: 10, other: 5},
    accessories: {plastics: 45, metals: 30, circuitBoards: 15, other: 10},
  };
  const condition = String(item.condition ?? "recyclable") as (typeof conditions)[number];
  const reusability = ["working", "reusable"].includes(condition) ? 85 :
    ["repairable", "refurbishable"].includes(condition) ? 55 : 10;
  const repairability = condition === "repairable" ? 80 :
    condition === "refurbishable" ? 70 : condition === "working" ? 90 : 20;
  const recommendation = hazardous ? "hazardousDisposal" :
    condition === "working" || condition === "reusable" ? "reuse" :
    condition === "repairable" ? "repair" :
    condition === "refurbishable" ? "refurbish" :
    condition === "nonRecoverable" ? "finalDisposal" : "recycle";
  return {
    category,
    materials: materialProfiles[category],
    hazards: hazardous ? [
      category === "batteries" ? "Battery electrolyte and heavy-metal risk" :
        "Potential hazardous component; isolate pending inspection",
    ] : [],
    assessedCondition: condition,
    reusability,
    repairability,
    recommendation,
    recoveryValue: Math.round(Number(item.weight ?? 0) *
      (category === "mobilePhones" || category === "laptops" ? 35 : 12) * 100) / 100,
    confidence: Array.isArray(item.imageUrls) && item.imageUrls.length > 0 ? 0.72 : 0.55,
    notes: "Assisted result must be verified by a qualified assessor.",
  };
}

async function externalSuggestion(item: FirebaseFirestore.DocumentData) {
  const url = process.env.CLASSIFICATION_AI_URL?.trim();
  if (!url) return null;
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(process.env.CLASSIFICATION_AI_KEY ?
          {authorization: `Bearer ${process.env.CLASSIFICATION_AI_KEY}`} : {}),
      },
      body: JSON.stringify({
        task: "ewaste-classification",
        categories,
        conditions,
        recommendations,
        item: {
          deviceType: item.deviceType,
          brand: item.brand,
          model: item.model,
          condition: item.condition,
          weightKg: item.weight,
          imageUrls: item.imageUrls ?? [],
        },
      }),
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) return null;
    const body = await response.json() as {data?: unknown};
    return suggestionSchema.parse(body.data ?? body);
  } catch (error) {
    console.error("External classification provider failed; using heuristic fallback.", error);
    return null;
  }
}

router.post(
  "/inventory/items/:id/classification-assist",
  authenticate,
  requireRoles(...operators),
  async (request, response) => {
    const itemRef = db.collection("inventoryItems").doc(id(request.params.id));
    const item = await itemRef.get();
    if (!item.exists) throw new ApiError(404, "Inventory item not found.", "not_found");
    const external = await externalSuggestion(item.data()!);
    const suggestion = external ?? heuristicSuggestion(item.data()!);
    response.json({data: {
      ...suggestion,
      engine: external ? "external-ai" : "ecotrace-heuristic-v1",
      requiresHumanReview: true,
      generatedAt: new Date().toISOString(),
    }});
  },
);

router.get(
  "/classification/review-queue",
  authenticate,
  requireRoles(...reviewers),
  async (request, response) => {
    const limit = z.coerce.number().int().min(1).max(200).default(100).parse(request.query.limit);
    const snapshot = await db.collectionGroup("assessments")
      .where("status", "==", "pendingSupervisor").limit(limit).get();
    response.json({data: snapshot.docs.map((document) => ({
      ...documentJson(document.id, document.data()),
      itemId: document.ref.parent.parent?.id ?? "",
    }))});
  },
);

router.get(
  "/classification/summary",
  authenticate,
  requireRoles(...operators),
  async (_request, response) => {
    const snapshot = await db.collectionGroup("assessments").limit(5000).get();
    const byStatus: Record<string, number> = {};
    const byCategory: Record<string, number> = {};
    const byRecommendation: Record<string, number> = {};
    let confidenceTotal = 0;
    for (const assessment of snapshot.docs) {
      const status = String(assessment.get("status") ?? "unknown");
      const category = String(assessment.get("category") ?? "unknown");
      const recommendation = String(assessment.get("recommendation") ?? "unknown");
      byStatus[status] = (byStatus[status] ?? 0) + 1;
      byCategory[category] = (byCategory[category] ?? 0) + 1;
      byRecommendation[recommendation] = (byRecommendation[recommendation] ?? 0) + 1;
      confidenceTotal += Number(assessment.get("confidence") ?? 0);
    }
    response.json({data: {
      totalAssessments: snapshot.size,
      averageConfidence: snapshot.size ? confidenceTotal / snapshot.size : 0,
      byStatus,
      byCategory,
      byRecommendation,
    }});
  },
);

export default router;
