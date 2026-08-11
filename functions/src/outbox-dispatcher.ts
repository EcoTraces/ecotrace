import {FieldValue} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {db} from "./firebase.js";

const INVALID_TOKEN_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
  "messaging/invalid-argument",
]);

async function sendPush(
  recipientId: string,
  title: string,
  body: string,
  data: Record<string, unknown>,
): Promise<{status: string}> {
  if (!recipientId) return {status: "failed"};
  const tokens = await db.collection("deviceTokens").where("userId", "==", recipientId).limit(500).get();
  if (tokens.empty) return {status: "no_device"};
  const messaging = getMessaging();
  let sent = 0;
  for (let start = 0; start < tokens.docs.length; start += 500) {
    const chunk = tokens.docs.slice(start, start + 500);
    const result = await messaging.sendEachForMulticast({
      tokens: chunk.map((doc) => String(doc.get("deviceToken"))),
      notification: {title, body},
      data: Object.fromEntries(Object.entries(data).map(([key, value]) => [key, String(value)])),
    });
    sent += result.successCount;
    await Promise.all(
      result.responses.map((response, index) =>
        !response.success && INVALID_TOKEN_CODES.has(String(response.error?.code ?? ""))
          ? chunk[index].ref.delete()
          : Promise.resolve(),
      ),
    );
  }
  return {status: sent > 0 ? "sent" : "failed"};
}

/**
 * Delivers via a generic provider webhook configured through environment
 * variables (<KIND>_PROVIDER_WEBHOOK_URL, <KIND>_PROVIDER_API_KEY). No SMS or
 * email provider is wired to a specific vendor SDK here - operators point
 * these variables at whichever provider (Twilio, SendGrid, a regional SMS
 * gateway, etc.) they choose, behind a small relay matching this contract.
 * Without both variables set, delivery is correctly reported as failed
 * rather than silently left queued.
 */
async function sendViaWebhook(
  kind: "sms" | "email",
  payload: Record<string, unknown>,
): Promise<{status: string; reason: string}> {
  const url = process.env[`${kind.toUpperCase()}_PROVIDER_WEBHOOK_URL`]?.trim();
  const key = process.env[`${kind.toUpperCase()}_PROVIDER_API_KEY`]?.trim();
  if (!url || !key) {
    return {
      status: "failed",
      reason: `No ${kind.toUpperCase()} provider is configured (set ${kind.toUpperCase()}_PROVIDER_WEBHOOK_URL and ${kind.toUpperCase()}_PROVIDER_API_KEY).`,
    };
  }
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {"content-type": "application/json", authorization: `Bearer ${key}`},
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) return {status: "failed", reason: `${kind.toUpperCase()} provider responded with HTTP ${response.status}.`};
    return {status: "sent", reason: ""};
  } catch (error) {
    return {status: "failed", reason: `${kind.toUpperCase()} provider request failed: ${error instanceof Error ? error.message : "unknown error"}.`};
  }
}

/**
 * Attempts real delivery for every queued notificationOutbox entry. Fires on
 * both creation and any update that transitions status back to "queued"
 * (e.g. POST /communication/outbox/:id/retry), and is a no-op for every
 * other status so it never reprocesses its own terminal writes.
 */
export const dispatchOutboxNotification = onDocumentWritten(
  {document: "notificationOutbox/{id}", region: "europe-west1"},
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;
    const data = after.data();
    if (!data || String(data.status ?? "") !== "queued") return;

    const channels = (Array.isArray(data.channels) ? data.channels : [data.channel]).filter(Boolean) as string[];
    const recipientId = String(data.recipientId ?? "");
    const recipientEmail = String(data.recipientEmail ?? data.email ?? "");
    const title = String(data.title ?? "EcoTrace notification");
    const body = String(data.body ?? "");
    const results: Record<string, {status: string; reason?: string}> = {};

    for (const channel of channels) {
      if (channel === "inApp") {
        results.inApp = {status: "delivered"};
      } else if (channel === "push") {
        results.push = await sendPush(recipientId, title, body, (data.data ?? {}) as Record<string, unknown>);
      } else if (channel === "sms") {
        results.sms = await sendViaWebhook("sms", {to: recipientId, message: `${title}: ${body}`});
      } else if (channel === "email") {
        results.email = await sendViaWebhook("email", {to: recipientEmail || recipientId, subject: title, body});
      }
    }

    const statuses = Object.values(results).map((result) => result.status);
    const anySent = statuses.some((status) => status === "sent" || status === "delivered");
    const overallStatus = anySent ? "sent" : "failed";
    await after.ref.update({
      status: overallStatus,
      deliveryResults: results,
      failureReason: Object.values(results).find((result) => result.status === "failed")?.reason ?? "",
      attemptCount: FieldValue.increment(1),
      ...(overallStatus === "sent" ? {deliveredAt: FieldValue.serverTimestamp()} : {}),
      updatedAt: FieldValue.serverTimestamp(),
    });
  },
);
