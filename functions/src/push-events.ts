type NotificationEvent =
  | "pickup_request_submitted"
  | "pickup_accepted"
  | "collector_assigned"
  | "driver_en_route"
  | "pickup_completed"
  | "pickup_cancelled"
  | "pickup_rescheduled"
  | "pickup_failed"
  | "pickup_status_updated"
  | "recycler_received_item"
  | "recycling_completed"
  | "organization_submitted"
  | "organization_reviewed"
  | "classification_assessment_submitted"
  | "classification_assessment_reviewed"
  | "centre_staff_assigned"
  | "centre_capacity_alert"
  | "centre_safety_alert"
  | "repair_technician_assigned"
  | "repair_reviewed"
  | "repair_completed"
  | "repair_unrepairable"
  | "repair_disposition_approved"
  | "recycling_hazardous_material_recorded"
  | "hazardous_incident_reported"
  | "hazardous_emergency_response_updated"
  | "hazardous_incident_closed"
  | "hazardous_waste_certified"
  | "logistics_transfer_submitted"
  | "logistics_transfer_reviewed"
  | "logistics_transport_assigned"
  | "logistics_dispatched"
  | "logistics_exception_reported"
  | "logistics_received"
  | "partner_licence_reviewed"
  | "partner_status_changed"
  | "marketplace_delivery_updated"
  | "donation_request_submitted"
  | "donation_status_updated"
  | "reward_points_awarded"
  | "reward_points_expired"
  | "reward_redeemed"
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
