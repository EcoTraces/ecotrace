type NotificationEvent =
  | "pickup_request_submitted"
  | "pickup_accepted"
  | "collector_assigned"
  | "driver_en_route"
  | "pickup_completed"
  | "recycler_received_item"
  | "recycling_completed"
  | "organization_submitted"
  | "organization_reviewed"
  | "security_alert";

interface EventPayload {
  event: NotificationEvent;
  recipientId?: string;
  affectedUserIds?: string[];
  body?: string;
  data?: Record<string, unknown>;
}

/** Send a best-effort event without making the domain transaction depend on FCM availability. */
export async function publishNotificationEvent(payload: EventPayload): Promise<void> {
  const baseUrl = process.env.NOTIFICATION_API_URL?.trim().replace(/\/$/, "");
  const eventKey = process.env.NOTIFICATION_EVENT_KEY?.trim();
  if (!baseUrl || !eventKey) return;
  try {
    const response = await fetch(`${baseUrl}/notifications/events`, {
      method: "POST",
      headers: {"content-type": "application/json", "x-ecotrace-event-key": eventKey},
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) console.error(`Notification event ${payload.event} failed with HTTP ${response.status}.`);
  } catch (error) {
    console.error(`Notification event ${payload.event} could not be delivered.`, error);
  }
}
