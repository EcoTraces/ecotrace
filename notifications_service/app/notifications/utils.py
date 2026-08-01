"""Authentication, authorization, and FCM payload utilities."""

import hashlib
import os
from dataclasses import dataclass
from typing import Any

from fastapi import Depends, Header, HTTPException, status
from firebase_admin import auth

from app.notifications.firebase import get_db

ADMIN_ROLES = frozenset({"administrator", "superAdministrator"})


@dataclass(frozen=True, slots=True)
class CurrentUser:
    uid: str
    role: str
    email: str | None


async def current_user(authorization: str | None = Header(default=None)) -> CurrentUser:
    """Verify a Firebase bearer token and resolve its EcoTrace role."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "A Firebase ID token is required.")
    try:
        decoded = auth.verify_id_token(authorization[7:])
        role = decoded.get("role")
        if not role:
            profile = get_db().collection("users").document(decoded["uid"]).get()
            role = profile.get("role") if profile.exists else "household"
        return CurrentUser(decoded["uid"], str(role), decoded.get("email"))
    except Exception as exc:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "The Firebase ID token is invalid or expired.") from exc


async def admin_user(user: CurrentUser = Depends(current_user)) -> CurrentUser:
    """Require an EcoTrace administrator."""
    if user.role not in ADMIN_ROLES:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Administrator permission is required.")
    return user


async def event_authorized(
    x_ecotrace_event_key: str | None = Header(default=None),
    authorization: str | None = Header(default=None),
) -> CurrentUser | None:
    """Authorize trusted backend event calls or administrator tokens."""
    configured = os.getenv("NOTIFICATION_EVENT_KEY", "").strip()
    if configured and x_ecotrace_event_key and secrets_equal(configured, x_ecotrace_event_key):
        return None
    user = await current_user(authorization)
    if user.role not in ADMIN_ROLES:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Trusted backend or administrator permission is required.")
    return user


def secrets_equal(left: str, right: str) -> bool:
    """Compare secrets without leaking timing information."""
    import hmac
    return hmac.compare_digest(left.encode(), right.encode())


def token_document_id(token: str) -> str:
    """Create a stable, non-secret Firestore document identifier."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def stringify_data(data: dict[str, Any]) -> dict[str, str]:
    """Convert values to the string-only format required by FCM."""
    import json
    return {str(key): value if isinstance(value, str) else json.dumps(value, separators=(",", ":"), default=str) for key, value in data.items()}
