"""Secure, duplicate-safe Firebase Admin initialization."""

import base64
import json
import os
from pathlib import Path
from typing import Any

import firebase_admin
from firebase_admin import credentials, firestore


def _service_account() -> dict[str, Any] | None:
    encoded = os.getenv("FIREBASE_SERVICE_ACCOUNT_BASE64", "").strip()
    raw = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON", "").strip()
    file_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
    if encoded:
        return json.loads(base64.b64decode(encoded).decode("utf-8"))
    if raw:
        return json.loads(raw)
    if file_path:
        return json.loads(Path(file_path).read_text(encoding="utf-8"))
    return None


def initialize_firebase() -> firebase_admin.App:
    """Initialize Firebase once using Render secrets or ADC."""
    try:
        return firebase_admin.get_app()
    except ValueError:
        account = _service_account()
        expected_project_id = os.getenv("FIREBASE_PROJECT_ID", "").strip()
        account_project_id = str((account or {}).get("project_id", "")).strip()
        if expected_project_id and account_project_id and expected_project_id != account_project_id:
            raise RuntimeError(
                f"Firebase service account belongs to {account_project_id}, "
                f"expected {expected_project_id}."
            )
        project_id = expected_project_id or account_project_id
        options = {"projectId": project_id} if project_id else None
        credential = credentials.Certificate(account) if account else credentials.ApplicationDefault()
        return firebase_admin.initialize_app(credential, options)


def get_db() -> firestore.Client:
    """Return the initialized Firestore client."""
    initialize_firebase()
    return firestore.client()
