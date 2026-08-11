import {Router, type Request} from "express";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {z} from "zod";
import {authenticate, requireRoles} from "./auth.js";
import {ApiError} from "./errors.js";
import {db} from "./firebase.js";
import {documentJson} from "./firestore-json.js";

const router = Router();
const users = ["household", "business", "institution", "collector", "driver", "collectionCentreOperator", "repairTechnician", "recycler", "environmentalOfficer", "administrator", "superAdministrator"] as const;
const managers = ["environmentalOfficer", "administrator", "superAdministrator"] as const;
const defaultMaterialCarbonKgPerKg = {copper: 3.5, aluminium: 9.0, steel: 1.8, plastic: 2.5, glass: 0.3, gold: 17.0, silver: 12.0, lithium: 5.0, cobalt: 6.0, circuitBoards: 4.5};
const defaultMaterialEnergyKwhPerKg = {copper: 18.0, aluminium: 45.0, steel: 8.0, plastic: 14.0, glass: 2.0, gold: 80.0, silver: 60.0, lithium: 25.0, cobalt: 30.0, circuitBoards: 22.0};
const defaultFormulas = {reuseCarbonKgPerDevice: 50, reuseEnergyKwhPerDevice: 200, treeCarbonKgPerYear: 21, waterProtectedLitresPerHazardousKg: 1000, materialCarbonKgPerKg: defaultMaterialCarbonKgPerKg, materialEnergyKwhPerKg: defaultMaterialEnergyKwhPerKg};
function number(value: unknown) { return Number(value ?? 0); }
function scope(request: Request) { const requested = typeof request.query.userId === "string" ? request.query.userId : ""; const privileged = ["environmentalOfficer", "administrator", "superAdministrator"].includes(request.user!.role); if (requested && requested !== request.user!.uid && !privileged) throw new ApiError(403, "You cannot access another user's impact.", "forbidden"); return requested || (privileged ? "" : request.user!.uid); }
async function formulas() { const snapshot = await db.collection("systemSettings").doc("environmentalFormulas").get(); return {...defaultFormulas, ...(snapshot.exists ? snapshot.data() : {})}; }
function materialCarbonFactor(formula: Record<string, unknown>, material: string) { const table = (formula.materialCarbonKgPerKg ?? defaultMaterialCarbonKgPerKg) as Record<string, number>; return Number(table[material] ?? 1.0); }
function materialEnergyFactor(formula: Record<string, unknown>, material: string) { const table = (formula.materialEnergyKwhPerKg ?? defaultMaterialEnergyKwhPerKg) as Record<string, number>; return Number(table[material] ?? 5.0); }
function timestampDate(value: unknown): Date | null { return value instanceof Timestamp ? value.toDate() : null; }
function monthKey(date: Date) { return `${date.getUTCFullYear()}-${date.getUTCMonth()}`; }

type MonthlyBucket = {collectedKg: number; recycledKg: number; materialsRecoveredKg: number; hazardousHandledKg: number; reusableDevices: number; carbonAvoidedKg: number; energySavedKwh: number};
function emptyBucket(): MonthlyBucket { return {collectedKg: 0, recycledKg: 0, materialsRecoveredKg: 0, hazardousHandledKg: 0, reusableDevices: 0, carbonAvoidedKg: 0, energySavedKwh: 0}; }

function monthlyTrend(months: number, inventory: FirebaseFirestore.QueryDocumentSnapshot[], recycled: FirebaseFirestore.QueryDocumentSnapshot[], materialLots: FirebaseFirestore.QueryDocumentSnapshot[], hazardousHandled: FirebaseFirestore.QueryDocumentSnapshot[], completedRepairs: FirebaseFirestore.QueryDocumentSnapshot[], formula: Record<string, unknown>) {
  const buckets = new Map<string, MonthlyBucket>();
  function bucket(key: string) { let value = buckets.get(key); if (!value) { value = emptyBucket(); buckets.set(key, value); } return value; }
  for (const doc of inventory) { const date = timestampDate(doc.get("createdAt")); if (!date) continue; bucket(monthKey(date)).collectedKg += number(doc.get("weight")); }
  for (const doc of recycled) { const date = timestampDate(doc.get("completedAt")) ?? timestampDate(doc.get("updatedAt")); if (!date) continue; bucket(monthKey(date)).recycledKg += number(doc.get("inputWeightKg")); }
  for (const doc of materialLots) { const date = timestampDate(doc.get("createdAt")); if (!date) continue; const material = String(doc.get("material") ?? "other"); const weightKg = number(doc.get("weightKg")); const entry = bucket(monthKey(date)); entry.materialsRecoveredKg += weightKg; entry.carbonAvoidedKg += weightKg * materialCarbonFactor(formula, material); entry.energySavedKwh += weightKg * materialEnergyFactor(formula, material); }
  for (const doc of hazardousHandled) { const date = timestampDate(doc.get("certifiedAt")) ?? timestampDate(doc.get("disposalRecordedAt")) ?? timestampDate(doc.get("updatedAt")); if (!date) continue; bucket(monthKey(date)).hazardousHandledKg += number(doc.get("weightKg")); }
  for (const doc of completedRepairs) { const date = timestampDate(doc.get("completedAt")); if (!date) continue; const entry = bucket(monthKey(date)); entry.reusableDevices += 1; entry.carbonAvoidedKg += number(formula.reuseCarbonKgPerDevice); entry.energySavedKwh += number(formula.reuseEnergyKwhPerDevice); }
  const now = new Date();
  const trend = [];
  for (let offset = months - 1; offset >= 0; offset--) {
    const monthDate = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - offset, 1));
    const entry = buckets.get(monthKey(monthDate)) ?? emptyBucket();
    trend.push({month: monthDate.toISOString(), ...entry, landfillDiversionRate: entry.collectedKg > 0 ? Math.min(100, entry.recycledKg / entry.collectedKg * 100) : 0});
  }
  return trend;
}

async function calculate(userId = "") {
  let inventoryQuery: FirebaseFirestore.Query = db.collection("inventoryItems"); if (userId) inventoryQuery = inventoryQuery.where("createdBy", "==", userId);
  const [inventory, batches, materials, hazardous, repairs, formula] = await Promise.all([inventoryQuery.limit(3000).get(), db.collection("recyclingBatches").limit(1000).get(), db.collection("recoveredMaterialLots").limit(2000).get(), db.collection("hazardousWasteRecords").limit(1000).get(), db.collection("repairJobs").where("status", "==", "completed").limit(1000).get(), formulas()]);
  const recycledBatches = batches.docs.filter((doc) => doc.get("completionVerified") === true || doc.get("stage") === "completed");
  const hazardousHandled = hazardous.docs.filter((doc) => ["disposed", "certified"].includes(String(doc.get("status"))));
  const totalCollectedKg = inventory.docs.reduce((sum, doc) => sum + number(doc.get("weight")), 0);
  const totalRecycledKg = recycledBatches.reduce((sum, doc) => sum + number(doc.get("inputWeightKg")), 0);
  const hazardousSafelyHandledKg = hazardousHandled.reduce((sum, doc) => sum + number(doc.get("weightKg")), 0);
  const reusableDevicesRecovered = repairs.docs.length;
  const materialBreakdownKg: Record<string, number> = {};
  let carbonEmissionsAvoidedKg = reusableDevicesRecovered * number(formula.reuseCarbonKgPerDevice);
  let energySavedKwh = reusableDevicesRecovered * number(formula.reuseEnergyKwhPerDevice);
  for (const doc of materials.docs) { const material = String(doc.get("material") ?? "other"); const weightKg = number(doc.get("weightKg")); materialBreakdownKg[material] = (materialBreakdownKg[material] ?? 0) + weightKg; carbonEmissionsAvoidedKg += weightKg * materialCarbonFactor(formula, material); energySavedKwh += weightKg * materialEnergyFactor(formula, material); }
  const materialsRecoveredKg = materials.docs.reduce((sum, doc) => sum + number(doc.get("weightKg")), 0);
  const landfillDiversionRate = totalCollectedKg ? Math.min(100, totalRecycledKg / totalCollectedKg * 100) : 0;
  const treesEquivalent = number(formula.treeCarbonKgPerYear) > 0 ? carbonEmissionsAvoidedKg / number(formula.treeCarbonKgPerYear) : 0;
  const waterPollutionReductionLitres = hazardousSafelyHandledKg * number(formula.waterProtectedLitresPerHazardousKg);
  const monthly = monthlyTrend(12, inventory.docs, recycledBatches, materials.docs, hazardousHandled, repairs.docs, formula);
  return {totalCollectedKg, totalRecycledKg, landfillDiversionRate, materialsRecoveredKg, materialBreakdownKg, carbonEmissionsAvoidedKg, energySavedKwh, hazardousSafelyHandledKg, reusableDevicesRecovered, treesEquivalent, waterPollutionReductionLitres, monthly, formulas: formula};
}

router.get("/impact/summary", authenticate, requireRoles(...users), async (request, response) => { response.json({data: await calculate(scope(request))}); });

router.get("/impact/formulas", authenticate, requireRoles(...users), async (_request, response) => { response.json({data: await formulas()}); });

router.put("/impact/formulas", authenticate, requireRoles(...managers), async (request, response) => { const input = z.object({carbonAvoidedKgPerRecycledKg: z.number().nonnegative(), energySavedKwhPerRecycledKg: z.number().nonnegative(), treesPerTonneCarbon: z.number().nonnegative(), waterProtectedLitresPerHazardousKg: z.number().nonnegative(), landfillDiversionIncludesReuse: z.boolean()}).parse(request.body); await db.collection("systemSettings").doc("environmentalFormulas").set({...input, updatedBy: request.user!.uid, updatedAt: FieldValue.serverTimestamp()}); response.json({data: input}); });

router.post("/impact/snapshots", authenticate, requireRoles(...managers), async (request, response) => { const input = z.object({period: z.string().regex(/^\d{4}-(0[1-9]|1[0-2])$/), notes: z.string().trim().max(1000).default("")}).parse(request.body); const metrics = await calculate(); const ref = db.collection("environmentalImpactSnapshots").doc(input.period); await ref.set({...input, ...metrics, generatedBy: request.user!.uid, generatedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}, {merge: true}); response.status(201).json({data: {id: ref.id, ...metrics}}); });

router.get("/impact/monthly", authenticate, requireRoles(...users), async (request, response) => { const months = z.coerce.number().int().min(1).max(60).default(12).parse(request.query.months); const snapshot = await db.collection("environmentalImpactSnapshots").orderBy("period", "desc").limit(months).get(); response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))}); });

router.get("/impact/comparison", authenticate, requireRoles(...users), async (request, response) => { const from = z.string().regex(/^\d{4}-(0[1-9]|1[0-2])$/).parse(request.query.from); const to = z.string().regex(/^\d{4}-(0[1-9]|1[0-2])$/).parse(request.query.to); const [first, second] = await Promise.all([db.collection("environmentalImpactSnapshots").doc(from).get(), db.collection("environmentalImpactSnapshots").doc(to).get()]); if (!first.exists || !second.exists) throw new ApiError(404, "Both monthly impact snapshots are required.", "not_found"); const fields = ["totalCollectedKg", "totalRecycledKg", "landfillDiversionRate", "materialsRecoveredKg", "carbonEmissionsAvoidedKg", "energySavedKwh", "hazardousSafelyHandledKg", "reusableDevicesRecovered", "treesEquivalent", "waterPollutionReductionLitres"]; const changes: Record<string, {from: number; to: number; change: number; percent: number}> = {}; for (const field of fields) { const a = number(first.get(field)); const b = number(second.get(field)); changes[field] = {from: a, to: b, change: b - a, percent: a ? (b - a) / a * 100 : b ? 100 : 0}; } response.json({data: {from, to, changes}}); });

router.post("/impact/adjustments", authenticate, requireRoles(...managers), async (request, response) => { const input = z.object({metric: z.enum(["totalCollectedKg", "totalRecycledKg", "materialsRecoveredKg", "carbonEmissionsAvoidedKg", "energySavedKwh", "hazardousSafelyHandledKg", "reusableDevicesRecovered", "treesEquivalent", "waterPollutionReductionLitres"]), value: z.number(), reason: z.string().trim().min(2).max(1000), referenceId: z.string().trim().min(1).max(200)}).parse(request.body); const ref = await db.collection("environmentalImpactAdjustments").add({...input, approvedBy: request.user!.uid, createdAt: FieldValue.serverTimestamp()}); response.status(201).json({data: {id: ref.id}}); });

router.get("/impact/report", authenticate, requireRoles(...users), async (request, response) => { const metrics = await calculate(scope(request)); const snapshots = await db.collection("environmentalImpactSnapshots").orderBy("period", "desc").limit(12).get(); response.json({data: {reportNumber: `ENV-${new Date().toISOString().slice(0, 10).replaceAll("-", "")}`, generatedAt: new Date().toISOString(), generatedForUserId: scope(request) || "platform", metrics, monthlyTrend: snapshots.docs.map((doc) => documentJson(doc.id, doc.data()))}}); });

export default router;
