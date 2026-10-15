# Rent & Play Android

## Mobile staff counter

The Android app uses the same login page for customers, operators, and owners. An active `OPERATOR` or `OWNER` account opens a focused staff counter with rental review, QR scanning, equipment handoff, return inspection, equipment details and unit maintenance. Staff can check the Bluetooth printer connection and print 50 × 30 mm QR labels, open the Android print screen, or share the label PDF. **Manage maintenance** opens the shared ticket workflow for reports, repairs, photos, assignments, cost records, inspection and retirement. Equipment setup, customer administration, rates, reports, and staff settings stay in the web admin workspace in the adjacent `RENT-AND-PLAY` project. Signing out returns to the shared login page. Legacy `ADMIN`/`USER` roles map to Operator/Customer.

Rental changes refresh the staff counter immediately through the shared live event connection used by notifications and customer rental progress. The counter combines short event bursts, resyncs after reconnection or app resume, and pauses background reads. Its five-minute foreground check also catches non-rental inventory edits. See the [Firebase usage changes](../RENT-AND-PLAY/docs/development/firebase-usage-optimization.md) and run `flutter test test/live_rental_updates_test.dart test/notification_service_test.dart test/rental_events_test.dart` for the live-update regression tests.

## Account validation and recovery

Login and registration normalize emails to lowercase, reject spaces, and check email format only; no flow performs a DNS/domain lookup. Registration verifies mailbox ownership with an email code. Registration shows inline name, email, phone, password-strength, and matching-confirmation errors. New passwords require at least eight characters, a capital letter, and a number. Forgot password uses the same email-code, verification, and new-password flow as the web app. App launch uses an ordinary opening screen; it does not describe a saved login as account recovery.

New Owner/Operator accounts must change their temporary password before entering the staff workspace. The backend enforces this restriction independently of routing, and mobile asks the user to log in with the new password. See [the shared account procedures](../RENT-AND-PLAY/docs/architecture/account-access.md).

## Test customer rentals without the ESP32

Customer checkout saves an authoritative quote for the rental fee and holds the physical unit while the request waits for admin review. The customer gets a transaction QR. In web or Android admin, approve the request: it becomes **Awaiting pickup**, and the timer has not started. Scan the customer's transaction QR and the assigned equipment sticker, verify the customer and rental payment, check condition/accessories, then confirm release. This starts the timer and marks the equipment rented.

On return, admin scans the equipment and records physical receipt. The timer stops immediately while the unit stays under inspection. Complete inspection with an explicit penalty (zero if none) to make it available or send it to maintenance. Rental payment balances are tracked separately from equipment availability. The customer can report a return, but only staff receipt stops the timer. Pending/approved bookings can be cancelled and unclaimed holds expire automatically.

The web **ESP32 terminal** page, device APIs and firmware stay on standby for implementation at the end of the project. The backend defaults to `ENABLE_ESP32=false`. Android's retired direct-database hardware screens have been removed; future hardware integration must use the same authenticated backend. No current rental step uses the terminal. See [the standby plan](../RENT-AND-PLAY/docs/esp32/standby-plan.md).

## Local development without deploying

The website at `http://127.0.0.1:5173` uses the laptop backend on port 3000. The phone must use that same backend to test local code changes. On a phone, `127.0.0.1` refers to the phone itself unless USB forwarding is configured.

1. In the adjacent `RENT-AND-PLAY` VS Code window, run **Rent & Play: Start App** and leave both servers running.
2. Turn on the laptop's **RentPlay-Local** Mobile Hotspot at **2.4 GHz**, and connect both phones to it. The laptop backend is reachable at `http://192.168.137.1:3000/api`. Keep the laptop connected to the Internet for Firebase. A guest router network can isolate phones from the laptop, even when the SSID is the same.
3. Open a PowerShell terminal in `AndroidFiles` and run `powershell -ExecutionPolicy Bypass -File .\scripts\local-android.ps1`. This prefers the active Windows hotspot address, otherwise detects the laptop's Wi-Fi IPv4 address, checks that port 3000 is reachable without reading Firestore, and starts Flutter with the local API.
4. To install on both phones by USB, connect and authorize both phones, then run `powershell -ExecutionPolicy Bypass -File .\scripts\local-android.ps1 -Connection WiFi -ApiHost 192.168.137.1 -BuildApk -Install -AllDevices`. The helper builds one APK with the hotspot API address and installs it on every connected, authorized Android device. You can unplug both USB cables after installation and open the app normally; both phones must stay connected to the laptop hotspot, with the backend running. Its output is `build/app/outputs/flutter-apk/app-local-debug.apk`. For one phone, use `-DeviceId <device-id>` instead of `-AllDevices`.

In Android Studio, select **Rent & Play: Phones (Hotspot 192.168.137.1)** even when installing over USB. In VS Code, select **Rent & Play: Phones (USB install, Wi-Fi API)**. These profiles use Wi-Fi for API requests, so they keep working when USB is unplugged. If switching away from the laptop hotspot, rebuild with `-ApiHost <laptop-ip>` or update the run configuration for that network. Start the backend first either way.

Backend changes only need a backend restart. Web changes use the local web server. Flutter changes use hot reload during `flutter run`, or require another APK build/install when testing an installed APK. Local development does not need a Git push or external web hosting. Firebase data still uses the configured shared project.

If the laptop's Wi-Fi address changes, rerun the script and reinstall the local APK so it contains the new address. Use `-ApiHost <laptop-ip>` to select a particular interface. For a cable connection without Wi-Fi, use `-Connection USB`; it sets up `adb reverse` and points the phone at `http://127.0.0.1:3000/api`. Keep USB connected and rerun after reconnecting. For an emulator, use `-Connection Emulator`.

In an `AndroidFiles` VS Code window, use one of the included local Android launch configurations. The USB option sets up forwarding before F5. Start the backend and web in their own VS Code window first.

## Local API and manual commands

The bell opens the rental notification inbox for customers, operators, and owners. New customer rental/return requests alert active `OPERATOR` and `OWNER` accounts; approval, rejection, release and return decisions alert the customer. Tap an update to open that rental, or use **Mark shown as read**. On Android, select **Enable phone alerts** in the inbox to grant notification permission and register background FCM alerts. Sign-out unregisters the phone, and switching accounts rotates the device token. See `../RENT-AND-PLAY/docs/architecture/rental-notifications.md` for deployment and real-device acceptance steps.

The app defaults to the local Android emulator API at `http://10.0.2.2:3000/api`; the included USB launch profile uses `http://127.0.0.1:3000/api`. To test local changes:

- From the `RENT-AND-PLAY` folder, start the backend in one terminal: `cd apps/backend` then `npm run dev`.
- In a second terminal, start the web admin: `cd apps/web` then `npm run dev`. Open `http://localhost:5173`; it proxies API requests to the local backend on port 3000.
- Android emulator: `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api`
- Physical Android phone on the same Wi-Fi: `flutter run --dart-define=API_BASE_URL=http://<laptop-ip>:3000/api`, or use `scripts/local-android.ps1 -Connection WiFi`.

The backend must have its Firebase credentials configured for the same `rent-and-play` project used by the app. Local HTTP access is enabled for debug builds only; release builds continue to use HTTPS.

Run `flutter test` for customer requests, staff approval, lifecycle, receipt time, maintenance and shared IDs. Run `flutter analyze` for static checks. For a read-only check on a connected phone, run `flutter test -d <device-id> integration_test/local_connection_test.dart --dart-define=API_BASE_URL=http://<laptop-ip>:3000/api`; it verifies the real catalog, QR/code resolution and ESP32 standby. Build an installable test APK with `flutter build apk --debug`; its output is `build/app/outputs/flutter-apk/app-debug.apk`. Use a reachable `API_BASE_URL` when building for a local server. Grant camera permission on the test Android device and check both printed QR labels. Manual lookup requires a reason if a camera is unavailable.

The full flow and local setup instructions are in the adjacent `RENT-AND-PLAY/docs/architecture/admin-rental-flow.md` and `RENT-AND-PLAY/docs/development/local-integration.md`.
