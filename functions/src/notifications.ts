import {FieldValue} from "firebase-admin/firestore";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import {db} from "./firebase.js";

type NotificationType = "assignment" | "statusUpdate" | "general";

async function notify(
  userIds: Iterable<string>,
  eventId: string,
  type: NotificationType,
  title: string,
  body: string,
  data: Record<string, unknown> = {},
): Promise<void> {
  const ids = [...new Set(userIds)].filter(Boolean);
  if (ids.length === 0) return;
  const batch = db.batch();
  for (const uid of ids) {
    batch.set(
      db.collection("users").doc(uid).collection("notifications").doc(eventId),
      {
        type,
        title,
        body,
        read: false,
        data,
        createdAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  }
  await batch.commit();
}

async function usersWithRoles(roles: string[]): Promise<string[]> {
  const snapshot = await db.collection("users").where("role", "in", roles).get();
  return snapshot.docs.map((document) => document.id);
}

export const notifyPickupCreated = onDocumentCreated(
  "pickupRequests/{pickupId}",
  async (event) => {
    const pickup = event.data?.data();
    if (!pickup) return;
    const administrators = await usersWithRoles([
      "administrator",
      "superAdministrator",
    ]);
    await notify(
      administrators,
      `pickup-created-${event.params.pickupId}`,
      "general",
      "New pickup request",
      `${pickup.location ?? "A user"} submitted a ${pickup.category ?? "e-waste"} pickup request.`,
      {pickupId: event.params.pickupId},
    );
  },
);

export const notifyPickupStatusChanged = onDocumentUpdated(
  "pickupRequests/{pickupId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.status === after.status) return;
    await notify(
      [String(after.userId ?? "")],
      `pickup-status-${event.params.pickupId}-${after.status}`,
      "statusUpdate",
      "Pickup status updated",
      `Your pickup is now ${String(after.status).replaceAll(/([A-Z])/g, " $1").toLowerCase()}.`,
      {pickupId: event.params.pickupId, status: after.status},
    );
  },
);

export const notifyScheduleCreated = onDocumentCreated(
  "collectionSchedules/{scheduleId}",
  async (event) => {
    const schedule = event.data?.data();
    if (!schedule) return;
    const assignees = [
      String(schedule.driverId ?? ""),
      ...((schedule.collectorIds ?? []) as string[]),
    ];
    await notify(
      assignees,
      `schedule-created-${event.params.scheduleId}`,
      "assignment",
      "New collection assignment",
      `You have been assigned a collection in ${schedule.serviceArea ?? "your service area"}.`,
      {scheduleId: event.params.scheduleId},
    );
  },
);

export const notifyScheduleStatusChanged = onDocumentUpdated(
  "collectionSchedules/{scheduleId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.status === after.status) return;
    const assignees = [
      String(after.driverId ?? ""),
      ...((after.collectorIds ?? []) as string[]),
    ];
    await notify(
      assignees,
      `schedule-status-${event.params.scheduleId}-${after.status}`,
      "statusUpdate",
      "Collection assignment updated",
      `The collection status is now ${after.status}.`,
      {scheduleId: event.params.scheduleId, status: after.status},
    );
  },
);
