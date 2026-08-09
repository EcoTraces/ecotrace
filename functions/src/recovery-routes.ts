import {Router} from "express";
import {FieldValue} from "firebase-admin/firestore";
import {z} from "zod";
import {authenticate, requireRoles} from "./auth.js";
import {ApiError} from "./errors.js";
import {db} from "./firebase.js";
import {documentJson} from "./firestore-json.js";

const router = Router();
const operators = ["recycler", "environmentalOfficer", "administrator", "superAdministrator"] as const;
const materials = ["copper", "aluminium", "steel", "plastic", "glass", "gold", "silver", "lithium", "cobalt", "circuitBoards"] as const;
const grades = ["premium", "gradeA", "gradeB", "gradeC", "mixed"] as const;

function id(value: string | string[]) { return Array.isArray(value) ? value[0] : value; }
function number(value: unknown) { return Number(value ?? 0); }
function accounted(data: FirebaseFirestore.DocumentData) {
  return number(data.recoveredWeightKg) + number(data.hazardousWeightKg) + number(data.disposedWeightKg) + number(data.processingLossKg);
}
async function lotRef(lotId: string) {
  const ref = db.collection("recoveredMaterialLots").doc(lotId);
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new ApiError(404, "Recovered material lot not found.", "not_found");
  return {ref, snapshot};
}

async function activeCategory(material: typeof materials[number]) {
  const snapshot = await db.collection("materialCategories").doc(material).get();
  if (snapshot.exists && snapshot.get("active") === false) {
    throw new ApiError(409, "This recovered-material category is inactive.", "inactive_material_category");
  }
}

function lifecycle(ref: FirebaseFirestore.DocumentReference, event: string, actorId: string, details: Record<string, unknown> = {}) {
  return ref.collection("lifecycleEvents").doc().set({event, actorId, ...details, createdAt: FieldValue.serverTimestamp()});
}

router.get("/recovery/categories", authenticate, requireRoles(...operators), async (_request, response) => {
  const snapshot = await db.collection("materialCategories").limit(100).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.patch("/recovery/categories/:material", authenticate, requireRoles(...operators), async (request, response) => {
  const material = z.enum(materials).parse(id(request.params.material));
  const input = z.object({defaultUnitValue: z.number().nonnegative(), active: z.boolean()}).parse(request.body);
  await db.collection("materialCategories").doc(material).set({material, ...input, updatedBy: request.user!.uid, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  response.json({data: {id: material, material, ...input}});
});

router.get("/recovery/buyers", authenticate, requireRoles(...operators), async (_request, response) => {
  const snapshot = await db.collection("materialBuyers").limit(500).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.post("/recovery/buyers", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({name: z.string().trim().min(2).max(200), contact: z.string().trim().min(2).max(300), materials: z.array(z.enum(materials)).min(1)}).parse(request.body);
  const ref = await db.collection("materialBuyers").add({...input, active: true, createdBy: request.user!.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.status(201).json({data: {id: ref.id}});
});

router.patch("/recovery/buyers/:id", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({
    name: z.string().trim().min(2).max(200).optional(),
    contact: z.string().trim().min(2).max(300).optional(),
    materials: z.array(z.enum(materials)).min(1).optional(),
    active: z.boolean().optional(),
  }).refine((value) => Object.keys(value).length > 0, "At least one field is required.").parse(request.body);
  const ref = db.collection("materialBuyers").doc(id(request.params.id));
  const current = await ref.get();
  if (!current.exists) throw new ApiError(404, "Material buyer not found.", "not_found");
  await ref.update({...input, updatedBy: request.user!.uid, updatedAt: FieldValue.serverTimestamp()});
  response.json({data: {id: ref.id, ...input}});
});

router.get("/recovery/lots", authenticate, requireRoles(...operators), async (request, response) => {
  let query: FirebaseFirestore.Query = db.collection("recoveredMaterialLots");
  if (typeof request.query.status === "string") query = query.where("status", "==", request.query.status);
  if (typeof request.query.material === "string") query = query.where("material", "==", request.query.material);
  const snapshot = await query.limit(500).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.get("/recovery/lots/:id", authenticate, requireRoles(...operators), async (request, response) => {
  const lot = await lotRef(id(request.params.id));
  response.json({data: documentJson(lot.snapshot.id, lot.snapshot.data()!)});
});

router.post("/recovery/lots", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({recyclingBatchId: z.string().trim().min(1), material: z.enum(materials), weightKg: z.number().positive(), quantity: z.number().int().nonnegative(), qualityGrade: z.enum(grades), storageLocation: z.string().trim().min(1).max(300), unitMarketValue: z.number().nonnegative()}).parse(request.body);
  await activeCategory(input.material);
  const batchRef = db.collection("recyclingBatches").doc(input.recyclingBatchId);
  const ref = db.collection("recoveredMaterialLots").doc();
  await db.runTransaction(async (transaction) => {
    const batch = await transaction.get(batchRef);
    if (!batch.exists) throw new ApiError(404, "Recycling batch not found.", "not_found");
    if (batch.get("completionVerified") === true) throw new ApiError(409, "Completed recycling batches cannot receive new outputs.", "invalid_state");
    if (accounted(batch.data()!) + input.weightKg > number(batch.get("inputWeightKg")) + 0.001) throw new ApiError(409, "Recovered weight exceeds the batch mass balance.", "mass_balance_exceeded");
    transaction.set(ref, {lotCode: `MAT-${ref.id.substring(0, 8).toUpperCase()}`, recyclingBatchId: batch.id, recyclingBatchCode: String(batch.get("batchCode") ?? batch.id), material: input.material, weightKg: input.weightKg, quantity: input.quantity, qualityGrade: input.qualityGrade, storageLocation: input.storageLocation, unitMarketValue: input.unitMarketValue, buyerId: "", status: "stored", saleRevenue: 0, recordedBy: request.user!.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
    transaction.update(batchRef, {recoveredWeightKg: FieldValue.increment(input.weightKg), stage: "materialRecovery", updatedAt: FieldValue.serverTimestamp()});
    transaction.set(batchRef.collection("processRecords").doc(), {type: "materialRecovered", material: input.material, component: "", quantity: input.quantity, weightKg: input.weightKg, notes: `Recovered material lot ${ref.id}`, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  });
  await lifecycle(ref, "materialRecorded", request.user!.uid, {material: input.material, weightKg: input.weightKg, recyclingBatchId: input.recyclingBatchId});
  response.status(201).json({data: {id: ref.id, lotCode: `MAT-${ref.id.substring(0, 8).toUpperCase()}`, estimatedMarketValue: input.weightKg * input.unitMarketValue}});
});

router.patch("/recovery/lots/:id/buyer", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({buyerId: z.string().trim().min(1)}).parse(request.body);
  const [lot, buyer] = await Promise.all([lotRef(id(request.params.id)), db.collection("materialBuyers").doc(input.buyerId).get()]);
  if (!buyer.exists || buyer.get("active") === false) throw new ApiError(404, "Active material buyer not found.", "not_found");
  if (!(buyer.get("materials") ?? []).includes(lot.snapshot.get("material"))) throw new ApiError(409, "Buyer does not accept this material.", "buyer_material_mismatch");
  if (!["stored", "salesReady", "reserved"].includes(String(lot.snapshot.get("status")))) throw new ApiError(409, "Only stored or sales-ready lots can be assigned to a buyer.", "invalid_state");
  await lot.ref.update({buyerId: input.buyerId, status: "reserved", updatedAt: FieldValue.serverTimestamp()});
  await lifecycle(lot.ref, "buyerAssigned", request.user!.uid, {buyerId: input.buyerId, buyerName: String(buyer.get("name") ?? "")});
  response.json({data: {id: lot.ref.id, buyerId: input.buyerId, status: "reserved"}});
});

router.patch("/recovery/lots/:id/sales-ready", authenticate, requireRoles(...operators), async (request, response) => {
  const lot = await lotRef(id(request.params.id));
  if (!["stored", "reserved"].includes(String(lot.snapshot.get("status")))) throw new ApiError(409, "Only stored or reserved lots can be marked sales-ready.", "invalid_state");
  await lot.ref.update({status: "salesReady", salesReadyAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  await lifecycle(lot.ref, "salesReady", request.user!.uid);
  response.json({data: {id: lot.ref.id, status: "salesReady"}});
});

router.get("/recovery/lots/:id/transfers", authenticate, requireRoles(...operators), async (request, response) => {
  const lot = await lotRef(id(request.params.id));
  const snapshot = await lot.ref.collection("transfers").orderBy("createdAt", "desc").limit(300).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.get("/recovery/lots/:id/lifecycle", authenticate, requireRoles(...operators), async (request, response) => {
  const lot = await lotRef(id(request.params.id));
  const snapshot = await lot.ref.collection("lifecycleEvents").orderBy("createdAt", "desc").limit(300).get();
  response.json({data: snapshot.docs.map((doc) => documentJson(doc.id, doc.data()))});
});

router.post("/recovery/lots/:id/transfers", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({destination: z.string().trim().min(2).max(300), carrier: z.string().trim().min(2).max(200), reference: z.string().trim().min(1).max(200)}).parse(request.body);
  const lot = await lotRef(id(request.params.id));
  if (lot.snapshot.get("status") === "sold") throw new ApiError(409, "Sold lots cannot be transferred.", "invalid_state");
  const transfer = lot.ref.collection("transfers").doc(); const write = db.batch();
  write.update(lot.ref, {storageLocation: input.destination, status: "transferred", updatedAt: FieldValue.serverTimestamp()});
  write.set(transfer, {from: String(lot.snapshot.get("storageLocation") ?? ""), to: input.destination, weightKg: number(lot.snapshot.get("weightKg")), carrier: input.carrier, reference: input.reference, actorId: request.user!.uid, createdAt: FieldValue.serverTimestamp()});
  await write.commit();
  await lifecycle(lot.ref, "transferred", request.user!.uid, {destination: input.destination, carrier: input.carrier, reference: input.reference});
  response.status(201).json({data: {id: transfer.id}});
});

router.post("/recovery/lots/:id/sale", authenticate, requireRoles(...operators), async (request, response) => {
  const input = z.object({revenue: z.number().positive(), reference: z.string().trim().min(1).max(200)}).parse(request.body);
  const lot = await lotRef(id(request.params.id));
  if (lot.snapshot.get("status") === "sold") throw new ApiError(409, "This material lot is already sold.", "invalid_state");
  if (!["salesReady", "reserved", "transferred"].includes(String(lot.snapshot.get("status")))) throw new ApiError(409, "Material must be sales-ready, reserved, or transferred before sale.", "invalid_state");
  const buyerId = String(lot.snapshot.get("buyerId") ?? "");
  if (!buyerId) throw new ApiError(409, "Assign an active buyer before recording a sale.", "buyer_required");
  const buyer = await db.collection("materialBuyers").doc(buyerId).get();
  if (!buyer.exists || buyer.get("active") === false) throw new ApiError(409, "The assigned buyer is no longer active.", "inactive_buyer");
  const sale = db.collection("materialSales").doc();
  await db.runTransaction(async (transaction) => {
    const current = await transaction.get(lot.ref);
    if (current.get("status") === "sold") throw new ApiError(409, "This material lot is already sold.", "invalid_state");
    transaction.update(lot.ref, {status: "sold", saleRevenue: input.revenue, saleId: sale.id, saleReference: input.reference, soldBy: request.user!.uid, soldAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
    transaction.set(sale, {lotId: lot.ref.id, lotCode: String(current.get("lotCode") ?? lot.ref.id), buyerId, buyerName: String(buyer.get("name") ?? ""), material: String(current.get("material") ?? ""), weightKg: number(current.get("weightKg")), revenue: input.revenue, reference: input.reference, recordedBy: request.user!.uid, soldAt: FieldValue.serverTimestamp(), createdAt: FieldValue.serverTimestamp()});
  });
  await lifecycle(lot.ref, "sold", request.user!.uid, {saleId: sale.id, buyerId, revenue: input.revenue, reference: input.reference});
  response.json({data: {id: lot.ref.id, saleId: sale.id, status: "sold", saleRevenue: input.revenue}});
});

router.get("/recovery/reports/revenue", authenticate, requireRoles(...operators), async (_request, response) => {
  const [sales, lots] = await Promise.all([
    db.collection("materialSales").limit(2000).get(),
    db.collection("recoveredMaterialLots").where("status", "==", "sold").limit(2000).get(),
  ]);
  const ledgerRevenue = sales.docs.reduce((sum, doc) => sum + number(doc.get("revenue")), 0);
  const lotRevenue = lots.docs.reduce((sum, doc) => sum + number(doc.get("saleRevenue")), 0);
  const lotIds = new Set(sales.docs.map((doc) => String(doc.get("lotId") ?? "")));
  const unreconciledLotIds = lots.docs.filter((doc) => !lotIds.has(doc.id)).map((doc) => doc.id);
  response.json({data: {salesCount: sales.size, soldLotsCount: lots.size, ledgerRevenue, lotRevenue, variance: lotRevenue - ledgerRevenue, reconciled: unreconciledLotIds.length === 0 && Math.abs(lotRevenue - ledgerRevenue) < 0.001, unreconciledLotIds}});
});

router.get("/recovery/reports/summary", authenticate, requireRoles(...operators), async (_request, response) => {
  const [snapshot, batches] = await Promise.all([
    db.collection("recoveredMaterialLots").limit(1000).get(),
    db.collection("recyclingBatches").limit(1000).get(),
  ]);
  const byMaterial: Record<string, {weightKg: number; estimatedValue: number; revenue: number}> = {};
  let totalWeightKg = 0; let estimatedMarketValue = 0; let totalRevenue = 0; let salesReadyWeightKg = 0;
  for (const doc of snapshot.docs) {
    const data = doc.data(); const material = String(data.material ?? "unknown"); const weight = number(data.weightKg); const value = weight * number(data.unitMarketValue); const revenue = number(data.saleRevenue);
    totalWeightKg += weight; estimatedMarketValue += value; totalRevenue += revenue; if (data.status === "salesReady") salesReadyWeightKg += weight;
    byMaterial[material] ??= {weightKg: 0, estimatedValue: 0, revenue: 0}; byMaterial[material].weightKg += weight; byMaterial[material].estimatedValue += value; byMaterial[material].revenue += revenue;
  }
  const recyclingInputWeightKg = batches.docs.reduce((sum, doc) => sum + number(doc.get("inputWeightKg")), 0);
  const recyclingRecoveredWeightKg = batches.docs.reduce((sum, doc) => sum + number(doc.get("recoveredWeightKg")), 0);
  const recoveryEfficiencyPercent = recyclingInputWeightKg ? recyclingRecoveredWeightKg / recyclingInputWeightKg * 100 : 0;
  response.json({data: {totalLots: snapshot.size, totalWeightKg, estimatedMarketValue, totalRevenue, salesReadyWeightKg, recyclingInputWeightKg, recyclingRecoveredWeightKg, recoveryEfficiencyPercent, byMaterial}});
});

export default router;
