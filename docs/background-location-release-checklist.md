# EcoTrace background-location release checklist

The codebase is configured for continuous GPS updates only during a driver-initiated active route. The in-app flow displays a prominent disclosure, requests foreground location first, then requests background location. Drivers can pause tracking or complete the route to stop collection.

Store approval is not automatic. Complete the following account and listing work before release.

## Google Play

- Confirm background location is essential to live route progress, arrival detection, and route-deviation alerts. Google permits it only for a core feature with clear user value.
- In Play Console, complete **Policy > App content > Sensitive app permissions > Location permissions**.
- Declare one primary feature: **live driver route tracking during an active e-waste collection route**.
- Record a short Android review video showing: opening EcoTrace, starting a route, the complete in-app disclosure, accepting and denying the permission flow, selecting **Allow all the time**, backgrounding the app, the ongoing notification, and location-driven route updates.
- Complete the Foreground Service declaration for the `location` service type.
- Complete Data safety accurately. EcoTrace collects precise location and location history, links it to the signed-in driver/route, and sends it to its Firebase service provider for dispatch operations. Do not mark the data as ephemeral because route history is stored.
- Publish a non-editable, public HTTPS privacy-policy page. Link it in Play Console and inside EcoTrace. It must name EcoTrace and the legal developer entity; explain collection, use, service providers, retention/deletion, security, and how consent can be withdrawn.
- Make the store description and screenshots visibly describe live/background route tracking.
- Supply working review credentials for a driver account with an assigned route.

Official references: [Google Play background location](https://support.google.com/googleplay/android-developer/answer/9799150), [prominent disclosure guidance](https://support.google.com/googleplay/android-developer/answer/11150561), and [Android foreground services](https://developer.android.com/develop/background-work/services/fgs/launch).

## Apple App Store

- In App Store Connect privacy details, disclose **Precise Location** and the purposes that match the production behavior (App Functionality; and only other purposes actually used).
- Add review notes explaining that background location is limited to a driver-started active collection route and stops when paused or completed.
- Provide a driver review account, an assigned route, and exact steps to reach **Routes and GPS**.
- Ensure the public HTTPS privacy-policy URL is present in App Store Connect and reachable inside the app before submission.
- Test the When In Use → Always upgrade on a physical iPhone, the blue background-location indicator, pause, completion, permission denial, and Settings recovery.
- Build the iOS app on macOS and run `pod install` after `flutter pub get`; background location cannot be fully validated from Windows.

Official references: [Apple background location](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background), [App Review Guidelines 2.5.4 and 5.1](https://developer.apple.com/app-store/review/guidelines/), and [App privacy details](https://developer.apple.com/app-store/app-privacy-details/).

## Release blockers requiring product-owner input

- Replace the default Android application ID `com.example.wastemanagementsystem` and configure release signing.
- Confirm the legal developer/company name, public privacy-policy URL, support contact, location-retention period, deletion process, and Firebase/other service-provider list.
- Add the final privacy-policy link inside EcoTrace. The existing registration copy refers to a policy but does not link to a hosted policy.
- Validate that Firestore authentication custom claims contain each user's role; mobile security rules depend on those claims.
