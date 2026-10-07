# Rent & Play Android

## Mobile staff counter

The Android app uses the same login page for customers, operators, and owners. An active `ADMIN` or `OWNER` account opens a focused staff counter with rental review, QR scanning, equipment handoff, and return inspection. Detailed inventory management, customer administration, rates, reports, and staff settings stay in the web admin workspace in the adjacent `RENT-AND-PLAY` project. Signing out of the staff counter returns to the shared login page.

## Test customer rentals without the ESP32

Customer checkout saves an authoritative quote and holds the physical unit while the request waits for admin review. The customer gets a transaction QR. In web or Android admin, approve the request: it becomes **Awaiting pickup**, and the timer has not started. Scan the customer's transaction QR and the assigned equipment sticker, verify the customer and actual fee/deposit collection, check condition/accessories, then confirm release. This starts the timer and marks the equipment rented.

On return, admin scans the equipment and records physical receipt. The timer stops immediately while the unit stays under inspection. Complete inspection with an explicit penalty (zero if none) to make it available or send it to maintenance. Payment balances and deposit refunds remain separate. The customer can report a return, but only staff receipt stops the timer. Pending/approved bookings can be cancelled and unclaimed holds expire automatically.

The **ESP32 terminal** page stays visible on standby. Android hardware actions are disabled and the backend defaults to `ENABLE_ESP32=false`. No current rental step uses the terminal.

## Local development without deploying

The website at `http://127.0.0.1:5173` uses the laptop backend on port 3000. The phone must use that same backend to test local code changes. On a phone, `127.0.0.1` refers to the phone itself unless USB forwarding is configured.

1. In the adjacent `RENT-AND-PLAY` VS Code window, run **Rent & Play: Start App** and leave both servers running.
2. Open a PowerShell terminal in `AndroidFiles` and run `powershell -ExecutionPolicy Bypass -File .\scripts\local-android.ps1`. This detects the laptop's Wi-Fi IPv4 address, verifies its catalog, and starts Flutter with the local API. Keep both devices on the same Wi-Fi.
3. For an installable local test APK, run `powershell -ExecutionPolicy Bypass -File .\scripts\local-android.ps1 -BuildApk -Install`. Connect one authorized Android device over USB to install; the installed Wi-Fi APK can then run without the cable. Its output is `build/app/outputs/flutter-apk/app-local-debug.apk`.

Backend changes only need a backend restart. Web changes use the local web server. Flutter changes use hot reload during `flutter run`, or require another APK build/install when testing an installed APK. These local steps do not need a Git push or Render deployment. Firebase data still uses the configured shared project.

If the laptop's Wi-Fi address changes, rerun the script and reinstall the local APK. Use `-ApiHost <laptop-ip>` to select a particular interface. For a cable connection without Wi-Fi, use `-Connection USB`; it sets up `adb reverse` and points the phone at `http://127.0.0.1:3000/api`. Keep USB connected and rerun after reconnecting. For an emulator, use `-Connection Emulator`.

In an `AndroidFiles` VS Code window, the included **Rent & Play: Android local (USB)** launch configuration also sets up USB forwarding before F5. Start the backend/web in their own VS Code window first. The emulator and hosted Render configurations are separate choices.

## Hosted API and manual commands

The bell opens the rental notification inbox for customers, operators, and owners. New customer booking/return requests alert active `ADMIN` operators and `OWNER` super admins; approval, rejection, release and return decisions alert the booking owner. Tap an update to open that booking, or use **Mark shown as read**. On Android, select **Enable phone alerts** in the inbox to grant notification permission and register background FCM alerts. Sign-out unregisters the phone, and switching accounts rotates the device token. See `../RENT-AND-PLAY/docs/architecture/rental-notifications.md` for deployment and real-device acceptance steps.

The app defaults to `https://rent-and-play.onrender.com/api` when no override is provided. Deploy the matching backend/web changes before using an APK against this hosted address. Local source changes and rebuilding the APK alone do not update that service. To test local backend changes manually:

- From the `RENT-AND-PLAY` folder, start the backend in one terminal: `cd apps/backend` then `npm run dev`.
- In a second terminal, start the web admin: `cd apps/web` then `npm run dev`. Open `http://localhost:5173`; it proxies API requests to the local backend on port 3000.
- Android emulator: `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api`
- Physical Android phone on the same Wi-Fi: `flutter run --dart-define=API_BASE_URL=http://<laptop-ip>:3000/api`

The backend must have its Firebase credentials configured for the same `rent-and-play` project used by the app. Local HTTP access is enabled for debug builds only; release builds continue to use HTTPS.

Run `flutter test test/rental_model_test.dart` for lifecycle, receipt-time, and hardware standby checks. Build an installable test APK with `flutter build apk --debug`; its output is `build/app/outputs/flutter-apk/app-debug.apk`. Use a reachable `API_BASE_URL` when building for a local server. Grant camera permission on the test Android device and check both printed QR labels. Manual lookup requires a reason if a camera is unavailable.

The full flow, hold settings, acceptance steps, and deployment instructions are in the adjacent `RENT-AND-PLAY/docs/architecture/admin-rental-flow.md`.
