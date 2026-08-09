"""Reusable Firestore-backed Firebase Cloud Messaging service."""

import logging
from collections.abc import Iterable
from dataclasses import dataclass
from typing import Any

from firebase_admin import exceptions, messaging
from google.api_core.exceptions import GoogleAPIError
from google.cloud import firestore

from app.notifications.firebase import get_db
from app.notifications.schemas import EventName, NotificationType, SendResult
from app.notifications.utils import stringify_data, token_document_id

logger = logging.getLogger(__name__)

INVALID_TOKEN_CODES = {
    "registration-token-not-registered",
    "invalid-registration-token",
    "invalid-argument",
    "sender-id-mismatch",
}


@dataclass(frozen=True, slots=True)
class EventTemplate:
    type: NotificationType
    title: str
    body: str
    administrators: bool = False


EVENTS: dict[EventName, EventTemplate] = {
    EventName.PICKUP_REQUEST_SUBMITTED: EventTemplate(NotificationType.PICKUP_REQUEST, "New Pickup Request", "A new e-waste pickup request has been submitted.", True),
    EventName.PICKUP_ACCEPTED: EventTemplate(NotificationType.PICKUP_ACCEPTED, "Pickup Accepted", "Your pickup request has been accepted."),
    EventName.COLLECTOR_ASSIGNED: EventTemplate(NotificationType.COLLECTOR_ASSIGNED, "Collector Assigned", "A collector has been assigned to your pickup."),
    EventName.DRIVER_EN_ROUTE: EventTemplate(NotificationType.DRIVER_EN_ROUTE, "Driver On The Way", "Your assigned driver is on the way."),
    EventName.PICKUP_COMPLETED: EventTemplate(NotificationType.PICKUP_COMPLETED, "Pickup Completed", "Your electronic waste has been successfully collected."),
    EventName.PICKUP_CANCELLED: EventTemplate(NotificationType.PICKUP_REQUEST, "Collection Cancelled", "A scheduled collection has been cancelled."),
    EventName.PICKUP_RESCHEDULED: EventTemplate(NotificationType.PICKUP_REQUEST, "Collection Rescheduled", "Your collection assignment has been moved to a new date."),
    EventName.PICKUP_FAILED: EventTemplate(NotificationType.PICKUP_REQUEST, "Collection Exception", "A collection could not be completed and requires attention."),
    EventName.PICKUP_STATUS_UPDATED: EventTemplate(NotificationType.PICKUP_REQUEST, "Pickup Status Updated", "The status of a pickup request has changed."),
    EventName.RECYCLER_RECEIVED_ITEM: EventTemplate(NotificationType.RECYCLER_RECEIVED, "Recycler Received Item", "Your electronic waste has arrived at the recycling facility."),
    EventName.RECYCLING_COMPLETED: EventTemplate(NotificationType.RECYCLING_COMPLETED, "Recycling Completed", "Your electronic waste has been successfully recycled."),
    EventName.SECURITY_ALERT: EventTemplate(NotificationType.SECURITY_ALERT, "Security Alert", "A security-related change was detected on your EcoTrace account."),
    EventName.CLASSIFICATION_ASSESSMENT_SUBMITTED: EventTemplate(NotificationType.CLASSIFICATION, "Classification Review Required", "A new e-waste classification assessment is awaiting supervisor review.", True),
    EventName.CLASSIFICATION_ASSESSMENT_REVIEWED: EventTemplate(NotificationType.CLASSIFICATION, "Classification Reviewed", "Your e-waste classification assessment has been reviewed."),
}


class NotificationService:
    """Send FCM messages and maintain auditable notification history."""

    def __init__(self, database: firestore.Client | None = None) -> None:
        self.db = database or get_db()

    def register_token(self, user_id: str, device_token: str, platform: str) -> str:
        """Create or update a device registration and return its identifier."""
        identifier = token_document_id(device_token)
        self.db.collection("deviceTokens").document(identifier).set(
            {"userId": user_id, "deviceToken": device_token, "platform": platform, "updatedAt": firestore.SERVER_TIMESTAMP},
            merge=True,
        )
        return identifier

    def remove_token(self, user_id: str, device_token: str) -> bool:
        """Remove a token owned by the authenticated user."""
        reference = self.db.collection("deviceTokens").document(token_document_id(device_token))
        snapshot = reference.get()
        if not snapshot.exists or snapshot.get("userId") != user_id:
            return False
        reference.delete()
        return True

    def send_to_user(
        self,
        user_id: str,
        title: str,
        body: str,
        notification_type: NotificationType,
        data: dict[str, Any] | None = None,
    ) -> SendResult:
        """Send to all active registrations belonging to one user."""
        return self.send_to_multiple_users([user_id], title, body, notification_type, data)

    def send_to_multiple_users(
        self,
        user_ids: Iterable[str],
        title: str,
        body: str,
        notification_type: NotificationType,
        data: dict[str, Any] | None = None,
    ) -> SendResult:
        """Send in chunks, remove invalid tokens, and persist per-user history."""
        recipients = list(dict.fromkeys(uid for uid in user_ids if uid))
        payload = data or {}
        notification_ids: list[str] = []
        sent = failed = removed = 0
        for user_id in recipients:
            tokens = self._tokens_for_user(user_id)
            user_sent = user_failed = 0
            for start in range(0, len(tokens), 500):
                chunk = tokens[start : start + 500]
                try:
                    result = messaging.send_each_for_multicast(
                        messaging.MulticastMessage(
                            tokens=[token for _, token in chunk],
                            notification=messaging.Notification(title=title, body=body),
                            data=stringify_data({**payload, "type": notification_type.value}),
                            android=messaging.AndroidConfig(priority="high", notification=messaging.AndroidNotification(channel_id="ecotrace_updates", sound="default")),
                            apns=messaging.APNSConfig(payload=messaging.APNSPayload(aps=messaging.Aps(sound="default", badge=1))),
                            webpush=messaging.WebpushConfig(notification=messaging.WebpushNotification(title=title, body=body)),
                        )
                    )
                    user_sent += result.success_count
                    user_failed += result.failure_count
                    for index, response in enumerate(result.responses):
                        if not response.success and self._invalid_token(response.exception):
                            self.db.collection("deviceTokens").document(chunk[index][0]).delete()
                            removed += 1
                        elif not response.success:
                            logger.warning("FCM delivery failed user=%s error=%s", user_id, response.exception)
                except (exceptions.FirebaseError, GoogleAPIError, OSError) as exc:
                    user_failed += len(chunk)
                    logger.exception("FCM network/Firebase failure user=%s", user_id, exc_info=exc)
            sent += user_sent
            failed += user_failed
            status_value = "sent" if user_sent else ("no_device" if not tokens else "failed")
            notification_ids.append(self._store_history(user_id, title, body, notification_type, status_value, payload))
        return SendResult(notificationIds=notification_ids, recipients=len(recipients), sent=sent, failed=failed, removedTokens=removed)

    def send_to_topic(
        self,
        topic: str,
        title: str,
        body: str,
        notification_type: NotificationType,
        data: dict[str, Any] | None = None,
    ) -> str:
        """Send a push notification to an FCM topic."""
        return messaging.send(
            messaging.Message(
                topic=topic,
                notification=messaging.Notification(title=title, body=body),
                data=stringify_data({**(data or {}), "type": notification_type.value}),
            )
        )

    def send_announcement(self, title: str, body: str, data: dict[str, Any] | None = None, topic: str | None = None) -> SendResult:
        """Send an announcement and create history for every active user."""
        users = [document.id for document in self.db.collection("users").where("accountStatus", "==", "active").stream()]
        result = self.send_to_multiple_users(users, title, body, NotificationType.ANNOUNCEMENT, data)
        if topic:
            try:
                self.send_to_topic(topic, title, body, NotificationType.ANNOUNCEMENT, data)
            except (exceptions.FirebaseError, GoogleAPIError, OSError) as exc:
                logger.exception("FCM topic delivery failed topic=%s", topic, exc_info=exc)
        return result

    def notify_event(
        self,
        event: EventName,
        recipient_id: str | None = None,
        affected_user_ids: Iterable[str] = (),
        body: str | None = None,
        data: dict[str, Any] | None = None,
    ) -> SendResult:
        """Resolve a domain event to its required recipients and template."""
        template = EVENTS[event]
        if template.administrators:
            recipients = self.users_with_roles(["administrator", "superAdministrator"])
        else:
            recipients = list(affected_user_ids) or ([recipient_id] if recipient_id else [])
        return self.send_to_multiple_users(recipients, template.title, body or template.body, template.type, data)

    def users_with_roles(self, roles: list[str]) -> list[str]:
        """Resolve user identifiers for one or more roles."""
        users: list[str] = []
        for start in range(0, len(roles), 10):
            users.extend(document.id for document in self.db.collection("users").where("role", "in", roles[start : start + 10]).stream())
        return list(dict.fromkeys(users))

    def list_history(self, user_id: str, limit: int = 100) -> list[dict[str, Any]]:
        """Return newest notification records for one user."""
        query = self.db.collection("notifications").where("recipientId", "==", user_id).limit(limit)
        records = []
        for document in query.stream():
            value = document.to_dict() or {}
            created = value.get("createdAt")
            read_at = value.get("readAt")
            records.append({"notificationId": document.id, **value, "createdAt": created.isoformat() if created else None, "readAt": read_at.isoformat() if read_at else None})
        records.sort(key=lambda record: record.get("createdAt") or "", reverse=True)
        return records

    def mark_read(self, notification_id: str, actor_id: str, is_admin: bool) -> None:
        """Mark an owned notification as read in both history locations."""
        reference = self.db.collection("notifications").document(notification_id)
        snapshot = reference.get()
        if not snapshot.exists:
            raise KeyError(notification_id)
        recipient_id = snapshot.get("recipientId")
        if not is_admin and recipient_id != actor_id:
            raise PermissionError(notification_id)
        batch = self.db.batch()
        updates = {"read": True, "readAt": firestore.SERVER_TIMESTAMP}
        batch.update(reference, updates)
        batch.set(self.db.collection("users").document(recipient_id).collection("notifications").document(notification_id), updates, merge=True)
        batch.commit()

    def delete_notification(self, notification_id: str, actor_id: str, is_admin: bool) -> None:
        """Delete an owned notification from both history locations."""
        reference = self.db.collection("notifications").document(notification_id)
        snapshot = reference.get()
        if not snapshot.exists:
            raise KeyError(notification_id)
        recipient_id = snapshot.get("recipientId")
        if not is_admin and recipient_id != actor_id:
            raise PermissionError(notification_id)
        batch = self.db.batch()
        batch.delete(reference)
        batch.delete(self.db.collection("users").document(recipient_id).collection("notifications").document(notification_id))
        batch.commit()

    def _tokens_for_user(self, user_id: str) -> list[tuple[str, str]]:
        return [(document.id, str(document.get("deviceToken"))) for document in self.db.collection("deviceTokens").where("userId", "==", user_id).stream() if document.get("deviceToken")]

    def _store_history(self, user_id: str, title: str, body: str, notification_type: NotificationType, status_value: str, data: dict[str, Any]) -> str:
        reference = self.db.collection("notifications").document()
        value = {"notificationId": reference.id, "recipientId": user_id, "title": title, "body": body, "type": notification_type.value, "status": status_value, "createdAt": firestore.SERVER_TIMESTAMP, "read": False, "readAt": None, "data": data}
        legacy = {"type": notification_type.value, "title": title, "body": body, "status": status_value, "read": False, "readAt": None, "data": data, "createdAt": firestore.SERVER_TIMESTAMP}
        batch = self.db.batch()
        batch.set(reference, value)
        batch.set(self.db.collection("users").document(user_id).collection("notifications").document(reference.id), legacy)
        batch.commit()
        return reference.id

    @staticmethod
    def _invalid_token(error: Exception | None) -> bool:
        if error is None:
            return False
        code = str(getattr(error, "code", "")).lower()
        text = str(error).lower()
        return any(value in code or value.replace("-", " ") in text for value in INVALID_TOKEN_CODES)


def send_push_notification(title: str, body: str, user_id: str, data: dict[str, Any] | None = None) -> SendResult:
    """Compatibility function for application services."""
    return NotificationService().send_to_user(user_id, title, body, NotificationType.ADMIN_MESSAGE, data)


def send_to_user(user_id: str, title: str, body: str, notification_type: NotificationType, data: dict[str, Any] | None = None) -> SendResult:
    return NotificationService().send_to_user(user_id, title, body, notification_type, data)


def send_to_multiple_users(user_ids: Iterable[str], title: str, body: str, notification_type: NotificationType, data: dict[str, Any] | None = None) -> SendResult:
    return NotificationService().send_to_multiple_users(user_ids, title, body, notification_type, data)


def send_to_topic(topic: str, title: str, body: str, notification_type: NotificationType, data: dict[str, Any] | None = None) -> str:
    return NotificationService().send_to_topic(topic, title, body, notification_type, data)
