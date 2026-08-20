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
   origins — this must include the Firebase Hosting site if the web build is
   deployed there. For example:

   ```text
   https://wastemanagementsystem-902eb.web.app,https://wastemanagementsystem-902eb.firebaseapp.com
   ```

   There is no wildcard fallback (`functions/src/app.ts`): an origin missing
   from this list is silently rejected by CORS, which surfaces in the browser
   as a failed fetch with no useful error from the API itself.

6. After the health check succeeds, note the *actual* URL Render assigned the
   service (visible on the service's Render dashboard page) — it commonly
   differs from the plain `render.yaml` service name because Render appends a
   random suffix when the exact name is taken. As of this writing it is
   `https://ecotrace-api-ixev.onrender.com`; verify with
   `curl https://<service-url>/health` before building against it.

Delete the downloaded key after saving the Render secret. If the key is ever
exposed in source control, logs, screenshots, or chat, revoke it immediately
in Google Cloud IAM and create a replacement. Render's free service can sleep
after inactivity, so the first API request after an idle period may be slow.

## Flutter Web (Firebase Hosting) production build

```powershell
flutter build web --release --dart-define=API_BASE_URL=https://ecotrace-api-ixev.onrender.com
firebase deploy --only hosting
```

`API_BASE_URL` has no default value (`lib/core/api/api_config.dart`), so
omitting it silently disables the whole API layer in the built app —
including Cloudinary image uploads — rather than failing the build. There is
no CI step that does this automatically; it must be run by hand (or wired
into a pipeline) before every Hosting deploy. `firebase.json`'s `hosting`
block pins `"site": "wastemanagementsystem-902eb"`, which newer
`firebase-tools` versions require even when the project has only one site.

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

### Card (Stripe) and PayPal payments

Alongside Monime mobile money, citizens can pay with a card (via Stripe
Checkout) or PayPal. Both use a hosted-checkout redirect rather than an
embedded card form — this app targets Android/iOS/web/Windows, and
`flutter_stripe` (the native card-form SDK) has no Windows support, so the
backend creates a session/order and the app opens the returned URL in an
external browser tab, then watches `paymentTransactions/{id}` in Firestore
for the result exactly like the Monime flow does. Both gateways settle in
USD (Stripe/PayPal don't support Sierra Leone's SLE); the SLE amount stays
the source of truth on the transaction doc, converted to USD at
checkout-creation time using `systemSettings/billing.sleToUsdRate` (a
placeholder default lives in `payment-routes.ts` — an administrator must set
this Firestore field to a real, current rate before accepting real payments).

**Stripe**: create an account at <https://dashboard.stripe.com>, then set on
the Render `ecotrace-api` service:

```text
STRIPE_SECRET_KEY=<sk_test_... while testing, sk_live_... in production>
STRIPE_WEBHOOK_SECRET=<whsec_... from the webhook endpoint below>
```

In the Stripe dashboard, add a webhook endpoint pointing at
`https://<the Render API URL>/api/v1/payments/stripe/webhook`, subscribed to
`checkout.session.completed` and `checkout.session.expired`, then copy its
signing secret into `STRIPE_WEBHOOK_SECRET`.

**PayPal**: create an app at
<https://developer.paypal.com/dashboard/applications> (sandbox first), then
set:

```text
PAYPAL_CLIENT_ID=<from the PayPal app>
PAYPAL_CLIENT_SECRET=<from the PayPal app>
PAYPAL_API_BASE_URL=https://api-m.sandbox.paypal.com   # https://api-m.paypal.com in production
```

PayPal redirects the payer's browser directly to
`/api/v1/payments/paypal/capture` after approval (a plain backend route, not
a webhook) to finalize the charge, so no dashboard configuration is required
for that path. Optionally also register a webhook at
`/api/v1/payments/paypal/webhook` subscribed to `CHECKOUT.ORDER.APPROVED`
and `PAYMENT.CAPTURE.COMPLETED` — this is a backup confirmation path for
when a payer approves on PayPal but never returns to the app (closed tab,
lost network), used alongside a scheduled job
(`payment-expiry-scheduler.ts`) that fails any card/PayPal payment left
`pending` for more than 3 hours.

Also set `API_PUBLIC_URL` (this API's own public URL, used to build the
PayPal return URL — distinct from `WEB_APP_URL`, the Flutter web frontend
both gateways redirect back to once payment is settled) if it differs from
the default in `payment-routes.ts`.

## Federated sign-in (Google, Apple, GitHub)

Google, Apple, and GitHub sign-in use Firebase Authentication's built-in
generic OAuth provider flow (`FirebaseAuth.signInWithProvider`) directly —
no separate `google_sign_in`/`sign_in_with_apple` package, no backend route
or code change at all. Supported on Android, iOS, and web only; the buttons
are hidden on Windows/macOS/Linux desktop, where the Flutter plugin has no
implementation.

Each provider needs to be enabled once in the Firebase Console
(Authentication → Sign-in method) before its button will work — nothing to
configure in `render.yaml`:

- **Google**: enable the provider; Firebase handles the OAuth client for
  you. On Android, add the app's SHA-1/SHA-256 fingerprints under Project
  Settings → your Android app (`keytool -list -v -keystore <path>` for a
  release keystore) or Google Sign-In will fail silently there.
- **Apple**: requires an active Apple Developer Program membership. Create a
  Services ID and a Sign in with Apple key in the Apple Developer portal,
  then enter them under the Apple provider's configuration in Firebase.
  Required on iOS by App Store guidelines whenever another third-party
  sign-in option (Google here) is offered.
- **GitHub**: create an OAuth App at
  <https://github.com/settings/developers> with its callback URL set to the
  one Firebase's GitHub provider screen shows, then paste the resulting
  Client ID/Secret into Firebase.

A first-time sign-in with any of these creates the Firebase Auth user
without a `users` profile document — there's no form to collect a role or
terms acceptance from, unlike email/password registration. `AuthGate`
(`lib/features/auth/presentation/auth_gate.dart`) detects the missing
profile and shows `CompleteProfileScreen`, which calls the same
`/api/v1/identity/bootstrap` endpoint (or the equivalent direct-Firestore
write) email/password registration already uses — so the profile shape and
Firestore rules are identical regardless of how the account signed in.

## Migration roadmap

1. Authentication profile mutations and audit delivery.
2. Pickup lifecycle, dispatch, route generation, and live GPS updates (API-backed).
3. Collection-centre operations plus inventory, classification, batches, item history, and traceability (API-backed).
4. Repair, recycling, recovery, hazardous waste, and reverse logistics.
5. Marketplace, donations, rewards, billing, and partner workflows.
6. Compliance, incidents, documents, notifications, analytics, and reports.
7. Remove client Firestore writes and tighten Firestore rules so business data
   is accessible only through the API/Admin SDK.
