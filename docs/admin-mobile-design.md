# Mobile staff workspace

The staff UI is organized around counter work: review a request, prepare a unit,
confirm handoff, receive equipment, and complete inspection.

## Screen hierarchy

- **Counter:** overdue work, quick scan, actionable rental counts, today's
  collections, then equipment, maintenance, and payment tools. Counts open the
  matching queue filter.
- **Rentals / Returns:** one toolbar, search, a horizontally scrolling filter
  row, a compact attention summary, then priority-ordered rental cards. Cards
  show equipment, customer, reference, status, timing, balance, and one next
  action. Existing verification and confirmation screens still handle mutations.
- **Scan:** opens the camera immediately, with Rental QR / Equipment QR mode
  buttons on the scanner. Back returns to the current queue and preserves its
  filter. The main tab remembers the last mode for the app session; queue scan
  buttons start in the relevant mode.
- **Account:** a visible settings menu replaces offscreen tabs. Business
  information is read-only on mobile, as in the current mobile scope; profile
  editing, appearance, security, notifications, and sign-out remain available.
- Workflow explanations are in a Help sheet rather than repeated above every
  queue and inside every card. Contextual timer guidance remains on requested
  returns and pending inspections.

## Visual system

`lib/widgets/staff_ui.dart` owns the staff theme and reusable surfaces, metrics,
action tiles, and help steps. Navy establishes hierarchy; burnt orange identifies
actions; red is reserved for urgent states. Every status also has a text label.
Light and dark appearances share the same layout. Customer routes retain their
existing theme. `StaffPageRoute` carries the staff theme into deeper workflows.

Buttons and icon controls have a minimum 48dp target. Content grows with text
size rather than relying on fixed-height cards or filter rows. Narrow form
fields stack vertically. Main content is capped at 840dp on wide displays.
The scaffold reserves space for bottom navigation, preventing it from covering
the last action. Rental cards are built lazily as the list scrolls.

## References

- [Android: layouts and navigation patterns](https://developer.android.com/design/ui/mobile/guides/layout-and-content/layout-and-nav-patterns)
  informed the stable destination bar, primary action, and secondary overflow actions.
- [Material: canonical layouts](https://m3.material.io/foundations/layout/canonical-examples/overview)
  informed the queue and detail separation.
- [Flutter: accessibility](https://docs.flutter.dev/ui/accessibility)
  informed text scaling, labeled controls, contrast, and touch target sizing.

## Verification

`flutter test --no-pub test/admin_mobile_ui_test.dart` checks navigation from
dashboard counts, search, help and scan sheets, narrow contact fields, 320dp
screens at 200% text, dark mode, and tablet layout. It also writes sample-data
Flutter renders into `build/ui-previews/admin-*.png` for visual inspection.

Existing rental, walk-in, camera, live-update, maintenance, and payment tests
continue to cover operational behavior. No backend contracts, payment rules,
inspection requirements, or receipt-time behavior are changed by this redesign.

General scanning returns the captured code together with its selected mode, so
changing modes also changes the backend lookup. It reuses the existing lookup
API and requires no backend deployment. Changing modes keeps the same camera
session running. Scanning within an assigned-unit or customer verification step
has no mode switch and retains the transaction's existing checks.

The scanner's **Enter code instead** action pauses the camera while the manual
entry dialog is open. Cancelling resumes detection only when the app is in the
foreground. Manual entry is marked as lookup-only and never passed along as
proof of a physical QR scan. Duplicate camera frames produce a single result.

Validation on 7 November 2026:

- Static analysis of all changed Dart files: no issues.
- Focused admin, equipment, customer/staff handoff, scanner, live-update,
  maintenance, and payment suites: **46 tests passed**.
- The full-suite run found seven existing failures in customer registration,
  Home/Browse, and the customer rental tracker. All seven were reproduced
  independently against an isolated export of the original Git HEAD sources
  in `build/admin-ui-baseline`; they are not introduced by this admin redesign.
- The previews contain fixture data, not live customer or payment records.
- `flutter build apk --debug --no-pub` succeeded. The installable result is
  `build/app/outputs/flutter-apk/app-debug.apk`. This build uses the app's existing
  default API configuration and has not been installed on a physical phone.
