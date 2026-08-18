"""Contract tests that do not require live Firebase credentials."""

import os

os.environ.setdefault("FIREBASE_PROJECT_ID", "test-project")
os.environ.setdefault("FIREBASE_SERVICE_ACCOUNT_JSON", '{"type":"service_account","project_id":"test-project","private_key_id":"x","private_key":"-----BEGIN PRIVATE KEY-----\\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCvdnL6bUBGAcfd\\nzD2CajUFRxJHemuXO6g/6pbW9fD3uhJFYUJ7DGhss5DsUsRqp7c/BgcCtRPhwRV1\\nhcJbUqm+caR9QRBT1Ls8Soalmow+T6vRRNKPots4IpL/3rZKUetjL5y67qCwsz3Z\\n9vvqGFB8G8ex8GpTFeQI4I5/af8UEXjzwWQbzNEF671PlnS/dDlX+aGc43ROaFxS\\nYzy64Ceo96UtTnMmUILnEj4CYEktYfpSFdtYVMwbDMMugRVOM0xKz3pNdLFR/FNS\\nXQnMdckeYVm1w8JdIdFRaxoSk8ekmNTADWnOYyR0tt4G3sC7OaFEr22M8Rlbypo6\\n7zV/hxTdAgMBAAECggEABqhlMPzrwyxGn/Mjw1rR07cwaZ9qzTSBjBlT62iuIcxA\\n7LqFygL8xGEk5t62HsDp6l2JbxAdZsPLk2fFqe7vS29m+Sy6mJ+6Eg3W4ZpFZ4jg\\n4WIt5i7dCBqBvu09uAC3QI56MTqkRMgsWOSvBuEwzqDEOUuA0VHDkxWoOov0VpfJ\\n70A2551HLdyTlTtguZ6SmhV8Mlheeonem1Vu5Clv/NWEbuHDLMbjxBK3gOiSW0xJ\\nlRw6DMZ5e0hPffROVBsI1RsMvnIl4m1tIVaN8c9cs9QwNlMSpb3qUVILFlBT4nON\\nfQk9Yl+MtR33PbvyeAIkv9zf7Win8ofsyQYjd2LbkQKBgQDur8/sASp2NaxbOSun\\nD+l/IyuuFuGeggjyi0XL+O3fxL9lP9o9BRNLDHeBRIwkWPufQMwMWQZCd5QqevlX\\naPJIFtV0HYKf1C92y0q2db55k1p9wa2muVva8FiCv7u5hwmqAmTknqHOYdZuhiJI\\nPYY3VFoq8oFquZRpS/nds1kIkQKBgQC8MKAm3zClls2o4eSrdOI77Wca/q2rZO2Q\\n7XvesZh/MmFzsZ9W/b3yf4ZsYSt93YV7vNC6YdlVV2ppyETS4To6d3g5qRkTkXt6\\nHDHtLd3WOk2NiIfDR66Wb3KmHGuU3kem1Shpow+kz1ou73XoAu03i9hoo2JJzg3N\\nzVQoKC4NjQKBgQDlIGC4bWYVk/CgoYEGHoBHS7viopRzVODB9HBMHeo7pOMWjvUx\\nHm4m3RDbRrJBMipZ9hnqwIsBw0i4ftRc1KHAEitWC/4Y79egcgaGoQD4NDvp/MJ2\\nCfnjclWFLglHUBo22ZWA4cbyF3mBH8JJFsaA1ri4AZO6n+uYKRbze/c8AQKBgQCr\\ngalDI98C2lfd1NkAxUo1EVwJBxehfx7fGP/t6W6wZWrY9ITh0+hba4tHlJr9X3h6\\nV47mfayDEWLCuyi2A1t800p3Sju3ULv2gmGh5U4qIgJxvX71IovjP/h9mKMXDijA\\ny7zD4T6tled7pPKQmrI0EDgOzPATkT2VVM6gtlWaNQKBgGKt9Wabnmx5lTqOqp6x\\n8Q7DaZHiupVngYD0cUsu2I4BObGE+VB7uWNU23+OzpefLPbG+bzGZqsopic9fEJZ\\ntK7QgmPDq0sgc5f+iGqn72GzRFW4nt92XD9WBBLirWSphNzasHbIKDtUrH8JMCJG\\nGup3bFqLO/dqeR7YpMGY+4CG\\n-----END PRIVATE KEY-----\\n","client_email":"test@test-project.iam.gserviceaccount.com","client_id":"1","token_uri":"https://oauth2.googleapis.com/token"}')

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
