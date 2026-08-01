# EcoTrace Push Notification Service

FastAPI service for device-token management, Firebase Cloud Messaging delivery, invalid-token cleanup, event templates, and notification history.

## Local start

```powershell
cd notifications_service
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:GOOGLE_APPLICATION_CREDENTIALS='C:\secure\firebase-service-account.json'
uvicorn app.main:app --reload --port 8001
```

Use a Firebase ID token as `Authorization: Bearer <token>`. Never commit the service-account JSON.

## Render environment

- `FIREBASE_PROJECT_ID`
- `FIREBASE_SERVICE_ACCOUNT_BASE64` (base64 of the complete service-account JSON)
- `API_ALLOWED_ORIGINS` (comma-separated Flutter Web origins)
- `NOTIFICATION_EVENT_KEY` (long random secret shared only with trusted backend services)

Render provides `PORT`; the Blueprint start command binds Uvicorn to it. OpenAPI is available at `/docs` and `/openapi.json`.

## Flutter configuration

Launch Flutter with both backend URLs:

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=https://ecotrace-api-ixev.onrender.com --dart-define=NOTIFICATION_API_BASE_URL=https://ecotrace-notifications.onrender.com --dart-define=FCM_WEB_VAPID_KEY=YOUR_FIREBASE_WEB_PUSH_CERTIFICATE_KEY
```

The app registers the current FCM token after login, refreshes it when Firebase rotates the token, and removes it during logout.
For web builds, copy the public Web Push certificate key from Firebase Console → Project settings → Cloud Messaging → Web Push certificates into `FCM_WEB_VAPID_KEY`. This is a public browser key, not the Firebase service-account private key.

## Domain events

The existing EcoTrace Node API calls `POST /notifications/events` using the shared `NOTIFICATION_EVENT_KEY`. The Render Blueprint places the same generated secret in both services. Pickup submission, collector assignment, driver departure, and pickup completion are already connected. Recycling APIs can call the same endpoint with `recycler_received_item` and `recycling_completed` when those workflows are migrated.
