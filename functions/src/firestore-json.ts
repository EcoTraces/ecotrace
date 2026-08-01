import {DocumentReference, GeoPoint, Timestamp} from "firebase-admin/firestore";

export function toJson(value: unknown): unknown {
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (value instanceof GeoPoint) return {latitude: value.latitude, longitude: value.longitude};
  if (value instanceof DocumentReference) return value.path;
  if (Array.isArray(value)) return value.map(toJson);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, toJson(item)]));
  }
  return value;
}

export function documentJson(id: string, data: FirebaseFirestore.DocumentData): Record<string, unknown> {
  return {id, ...(toJson(data) as Record<string, unknown>)};
}
