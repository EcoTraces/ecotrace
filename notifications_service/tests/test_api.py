"""Contract tests that do not require live Firebase credentials."""

import os

os.environ.setdefault("FIREBASE_PROJECT_ID", "test-project")
os.environ.setdefault("FIREBASE_SERVICE_ACCOUNT_JSON", '{"type":"service_account","project_id":"test-project","private_key_id":"x","private_key":"-----BEGIN PRIVATE KEY-----\\nMIIBVgIBADANBgkqhkiG9w0BAQEFAASCATAwggEsAgEAAkEAu9C3zo7/2lZrxg8i\\nEBMfuaYhMdE8bH6b4dfzgR3B/E68q+8Ru3oWBSIuPJBEeToemHvblvyfqaYV9/+x\\n5QIDAQABAkEAjfj11wA1EZ90jZQMvdL1JoxQoGeIZLACUdMVuvOxCWOYqaRwRLJk\\nHVZq9g+CKZ1NIhcct4bPl5KsOR6fh48EkQIhAPrFb+ysdvJPQxy/p4kue6Xvjk9q\\nDP3wl00c1rROuLOvAiEAv7KiKYCZj1aVio7xJKqFhM94T+GrR4GZ9Qvf9Ap+zLsC\\nIQDqjq39Qnjzt6Ynw7UYjS/UjKl/m+SrGGQNSWk5WQLL+QIhALTFsw7aA0cVvLrS\\nzVTmll7RpQUJB//JB5fFcBboDHDjAiEAy9UN4sMKwBQXj9Q+9Hg5t4x0TJNeHo/W\\nx/Aovj2T2gw=\\n-----END PRIVATE KEY-----\\n","client_email":"test@test-project.iam.gserviceaccount.com","client_id":"1","token_uri":"https://oauth2.googleapis.com/token"}')

from fastapi.testclient import TestClient

from app.main import app


client = TestClient(app)


def test_health() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["service"] == "ecotrace-notifications"


def test_notifications_require_authentication() -> None:
    response = client.get("/notifications/user/some-user")
    assert response.status_code == 401


def test_openapi_contains_required_routes() -> None:
    paths = client.get("/openapi.json").json()["paths"]
    assert "/notifications/register-token" in paths
    assert "/notifications/send-announcement" in paths
    assert "/notifications/{notification_id}/read" in paths
