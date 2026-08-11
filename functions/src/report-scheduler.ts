import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {db} from "./firebase.js";

function csvEscape(value: unknown): string {
  const text = value === null || value === undefined ? "" : String(value);
  return /[",\n]/.test(text) ? `"${text.replace(/"/g, "\"\"")}"` : text;
}

function toCsv(fields: string[], rows: Record<string, unknown>[]): string {
  const columns = ["id", ...fields];
  const header = columns.map(csvEscape).join(",");
  const body = rows.map((row) => columns.map((column) => csvEscape(row[column])).join(",")).join("\n");
  return rows.length ? `${header}\n${body}` : header;
}

function periodWindow(frequency: string, reference: Date): {from: Date; to: Date} {
  const from = new Date(reference);
  if (frequency === "daily") from.setUTCDate(from.getUTCDate() - 1);
  else if (frequency === "weekly") from.setUTCDate(from.getUTCDate() - 7);
  else if (frequency === "monthly") from.setUTCMonth(from.getUTCMonth() - 1);
  else from.setUTCMonth(from.getUTCMonth() - 3);
  return {from, to: reference};
}

function nextRun(frequency: string, previous: Date): Date {
  const next = new Date(previous);
  if (frequency === "daily") next.setUTCDate(next.getUTCDate() + 1);
  else if (frequency === "weekly") next.setUTCDate(next.getUTCDate() + 7);
  else if (frequency === "monthly") next.setUTCMonth(next.getUTCMonth() + 1);
  else next.setUTCMonth(next.getUTCMonth() + 3);
  return next;
}

/**
 * Generates due scheduled reports as CSV and queues delivery through the
 * same notificationOutbox collection every other notification uses. Actual
 * email/SMS transmission still requires a production provider to be
 * configured; this function only produces the report and queues it, it does
 * not contact any delivery provider itself.
 */
export const deliverScheduledReports = onSchedule(
  {schedule: "every 60 minutes", region: "europe-west1"},
  async () => {
    const now = new Date();
    const due = await db
      .collection("reportSchedules")
      .where("active", "==", true)
      .where("nextRunAt", "<=", Timestamp.fromDate(now))
      .limit(50)
      .get();

    for (const scheduleDoc of due.docs) {
      const schedule = scheduleDoc.data();
      const definitionRef = db.collection("reportDefinitions").doc(String(schedule.definitionId ?? ""));
      const definitionSnapshot = await definitionRef.get();
      if (!definitionSnapshot.exists) {
        await scheduleDoc.ref.update({active: false, lastRunError: "Report definition no longer exists.", updatedAt: FieldValue.serverTimestamp()});
        continue;
      }
      const definition = definitionSnapshot.data()!;
      const frequency = String(schedule.frequency ?? "monthly");
      const {from, to} = periodWindow(frequency, now);

      let query: FirebaseFirestore.Query = db
        .collection(String(definition.sourceCollection))
        .where("createdAt", ">=", Timestamp.fromDate(from))
        .where("createdAt", "<=", Timestamp.fromDate(to));
      for (const filter of (definition.filters ?? []) as Array<{field: string; operator: FirebaseFirestore.WhereFilterOp; value: unknown}>) {
        query = query.where(filter.field, filter.operator, filter.value);
      }
      const snapshot = await query.limit(2000).get();
      const fields = (definition.fields ?? []) as string[];
      const rows = snapshot.docs.map((doc) => {
        const row: Record<string, unknown> = {id: doc.id};
        for (const field of fields) row[field] = doc.get(field) ?? null;
        return row;
      });
      const csvContent = toCsv(fields, rows);

      const generated = db.collection("generatedReports").doc();
      await generated.set({
        definitionId: definitionRef.id,
        scheduleId: scheduleDoc.id,
        name: schedule.name ?? definition.name,
        type: definition.type,
        from: Timestamp.fromDate(from),
        to: Timestamp.fromDate(to),
        requestedFormat: schedule.format ?? "csv",
        deliveredFormat: "csv",
        recordCount: rows.length,
        status: "completed",
        csvContent,
        requestedBy: "scheduler",
        createdAt: FieldValue.serverTimestamp(),
      });

      const recipients = (schedule.recipientEmails ?? []) as string[];
      const batch = db.batch();
      for (const email of recipients) {
        const outbox = db.collection("notificationOutbox").doc();
        batch.set(outbox, {
          recipientId: "",
          recipientEmail: email,
          category: "general",
          channels: ["email"],
          templateId: "",
          title: `Scheduled report ready: ${schedule.name ?? definition.name}`,
          body: `Your ${frequency} report "${schedule.name ?? definition.name}" is ready with ${rows.length} record(s).`,
          data: {reportId: generated.id, definitionId: definitionRef.id},
          status: "queued",
          priority: "normal",
          createdBy: "scheduler",
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      const previousNextRunAt = schedule.nextRunAt as Timestamp | undefined;
      batch.update(scheduleDoc.ref, {
        nextRunAt: Timestamp.fromDate(nextRun(frequency, previousNextRunAt?.toDate() ?? now)),
        lastRunAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      await batch.commit();
    }
  },
);
