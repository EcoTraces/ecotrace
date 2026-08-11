"""Pydantic request and response schemas for notifications."""

from enum import StrEnum
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


class NotificationType(StrEnum):
    PICKUP_REQUEST = "PICKUP_REQUEST"
    PICKUP_ACCEPTED = "PICKUP_ACCEPTED"
    COLLECTOR_ASSIGNED = "COLLECTOR_ASSIGNED"
    DRIVER_EN_ROUTE = "DRIVER_EN_ROUTE"
    PICKUP_COMPLETED = "PICKUP_COMPLETED"
    RECYCLER_RECEIVED = "RECYCLER_RECEIVED"
    RECYCLING_COMPLETED = "RECYCLING_COMPLETED"
    ANNOUNCEMENT = "ANNOUNCEMENT"
    SECURITY_ALERT = "SECURITY_ALERT"
    ADMIN_MESSAGE = "ADMIN_MESSAGE"
    CLASSIFICATION = "CLASSIFICATION"
    STATUS_UPDATE = "STATUS_UPDATE"
    COMPLIANCE_ALERT = "COMPLIANCE_ALERT"
    REWARD = "REWARD"
    PAYMENT = "PAYMENT"
    MAINTENANCE = "MAINTENANCE"
    PICKUP_REMINDER = "PICKUP_REMINDER"


class DevicePlatform(StrEnum):
    ANDROID = "android"
    IOS = "ios"
    WEB = "web"
    WINDOWS = "windows"


class RegisterTokenRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    user_id: str | None = Field(default=None, alias="userId", min_length=1)
    device_token: str = Field(alias="deviceToken", min_length=20, max_length=4096)
    platform: DevicePlatform


class RemoveTokenRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    device_token: str = Field(alias="deviceToken", min_length=20, max_length=4096)


class SendNotificationRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    title: str = Field(min_length=1, max_length=200)
    body: str = Field(min_length=1, max_length=2000)
    user_id: str = Field(alias="userId", min_length=1)
    type: NotificationType
    data: dict[str, Any] = Field(default_factory=dict)

    @field_validator("data")
    @classmethod
    def limit_data(cls, value: dict[str, Any]) -> dict[str, Any]:
        if len(value) > 50:
            raise ValueError("Notification data cannot contain more than 50 keys.")
        return value


class AdminMessageRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    user_ids: list[str] = Field(alias="userIds", min_length=1, max_length=500)
    title: str = Field(default="Admin Message", min_length=1, max_length=200)
    body: str = Field(min_length=1, max_length=2000)
    data: dict[str, Any] = Field(default_factory=dict)

    @field_validator("user_ids")
    @classmethod
    def unique_users(cls, values: list[str]) -> list[str]:
        return list(dict.fromkeys(value.strip() for value in values if value.strip()))


class AnnouncementRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    body: str = Field(min_length=1, max_length=2000)
    title: str = Field(default="Announcement", min_length=1, max_length=200)
    data: dict[str, Any] = Field(default_factory=dict)
    topic: str | None = Field(default=None, pattern=r"^[a-zA-Z0-9-_.~%]+$")


class EventName(StrEnum):
    PICKUP_REQUEST_SUBMITTED = "pickup_request_submitted"
    PICKUP_ACCEPTED = "pickup_accepted"
    COLLECTOR_ASSIGNED = "collector_assigned"
    DRIVER_EN_ROUTE = "driver_en_route"
    PICKUP_COMPLETED = "pickup_completed"
    PICKUP_CANCELLED = "pickup_cancelled"
    PICKUP_RESCHEDULED = "pickup_rescheduled"
    PICKUP_FAILED = "pickup_failed"
    PICKUP_STATUS_UPDATED = "pickup_status_updated"
    RECYCLER_RECEIVED_ITEM = "recycler_received_item"
    RECYCLING_COMPLETED = "recycling_completed"
    SECURITY_ALERT = "security_alert"
    CLASSIFICATION_ASSESSMENT_SUBMITTED = "classification_assessment_submitted"
    CLASSIFICATION_ASSESSMENT_REVIEWED = "classification_assessment_reviewed"
    CENTRE_STAFF_ASSIGNED = "centre_staff_assigned"
    CENTRE_CAPACITY_ALERT = "centre_capacity_alert"
    CENTRE_SAFETY_ALERT = "centre_safety_alert"
    REPAIR_TECHNICIAN_ASSIGNED = "repair_technician_assigned"
    REPAIR_REVIEWED = "repair_reviewed"
    REPAIR_COMPLETED = "repair_completed"
    REPAIR_UNREPAIRABLE = "repair_unrepairable"
    REPAIR_DISPOSITION_APPROVED = "repair_disposition_approved"
    RECYCLING_HAZARDOUS_MATERIAL_RECORDED = "recycling_hazardous_material_recorded"
    HAZARDOUS_INCIDENT_REPORTED = "hazardous_incident_reported"
    HAZARDOUS_EMERGENCY_RESPONSE_UPDATED = "hazardous_emergency_response_updated"
    HAZARDOUS_INCIDENT_CLOSED = "hazardous_incident_closed"
    HAZARDOUS_WASTE_CERTIFIED = "hazardous_waste_certified"
    LOGISTICS_TRANSFER_SUBMITTED = "logistics_transfer_submitted"
    LOGISTICS_TRANSFER_REVIEWED = "logistics_transfer_reviewed"
    LOGISTICS_TRANSPORT_ASSIGNED = "logistics_transport_assigned"
    LOGISTICS_DISPATCHED = "logistics_dispatched"
    LOGISTICS_EXCEPTION_REPORTED = "logistics_exception_reported"
    LOGISTICS_RECEIVED = "logistics_received"
    PARTNER_LICENCE_REVIEWED = "partner_licence_reviewed"
    PARTNER_STATUS_CHANGED = "partner_status_changed"
    MARKETPLACE_DELIVERY_UPDATED = "marketplace_delivery_updated"
    DONATION_REQUEST_SUBMITTED = "donation_request_submitted"
    DONATION_STATUS_UPDATED = "donation_status_updated"
    REWARD_POINTS_AWARDED = "reward_points_awarded"
    REWARD_POINTS_EXPIRED = "reward_points_expired"
    REWARD_REDEEMED = "reward_redeemed"
    PAYMENT_CONFIRMED = "payment_confirmed"
    PAYMENT_FAILED = "payment_failed"
    PAYMENT_REFUNDED = "payment_refunded"
    PAYOUT_PROCESSED = "payout_processed"
    COMPLIANCE_VIOLATION_RECORDED = "compliance_violation_recorded"
    COMPLIANCE_DOCUMENT_EXPIRING = "compliance_document_expiring"
    FLEET_MAINTENANCE_DUE = "fleet_maintenance_due"
    FLEET_DOCUMENT_EXPIRING = "fleet_document_expiring"
    PICKUP_REMINDER = "pickup_reminder"


class EventNotificationRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    event: EventName
    recipient_id: str | None = Field(default=None, alias="recipientId")
    affected_user_ids: list[str] = Field(default_factory=list, alias="affectedUserIds", max_length=500)
    body: str | None = Field(default=None, max_length=2000)
    data: dict[str, Any] = Field(default_factory=dict)

    @model_validator(mode="after")
    def require_recipient(self) -> "EventNotificationRequest":
        no_recipient = self.event not in {
            EventName.PICKUP_REQUEST_SUBMITTED,
            EventName.CLASSIFICATION_ASSESSMENT_SUBMITTED,
            EventName.HAZARDOUS_INCIDENT_REPORTED,
            EventName.HAZARDOUS_EMERGENCY_RESPONSE_UPDATED,
            EventName.HAZARDOUS_INCIDENT_CLOSED,
            EventName.HAZARDOUS_WASTE_CERTIFIED,
            EventName.LOGISTICS_TRANSFER_SUBMITTED,
            EventName.LOGISTICS_EXCEPTION_REPORTED,
            EventName.PARTNER_LICENCE_REVIEWED,
            EventName.PARTNER_STATUS_CHANGED,
            EventName.DONATION_REQUEST_SUBMITTED,
        } and not self.recipient_id and not self.affected_user_ids
        if no_recipient:
            raise ValueError("A recipientId or affectedUserIds value is required for this event.")
        return self


class SendResult(BaseModel):
    notification_ids: list[str] = Field(alias="notificationIds")
    recipients: int
    sent: int
    failed: int
    removed_tokens: int = Field(alias="removedTokens")


class NotificationRecord(BaseModel):
    notification_id: str = Field(alias="notificationId")
    recipient_id: str = Field(alias="recipientId")
    title: str
    body: str
    type: NotificationType
    status: str
    created_at: str | None = Field(alias="createdAt")
    read: bool
    read_at: str | None = Field(alias="readAt")
    data: dict[str, Any]
