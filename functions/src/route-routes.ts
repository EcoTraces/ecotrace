import {Router} from "express";
import {FieldValue} from "firebase-admin/firestore";
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
  const {scheduleId} = z.object({scheduleId: z.string().trim().min(1)}).parse(request.body);
  const existing = await db.collection("routePlans").where("scheduleId", "==", scheduleId).limit(1).get();
  if (!existing.empty) {
    const route = existing.docs[0];
    response.json({data: documentJson(route.id, route.data())});
    return;
  }
  const schedule = await db.collection("collectionSchedules").doc(scheduleId).get();
  if (!schedule.exists) throw new ApiError(404, "Collection schedule not found.", "not_found");
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
  const estimatedMinutes = totalDistance / 30 * 60;
  const batch = db.batch();
  batch.set(reference, {
    scheduleId,
    driverId: schedule.get("driverId") ?? "",
    vehicleId: schedule.get("vehicleId") ?? "",
    stops,
    distanceKm: totalDistance,
    estimatedMinutes,
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
  const {reference} = await accessibleRoute(parameter(request.params.id), request.user!.uid, request.user!.role);
  await reference.update({status: "active", startedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.json({data: {id: reference.id, status: "active"}});
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
  const remaining = stops.filter((stop) => stop.arrived !== true);
  remaining.sort((a, b) => distanceKm(position.latitude, position.longitude, Number(a.latitude), Number(a.longitude)) - distanceKm(position.latitude, position.longitude, Number(b.latitude), Number(b.longitude)));
  const nearest = remaining[0];
  const nearestDistance = nearest ? distanceKm(position.latitude, position.longitude, Number(nearest.latitude), Number(nearest.longitude)) : 0;
  const arrived = Boolean(nearest && nearestDistance <= 0.15);
  const deviated = nearestDistance > 2;
  const batch = db.batch();
  batch.update(reference, {
    currentLatitude: position.latitude,
    currentLongitude: position.longitude,
    lastLocationAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    ...(deviated ? {deviationCount: FieldValue.increment(1)} : {}),
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
  const {reference} = await accessibleRoute(parameter(request.params.id), request.user!.uid, request.user!.role);
  await reference.update({status: "completed", completedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  response.json({data: {id: reference.id, status: "completed"}});
});

export default router;
