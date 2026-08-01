# EcoTrace API architecture

## Target architecture

```text
Flutter (Android, iOS, web, Windows)
  -> HTTPS + Firebase ID token
EcoTrace REST API (Cloud Functions v2)
  -> Firebase Admin SDK
Cloud Firestore
```

Firebase Authentication remains in Flutter for sign-in and token refresh. All
business data is migrated feature-by-feature from direct Firestore repositories
to versioned API endpoints. The API verifies protected requests, resolves the
user role, validates payloads, applies business rules, and accesses Firestore
through the Admin SDK.

## Phase 1 endpoints

| Method | Path | Access |
| --- | --- | --- |
| GET | `/health` | Public |
| GET | `/openapi.json` | Public |
| GET | `/api/v1/me` | Authenticated |
| GET | `/api/v1/collection-centres` | Public directory |
| POST | `/api/v1/collection-centres` | Administrator |
| GET | `/api/v1/vehicles` | Authenticated |
| POST | `/api/v1/vehicles` | Administrator |
| GET | `/api/v1/pickup-requests` | Authenticated and role-filtered |
| POST | `/api/v1/pickup-requests` | Authenticated |
| GET | `/api/v1/dispatch/schedules?from=&to=` | Dispatch roles; assignments filtered for field staff |
| POST | `/api/v1/dispatch/schedules` | Administrator |
| GET | `/api/v1/dispatch/assignable-pickups` | Administrator |
| GET | `/api/v1/dispatch/staff` | Administrator |
| PATCH | `/api/v1/dispatch/schedules/{id}/dispatch` | Administrator |
| PATCH | `/api/v1/dispatch/schedules/{id}/start` | Assigned field staff or administrator |
| PATCH | `/api/v1/dispatch/schedules/{id}/complete` | Assigned field staff or administrator |
| PATCH | `/api/v1/dispatch/schedules/{id}/reschedule` | Administrator |
| GET | `/api/v1/routes` | Administrator or assigned driver |
| GET | `/api/v1/routes/schedulable` | Administrator |
| POST | `/api/v1/routes/optimize` | Administrator |
| GET | `/api/v1/routes/{id}` | Administrator or assigned driver |
| PATCH | `/api/v1/routes/{id}/start` | Administrator or assigned driver |
| POST | `/api/v1/routes/{id}/positions` | Administrator or assigned driver |
| PATCH | `/api/v1/routes/{id}/complete` | Administrator or assigned driver |
| GET | `/api/v1/collection-centres/{id}` | Assigned centre operator, environmental officer, or administrator |
| GET | `/api/v1/collection-centres/{id}/storageSections` | Centre operations roles |
| GET | `/api/v1/collection-centres/{id}/receivingRecords` | Centre operations roles |
| GET | `/api/v1/collection-centres/{id}/stockMovements` | Centre operations roles |
| GET | `/api/v1/collection-centres/{id}/staffAssignments` | Centre operations roles |
| GET | `/api/v1/collection-centres/{id}/safetyInspections` | Centre operations roles |
| POST | `/api/v1/collection-centres/{id}/sections` | Centre operations roles |
| POST | `/api/v1/collection-centres/{id}/staff` | Administrator |
| POST | `/api/v1/collection-centres/{id}/check-ins` | Centre operations roles |
| PATCH | `/api/v1/collection-centres/{id}/receiving/{recordId}/verify` | Centre operations roles |
| POST | `/api/v1/collection-centres/{id}/check-outs` | Centre operations roles |
| POST | `/api/v1/collection-centres/{id}/inspections` | Centre operations roles |
| POST | `/api/v1/admin/demo-data` | Administrator; creates or refreshes role-specific demonstration records |
| GET/POST | `/api/v1/inventory/items` | Authenticated read; operational roles register items |
| GET | `/api/v1/inventory/items/by-code/{code}` | Authenticated trace lookup |
| GET | `/api/v1/inventory/items/{id}/history` | Authenticated item history |
| PATCH | `/api/v1/inventory/items/{id}/state` | Operational roles update status and location |
| GET/POST | `/api/v1/inventory/batches` | Authenticated read; operational roles create batches |
| PATCH | `/api/v1/inventory/items/{id}/batch` | Operational roles assign an item to a batch |
| GET/POST | `/api/v1/inventory/items/{id}/assessments` | Authenticated read; operational roles submit classification |
| PATCH | `/api/v1/inventory/items/{id}/assessments/{assessmentId}/review` | Administrator or environmental officer |
| GET/POST | `/api/v1/inventory/items/{id}/traceability` | Authenticated read; operational roles record custody events |

The demo-data endpoint uses deterministic document IDs and marks generated
records with `demoData: true`. It can be run repeatedly without creating an
unbounded number of duplicate records.

## Local development

```powershell
Set-Location functions
npm install
Set-Location ..
firebase.cmd emulators:start --only auth,firestore,functions
```

Run Flutter web against the local API:

```powershell
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATORS=true --dart-define=API_BASE_URL=http://127.0.0.1:5001/wastemanagementsystem-902eb/europe-west1/api
```

For an Android emulator, replace `127.0.0.1` with `10.0.2.2` and set
`FIREBASE_EMULATOR_HOST=10.0.2.2`.

## Production configuration

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://europe-west1-wastemanagementsystem-902eb.cloudfunctions.net/api
```

Never include a service-account JSON file in Flutter, Git, or application
assets. Cloud Functions uses its runtime service identity.

## Render deployment

The repository includes a `render.yaml` Blueprint for a free Render web
service. It installs build-time dependencies even with `NODE_ENV=production`,
builds the `functions` package, starts `lib/server.js`, and checks `/health`.
The same Express application remains deployable as a Firebase Function.

1. Create a Firebase Admin service-account key in Google Cloud IAM. Keep the
   downloaded JSON outside this repository.
2. Convert the complete JSON file to base64 in PowerShell:

   ```powershell
   $keyPath = "C:\path\to\firebase-admin-key.json"
   [Convert]::ToBase64String([IO.File]::ReadAllBytes($keyPath)) | Set-Clipboard
   ```

3. In Render, choose **New > Blueprint**, connect this GitHub repository, and
   select `render.yaml`.
4. When prompted, paste the clipboard value into
   `FIREBASE_SERVICE_ACCOUNT_BASE64`.
5. Set `API_ALLOWED_ORIGINS` to the comma-separated deployed Flutter web
   origins. For example:

   ```text
   https://ecotrace.example.com,https://ecotrace-web.onrender.com
   ```

6. After the health check succeeds, build Flutter with the Render service URL:

   ```powershell
   flutter build apk --release --dart-define=API_BASE_URL=https://ecotrace-api.onrender.com
   ```

Delete the downloaded key after saving the Render secret. If the key is ever
exposed in source control, logs, screenshots, or chat, revoke it immediately
in Google Cloud IAM and create a replacement. Render's free service can sleep
after inactivity, so the first API request after an idle period may be slow.

### Cloudinary image storage

User-uploaded images use signed direct uploads to Cloudinary. Flutter requests
a short-lived signature from `/api/v1/media/upload-signature` and uploads the
bytes directly to Cloudinary, so the Cloudinary API secret is never shipped in
the app and Render does not proxy large image bodies.

Create a Cloudinary product environment and add these secret environment
variables to the Render web service:

```text
CLOUDINARY_CLOUD_NAME=<Cloudinary cloud name>
CLOUDINARY_API_KEY=<Cloudinary API key>
CLOUDINARY_API_SECRET=<Cloudinary API secret>
```

After saving the variables, redeploy the Render service. Pickup, inventory,
collection evidence, incident, donation, support, compliance, partner, and
reverse-logistics images are stored under role-scoped `ecotrace/` folders.
General document/PDF storage remains a separate workflow.

## Migration roadmap

1. Authentication profile mutations and audit delivery.
2. Pickup lifecycle, dispatch, route generation, and live GPS updates (API-backed).
3. Collection-centre operations plus inventory, classification, batches, item history, and traceability (API-backed).
4. Repair, recycling, recovery, hazardous waste, and reverse logistics.
5. Marketplace, donations, rewards, billing, and partner workflows.
6. Compliance, incidents, documents, notifications, analytics, and reports.
7. Remove client Firestore writes and tighten Firestore rules so business data
   is accessible only through the API/Admin SDK.
