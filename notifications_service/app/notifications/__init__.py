"""Push notification domain package."""

from app.notifications.service import NotificationService, send_push_notification

__all__ = ["NotificationService", "send_push_notification"]
