import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {db} from "./firebase.js";
import {publishNotificationEvent} from "./push-events.js";

async function administratorIds(): Promise<string[]> {
  const snapshot = await db
    .collection("users")
    .where("role", "in", ["administrator", "superAdministrator"])
    .limit(200)
    .get();
  return snapshot.docs.map((doc) => doc.id);
}

/** Notify pickup owners whose dispatch schedule starts within the next 24 hours. */
async function sendPickupReminders(): Promise<void> {
  const now = Date.now();
  const horizon = Timestamp.fromMillis(now + 24 * 60 * 60 * 1000);
  const due = await db
    .collection("collectionSchedules")
    .where("status", "==", "planned")
    .where("scheduledAt", "<=", horizon)
    .where("scheduledAt", ">=", Timestamp.fromMillis(now))
    .limit(200)
    .get();

  for (const scheduleDoc of due.docs) {
    if (scheduleDoc.get("reminderSentAt")) continue;
    const pickupIds = (scheduleDoc.get("pickupIds") ?? []) as string[];
    if (pickupIds.length === 0) {
      await scheduleDoc.ref.update({reminderSentAt: FieldValue.serverTimestamp()});
      continue;
    }
    const pickups = await db.getAll(...pickupIds.map((pickupId) => db.collection("pickupRequests").doc(pickupId)));
    const userIds = [...new Set(pickups.filter((doc) => doc.exists).map((doc) => String(doc.get("userId") ?? "")).filter(Boolean))];
    const scheduledAt = (scheduleDoc.get("scheduledAt") as Timestamp).toDate();
    if (userIds.length > 0) {
      await publishNotificationEvent({
        event: "pickup_reminder",
        affectedUserIds: userIds,
        body: `Your e-waste pickup is scheduled for ${scheduledAt.toLocaleString("en-GB", {dateStyle: "medium", timeStyle: "short", timeZone: "UTC"})} UTC.`,
        data: {scheduleId: scheduleDoc.id},
      });
    }
    await scheduleDoc.ref.update({reminderSentAt: FieldValue.serverTimestamp()});
  }
}

/** Notify administrators and the assigned driver about fleet documents/maintenance due within 30 days. */
async function sendFleetReminders(): Promise<void> {
  const cutoff = Date.now() + 30 * 24 * 60 * 60 * 1000;
  const vehicles = await db.collection("vehicles").limit(1000).get();
  const admins = await administratorIds();
  const fields: Array<{field: "insuranceExpiry" | "licenceExpiry" | "nextMaintenanceAt"; event: "fleet_document_expiring" | "fleet_maintenance_due"; label: string}> = [
    {field: "insuranceExpiry", event: "fleet_document_expiring", label: "Insurance"},
    {field: "licenceExpiry", event: "fleet_document_expiring", label: "Licence"},
    {field: "nextMaintenanceAt", event: "fleet_maintenance_due", label: "Maintenance"},
  ];

  for (const vehicle of vehicles.docs) {
    const data = vehicle.data();
    const remindedFields = (data.remindedFields ?? {}) as Record<string, string>;
    const updates: Record<string, string> = {};
    for (const {field, event, label} of fields) {
      const due = data[field]?.toDate?.() as Date | undefined;
      if (!due || due.getTime() > cutoff) continue;
      const dueIso = due.toISOString();
      if (remindedFields[field] === dueIso) continue;
      const recipients = [...new Set([...admins, String(data.driverId ?? "")].filter(Boolean))];
      await publishNotificationEvent({
        event,
        affectedUserIds: recipients,
        body: `${label} for vehicle ${data.registrationNumber} is ${due.getTime() < Date.now() ? "overdue" : "due soon"} (${due.toISOString().slice(0, 10)}).`,
        data: {vehicleId: vehicle.id, field},
      });
      updates[field] = dueIso;
    }
    if (Object.keys(updates).length > 0) {
      await vehicle.ref.update({remindedFields: {...remindedFields, ...updates}, updatedAt: FieldValue.serverTimestamp()});
    }
  }
}

/** Notify administrators about compliance documents/licences/certificates expiring within 90 days. */
async function sendComplianceReminders(): Promise<void> {
  const cutoff = Date.now() + 90 * 24 * 60 * 60 * 1000;
  const admins = await administratorIds();
  if (admins.length === 0) return;
  const collections = ["complianceDocuments", "complianceLicences", "recyclerCertifications", "environmentalCertificates"];
  for (const collection of collections) {
    const snapshot = await db.collection(collection).limit(500).get();
    for (const doc of snapshot.docs) {
      const due = doc.get("expiresAt")?.toDate?.() as Date | undefined;
      if (!due || due.getTime() > cutoff) continue;
      const dueIso = due.toISOString();
      if (doc.get("expiryReminderFor") === dueIso) continue;
      const title = String(doc.get("title") ?? doc.get("licenseNumber") ?? doc.get("certificateNumber") ?? doc.id);
      await publishNotificationEvent({
        event: "compliance_document_expiring",
        affectedUserIds: admins,
        body: `${title} is ${due.getTime() < Date.now() ? "overdue" : "expiring soon"} (${due.toISOString().slice(0, 10)}).`,
        data: {collection, documentId: doc.id},
      });
      await doc.ref.update({expiryReminderFor: dueIso, expiryReminderSentAt: FieldValue.serverTimestamp()});
    }
  }
}

/** Notify the owner and administrators about secure vault documents (licences, certificates, contracts, etc.) expiring within 60 days. */
async function sendDocumentReminders(): Promise<void> {
  const cutoff = Date.now() + 60 * 24 * 60 * 60 * 1000;
  const admins = await administratorIds();
  const snapshot = await db.collection("documents").limit(500).get();
  for (const doc of snapshot.docs) {
    const due = doc.get("expiresAt")?.toDate?.() as Date | undefined;
    if (!due || due.getTime() > cutoff) continue;
    const dueIso = due.toISOString();
    if (doc.get("expiryReminderFor") === dueIso) continue;
    const ownerId = String(doc.get("ownerId") ?? "");
    const recipients = [...new Set([...admins, ownerId].filter(Boolean))];
    if (recipients.length === 0) continue;
    await publishNotificationEvent({
      event: "compliance_document_expiring",
      affectedUserIds: recipients,
      body: `${String(doc.get("title") ?? doc.id)} is ${due.getTime() < Date.now() ? "overdue" : "expiring soon"} (${due.toISOString().slice(0, 10)}).`,
      data: {documentId: doc.id},
    });
    await doc.ref.update({expiryReminderFor: dueIso, expiryReminderSentAt: FieldValue.serverTimestamp()});
  }
}

export const sendScheduledReminders = onSchedule(
  {schedule: "every 60 minutes", region: "europe-west1"},
  async () => {
    await sendPickupReminders();
    await sendFleetReminders();
    await sendComplianceReminders();
    await sendDocumentReminders();
  },
);
