import {Router} from "express";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {z} from "zod";
import {authenticate, requireRoles} from "./auth.js";
import {ApiError} from "./errors.js";
import {db} from "./firebase.js";
import {documentJson} from "./firestore-json.js";

const router = Router();
const supervisors = ["administrator", "superAdministrator"] as const;
const operators = ["administrator", "superAdministrator", "driver"] as const;

function parameter(value: string | string[]): string {
  return Array.isArray(value) ? value[0] : value;
}

function distanceKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const radians = (degrees: number) => degrees * Math.PI / 180;
  const dLat = radians(lat2 - lat1);
  const dLon = radians(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(radians(lat1)) * Math.cos(radians(lat2)) * Math.sin(dLon / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function trafficMultiplier(departure: Date): number {
  const hour = departure.getUTCHours();
  if ((hour >= 7 && hour < 10) || (hour >= 16 && hour < 19)) return 1.35;
  if ((hour >= 6 && hour < 7) || (hour >= 10 && hour < 12) || (hour >= 14 && hour < 16)) return 1.15;
  return 1;
}

function routeLength(points: Array<{latitude: number; longitude: number}>): number {
  let total = 0;
  for (let index = 1; index < points.length; index += 1) {
    total += distanceKm(points[index - 1].latitude, points[index - 1].longitude, points[index].latitude, points[index].longitude);
  }
  return total;
}

async function accessibleRoute(id: string, uid: string, role: string) {
  const reference = db.collection("routePlans").doc(id);
  const snapshot = await reference.get();
  if (!snapshot.exists) throw new ApiError(404, "Route not found.", "not_found");
  const supervisor = supervisors.some((candidate) => candidate === role);
  if (!supervisor && snapshot.get("driverId") !== uid) {
    throw new ApiError(403, "You are not assigned to this route.", "forbidden");
  }
  return {reference, snapshot};
}

router.get("/routes", authenticate, requireRoles(...operators), async (request, response) => {
  let query: FirebaseFirestore.Query = db.collection("routePlans");
  if (request.user!.role === "driver") query = query.where("driverId", "==", request.user!.uid);
  const snapshot = await query.limit(200).get();
  response.json({data: snapshot.docs.map((document) => documentJson(document.id, document.data()))});
});

router.get("/routes/schedulable", authenticate, requireRoles(...supervisors), async (_request, response) => {
  const snapshot = await db.collection("collectionSchedules")
    .where("status", "in", ["planned", "dispatched", "inProgress"])
    .limit(200)
    .get();
  response.json({data: snapshot.docs.map((document) => documentJson(document.id, document.data()))});
});

router.get("/routes/:id", authenticate, requireRoles(...operators), async (request, response) => {
  const {snapshot} = await accessibleRoute(parameter(request.params.id), request.user!.uid, request.user!.role);
  response.json({data: documentJson(snapshot.id, snapshot.data()!)});
});

router.post("/routes/optimize", authenticate, requireRoles(...supervisors), async (request, response) => {
  const input = z.object({
    scheduleId: z.string().trim().min(1),
    departureAt: z.coerce.date().default(new Date()),
    averageSpeedKph: z.number().min(5).max(120).default(30),
    trafficAware: z.boolean().default(true),
    arrivalRadiusMetres: z.number().int().min(25).max(1000).default(150),
    deviationRadiusMetres: z.number().int().min(250).max(10000).default(2000),
  }).parse(request.body);
  const {scheduleId} = input;
  const existing = await db.collection("routePlans").where("scheduleId", "==", scheduleId).limit(1).get();
  if (!existing.empty) {
    const route = existing.docs[0];
    response.json({data: documentJson(route.id, route.data())});
    return;
  }
  const schedule = await db.collection("collectionSchedules").doc(scheduleId).get();
  if (!schedule.exists) throw new ApiError(404, "Collection schedule not found.", "not_found");
  if (!["planned", "dispatched", "inProgress"].includes(String(schedule.get("status")))) {
    throw new ApiError(409, "Only an active collection schedule can be optimized.", "invalid_schedule_state");
  }
  if (!String(schedule.get("driverId") ?? "").trim()) {
    throw new ApiError(409, "Assign a driver before generating the route.", "driver_required");
  }
  const pickupIds = (schedule.get("pickupIds") ?? []) as string[];
  const pickupSnapshots = await db.getAll(...pickupIds.map((id) => db.collection("pickupRequests").doc(id)));
  if (pickupSnapshots.length === 0 || pickupSnapshots.some((pickup) => !pickup.exists)) {
    throw new ApiError(409, "The schedule does not contain available pickups.", "pickups_unavailable");
  }
  const pickups = pickupSnapshots.map((pickup) => ({
    id: pickup.id,
    userId: String(pickup.get("userId") ?? ""),
    address: String(pickup.get("location") ?? ""),
    latitude: Number(pickup.get("latitude")),
    longitude: Number(pickup.get("longitude")),
  }));
  if (pickups.some((pickup) => !Number.isFinite(pickup.latitude) || !Number.isFinite(pickup.longitude))) {
    throw new ApiError(409, "Every pickup must have GPS coordinates before optimization.", "coordinates_required");
  }
  const vehicle = await db.collection("vehicles").doc(String(schedule.get("vehicleId"))).get();
  let latitude = vehicle.exists ? Number(vehicle.get("latitude")) : Number.NaN;
  let longitude = vehicle.exists ? Number(vehicle.get("longitude")) : Number.NaN;
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    latitude = pickups[0].latitude;
    longitude = pickups[0].longitude;
  }
  const startLatitude = latitude;
  const startLongitude = longitude;
  const remaining = [...pickups];
  const ordered: typeof pickups = [];
  while (remaining.length > 0) {
    remaining.sort((a, b) => distanceKm(latitude, longitude, a.latitude, a.longitude) - distanceKm(latitude, longitude, b.latitude, b.longitude));
    const next = remaining.shift()!;
    ordered.push(next);
    latitude = next.latitude;
    longitude = next.longitude;
  }
  let totalDistance = 0;
  latitude = startLatitude;
  longitude = startLongitude;
  const stops = ordered.map((pickup, index) => {
    totalDistance += distanceKm(latitude, longitude, pickup.latitude, pickup.longitude);
    latitude = pickup.latitude;
    longitude = pickup.longitude;
    return {
      pickupId: pickup.id,
      userId: pickup.userId,
      address: pickup.address,
      latitude: pickup.latitude,
      longitude: pickup.longitude,
      sequence: index + 1,
      arrived: false,
    };
  });
  const reference = db.collection("routePlans").doc();
  const baselineMinutes = totalDistance / input.averageSpeedKph * 60;
  const trafficFactor = input.trafficAware ? trafficMultiplier(input.departureAt) : 1;
  const estimatedMinutes = baselineMinutes * trafficFactor;
  const batch = db.batch();
  batch.set(reference, {
    scheduleId,
    driverId: schedule.get("driverId") ?? "",
    vehicleId: schedule.get("vehicleId") ?? "",
    stops,
    distanceKm: totalDistance,
    baselineMinutes,
    estimatedMinutes,
    trafficAware: input.trafficAware,
    trafficFactor,
    trafficModel: input.trafficAware ? "timeOfDay" : "disabled",
    departureAt: Timestamp.fromDate(input.departureAt),
    arrivalRadiusMetres: input.arrivalRadiusMetres,
    deviationRadiusMetres: input.deviationRadiusMetres,
    offlineReady: true,
    status: "planned",
    currentLatitude: startLatitude,
    currentLongitude: startLongitude,
    deviationCount: 0,
    createdBy: request.user!.uid,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  batch.update(schedule.ref, {routePlanId: reference.id, routeDistanceKm: totalDistance, estimatedTravelMinutes: estimatedMinutes, updatedAt: FieldValue.serverTimestamp()});
  await batch.commit();
  const created = await reference.get();
  response.status(201).json({data: documentJson(created.id, created.data()!)});
});

router.patch("/routes/:id/start", authenticate, requireRoles(...operators), async (request, response) => {
  const {reference, snapshot} = await accessibleRoute(parameter(request.params.id), request.user!.uid, request.user!.role);
  if (!["planned", "paused"].includes(String(snapshot.get("status")))) {
    throw new ApiError(409, "Only a planned or paused route can be started.", "invalid_state");
  }
  await reference.update({
    status: "active",
    ...(snapshot.get("status") === "planned"
      ? {startedAt: FieldValue.serverTimestamp()}
      : {resumedAt: FieldValue.serverTimestamp()}),
    updatedAt: FieldValue.serverTimestamp(),
  });
  response.json({data: {id: reference.id, status: "active"}});
});

router.patch("/routes/:id/pause", authenticate, requireRoles(...operators), async (request, response) => {
  const {reference, snapshot} = await accessibleRoute(parameter(request.params.id), request.user!.uid, request.user!.role);
  if (snapshot.get("status") !== "active") {
    throw new ApiError(409, "Only an active route can be paused.", "invalid_state");
  }
  await reference.update({status: "paused", pausedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.json({data: {id: reference.id, status: "paused"}});
});

router.post("/routes/:id/positions", authenticate, requireRoles(...operators), async (request, response) => {
  const position = z.object({
    latitude: z.number().min(-90).max(90),
    longitude: z.number().min(-180).max(180),
    speedMps: z.number().default(0),
    accuracy: z.number().nonnegative().default(0),
    recordedAt: z.coerce.date().optional(),
  }).parse(request.body);
  const {reference, snapshot} = await accessibleRoute(parameter(request.params.id), request.user!.uid, request.user!.role);
  if (snapshot.get("status") !== "active") throw new ApiError(409, "Start the route before sending GPS positions.", "route_not_active");
  const stops = (snapshot.get("stops") ?? []) as Array<Record<string, unknown>>;
  const remaining = stops.filter((stop) => stop.arrived !== true)
    .sort((a, b) => Number(a.sequence ?? 0) - Number(b.sequence ?? 0));
  const nearest = remaining[0];
  const nearestDistance = nearest ? distanceKm(position.latitude, position.longitude, Number(nearest.latitude), Number(nearest.longitude)) : 0;
  const arrivalRadiusKm = Number(snapshot.get("arrivalRadiusMetres") ?? 150) / 1000;
  const deviationRadiusKm = Number(snapshot.get("deviationRadiusMetres") ?? 2000) / 1000;
  const arrived = Boolean(nearest && nearestDistance <= arrivalRadiusKm);
  const previousDeviationAt = snapshot.get("lastDeviationAlertAt")?.toDate?.() as Date | undefined;
  const deviationCooldownElapsed = !previousDeviationAt || Date.now() - previousDeviationAt.getTime() >= 5 * 60 * 1000;
  const deviated = Boolean(nearest && nearestDistance > deviationRadiusKm && deviationCooldownElapsed);
  const batch = db.batch();
  batch.update(reference, {
    currentLatitude: position.latitude,
    currentLongitude: position.longitude,
    lastLocationAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    ...(deviated ? {deviationCount: FieldValue.increment(1), lastDeviationAlertAt: FieldValue.serverTimestamp()} : {}),
    ...(arrived ? {stops: stops.map((stop) => stop.pickupId === nearest.pickupId ? {...stop, arrived: true} : stop)} : {}),
  });
  batch.set(reference.collection("locationHistory").doc(), {...position, recordedAt: position.recordedAt ?? FieldValue.serverTimestamp(), createdAt: FieldValue.serverTimestamp()});
  if (deviated) batch.set(reference.collection("alerts").doc(), {type: "routeDeviation", distanceKm: nearestDistance, createdAt: FieldValue.serverTimestamp()});
  if (arrived) {
    batch.set(reference.collection("events").doc(), {type: "pickupArrival", pickupId: nearest.pickupId, createdAt: FieldValue.serverTimestamp()});
    const userId = String(nearest.userId ?? "");
    if (userId) {
      batch.set(
        db.collection("users").doc(userId).collection("notifications").doc("route-arrival-" + reference.id + "-" + nearest.pickupId),
        {type: "statusUpdate", title: "Collector arriving", body: "Your collection team has arrived.", read: false, data: {routeId: reference.id, pickupId: nearest.pickupId}, createdAt: FieldValue.serverTimestamp()},
        {merge: true},
      );
    }
  }
  await batch.commit();
  response.json({data: {routeId: reference.id, nearestDistanceKm: nearestDistance, arrived, deviated}});
});

router.patch("/routes/:id/complete", authenticate, requireRoles(...operators), async (request, response) => {
  const {reference, snapshot} = await accessibleRoute(parameter(request.params.id), request.user!.uid, request.user!.role);
  if (!['active', 'paused'].includes(String(snapshot.get("status")))) {
    throw new ApiError(409, "Only an active or paused route can be completed.", "invalid_state");
  }
  const locations = await reference.collection("locationHistory").orderBy("recordedAt").limit(5000).get();
  const points = locations.docs.map((document) => ({latitude: Number(document.get("latitude")), longitude: Number(document.get("longitude"))})).filter((point) => Number.isFinite(point.latitude) && Number.isFinite(point.longitude));
  const actualDistanceKm = routeLength(points);
  const startedAt = snapshot.get("startedAt")?.toDate?.() as Date | undefined;
  const actualMinutes = startedAt ? Math.max(0, (Date.now() - startedAt.getTime()) / 60000) : 0;
  const stops = (snapshot.get("stops") ?? []) as Array<Record<string, unknown>>;
  const reachedStops = stops.filter((stop) => stop.arrived === true).length;
  if (reachedStops !== stops.length) {
    throw new ApiError(409, "All route stops must be reached before completion.", "stops_incomplete");
  }
  await reference.update({status: "completed", actualDistanceKm, actualMinutes, reachedStops, completionRate: stops.length === 0 ? 0 : reachedStops / stops.length * 100, completedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.json({data: {id: reference.id, status: "completed", actualDistanceKm, actualMinutes, reachedStops}});
});

router.get("/routes/:id/location-history", authenticate, requireRoles(...operators), async (request, response) => {
  const {reference} = await accessibleRoute(parameter(request.params.id), request.user!.uid, request.user!.role);
  const range = z.object({from: z.coerce.date().optional(), to: z.coerce.date().optional(), limit: z.coerce.number().int().min(1).max(5000).default(1000)}).parse(request.query);
  let query: FirebaseFirestore.Query = reference.collection("locationHistory").orderBy("recordedAt", "desc");
  if (range.from) query = query.where("recordedAt", ">=", Timestamp.fromDate(range.from));
  if (range.to) query = query.where("recordedAt", "<", Timestamp.fromDate(range.to));
  const snapshot = await query.limit(range.limit).get();
  response.json({data: snapshot.docs.map((document) => documentJson(document.id, document.data()))});
});

router.get("/routes/:id/alerts", authenticate, requireRoles(...operators), async (request, response) => {
  const {reference} = await accessibleRoute(parameter(request.params.id), request.user!.uid, request.user!.role);
  const snapshot = await reference.collection("alerts").orderBy("createdAt", "desc").limit(1000).get();
  response.json({data: snapshot.docs.map((document) => documentJson(document.id, document.data()))});
});

router.get("/routes/:id/performance", authenticate, requireRoles(...operators), async (request, response) => {
  const {snapshot} = await accessibleRoute(parameter(request.params.id), request.user!.uid, request.user!.role);
  const data = snapshot.data()!;
  const stops = (data.stops ?? []) as Array<Record<string, unknown>>;
  const reachedStops = stops.filter((stop) => stop.arrived === true).length;
  response.json({data: {
    routeId: snapshot.id, status: data.status, plannedDistanceKm: Number(data.distanceKm ?? 0), actualDistanceKm: Number(data.actualDistanceKm ?? 0),
    estimatedMinutes: Number(data.estimatedMinutes ?? 0), actualMinutes: Number(data.actualMinutes ?? 0), stops: stops.length, reachedStops,
    completionRate: stops.length === 0 ? 0 : reachedStops / stops.length * 100, deviationCount: Number(data.deviationCount ?? 0), trafficFactor: Number(data.trafficFactor ?? 1),
  }});
});

router.get("/routing/reports/performance", authenticate, requireRoles(...supervisors), async (request, response) => {
  const range = z.object({from: z.coerce.date(), to: z.coerce.date()}).parse(request.query);
  const snapshot = await db.collection("routePlans").where("createdAt", ">=", Timestamp.fromDate(range.from)).where("createdAt", "<", Timestamp.fromDate(range.to)).limit(2000).get();
  const routes = snapshot.docs.map((document) => document.data());
  const completed = routes.filter((route) => route.status === "completed");
  const sum = (field: string, source = routes) => source.reduce((total, route) => total + Number(route[field] ?? 0), 0);
  response.json({data: {routes: routes.length, completed: completed.length, active: routes.filter((route) => route.status === "active").length, plannedDistanceKm: sum("distanceKm"), actualDistanceKm: sum("actualDistanceKm", completed), estimatedMinutes: sum("estimatedMinutes"), actualMinutes: sum("actualMinutes", completed), deviations: sum("deviationCount"), averageCompletionRate: completed.length === 0 ? 0 : sum("completionRate", completed) / completed.length}});
});

router.get("/routing/service-coverage", authenticate, requireRoles(...operators), async (_request, response) => {
  const [centres, pickups] = await Promise.all([db.collection("collectionCentres").where("active", "==", true).limit(500).get(), db.collection("pickupRequests").limit(2000).get()]);
  const points = [
    ...centres.docs.map((document) => ({id: document.id, type: "centre", name: String(document.get("name") ?? "Collection centre"), latitude: Number(document.get("latitude")), longitude: Number(document.get("longitude"))})),
    ...pickups.docs.map((document) => ({id: document.id, type: "pickup", name: String(document.get("location") ?? "Pickup"), latitude: Number(document.get("latitude")), longitude: Number(document.get("longitude"))})),
  ].filter((point) => Number.isFinite(point.latitude) && Number.isFinite(point.longitude));
  response.json({data: points});
});

export default router;
