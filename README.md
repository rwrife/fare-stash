# Fare Stash

Offline transit pass journal: track passes, manually log rides and remaining trips, and export travel records across phone, tablet, and Windows.

## Why / for whom

Commuters, frequent travelers, and transit riders juggling multiple regional travel passes, monthly cards, stored-value tickets, and multi-ride punch cards need a reliable offline journal. Cloud transit and wallet apps often require accounts, real-time geolocation, bank logins, or supported smart-card readers; physical paper tickets, foreign transit passes, regional commuter rail cards, and family transit balances get lost or expire unexpectedly. `fare-stash` provides a private, manual single-device workspace to log card limits, count down multi-ride allocations, record trips, flag expiration dates, and export trip history.

## Intended workflow

1. Add a transit pass or ticket with user-entered parameters: agency name, pass type (time-based monthly/weekly, multi-trip ride pack, or stored-value currency balance), purchase date, expiration date, cost, and starting balance or ride count.
2. Log rides manually with one tap: select pass, record timestamp, optional line/route/station tag, and ride fare or trip deduction.
3. Review glanceable status: active passes sorted by urgency, remaining trips or balance, days until expiration, and cost-per-ride summary.
4. Filter and inspect history: filter trips by pass or date range, check travel expenses for reimbursement or tax records, and spot expired or depleted passes.
5. Backup and export: export structured JSON and CSV records directly to the local filesystem without external server dependencies.

## MVP / limits

- Core domain: passes/cards (pass title, transit authority, pass category, validity window, initial/remaining ride units or currency, active/archived state) and ride events (pass reference, timestamp, departure/destination tags, unit deduction, notes).
- Explicit non-goals: no live transit tracking, GTFS real-time feeds, NFC card balance scanning, payment processing, ticket purchasing, account logins, GPS location tracking, or cloud backup.
- Failure resilience: database migrations must preserve user-entered history; invalid trip entries (e.g. negative deduction or future date anomalies) must surface validation errors without corrupting the pass state.

## Platforms and privacy

Built as a single Flutter codebase targeting Windows 10/11, Android, and iOS (both phones and tablets fully supported). Input supports touch, mouse, keyboard navigation, dynamic window resizing, and accessibility screen readers. All storage uses a local SQLite database with zero telemetry, zero analytics, zero network requests, and zero advertising SDKs.

Identifier convention: `com.infinityball.farestash` for Android applicationId, iOS bundle ID, and Windows MSIX identity.

UX strategy A (Platform-native adaptive):
- iOS / iPadOS: Cupertino design language, SF-style typography, modal sheets, and standard navigation bars.
- Android: Material 3 styling with system navigation gestures and bottom sheets.
- Windows: Fluent-style desktop workspace with navigation rails, keyboard accelerators, and desktop-density layouts. Never show a phone UI on Windows or a desktop UI on a phone.

## Status / milestones

Flutter 3.47.7 Windows/Android/iOS runners, an offline SQLite pass ledger, and manual pass/ride workflows are implemented. The adaptive pass list and history use Cupertino controls on iOS/iPadOS, Material 3 on Android, and Fluent controls and a persistent desktop navigation pane on Windows. Milestone roadmap:
1. Issue #1: Flutter skeleton, multi-platform runner config, and GitHub Actions CI.
2. Issue #2: Pure Dart domain models, pass/ride state transitions, and unit tests.
3. Issue #3: SQLite persistence layer, migrations, and local storage tests.
4. Issue #4: Pass management, ride deduction logging, and balance calculation workflows.
5. Issue #5: Adaptive multi-platform UI (Cupertino, Material 3, Fluent) and golden/widget tests.
6. Issue #6: Local JSON backup and CSV export with privacy audit.
7. Issue #7: Release workflow, store description, and spark-media icon asset pipeline.

### Adaptive workspace

Phones switch between passes and history with platform-native navigation. Android tablets use a navigation rail; at 900 logical pixels and above, passes and history appear side by side. Windows retains its compact desktop navigation pane even in narrow windows and expands the pane at 1100 logical pixels. Each pass also opens its own history page with native back navigation, including the iOS edge-swipe gesture.

Controls support keyboard traversal and mouse hover; Ctrl+N (Command+N) opens Add pass. Headings and action names are exposed to screen readers, errors are live regions, text follows system scaling, and platform light/dark and high-contrast themes are respected. Windows high contrast uses dark surfaces with a yellow accent.

Run `flutter test test/adaptive_test.dart test/app_test.dart` for platform-isolated rendering, resizing, accessibility, and workflow checks. Screenshot assertions render iOS, Android, and Windows at 390×844, 768×1024, and 1440×900, verify opaque/nonempty output and native shell/layout geometry, and write PNGs to `build/adaptive-screenshots/` for inspection. These are rendering assertions rather than pixel-perfect baseline goldens; native-device VoiceOver/TalkBack/Narrator verification remains a manual release check.

`AppStore/description.txt` provides accurate planning copy. The real `AppStore/icon.png` is generated via OpenAI Images using `~/.local/bin/spark-media --project fare-stash image --prompt "..."` and wired into Windows/Android/iOS icon sets; no placeholder icon is accepted as complete.

## Build quickstart (after issue #1)

Install Flutter stable SDK (pinned in `toolchain.json`).
```bash
flutter pub get
flutter test
flutter run -d windows
```
Linux verification runs in Docker containers (`docker run --rm -v "$PWD:/work" ...`). The Windows release build runs on GitHub Actions `windows-latest` via `.github/workflows/release.yml` on `v*` tags, producing a zipped release bundle attached to GitHub Releases. iOS TestFlight and Android Play submissions remain deferred milestones.

## Manual setup required

App Store Connect bundle identifier `com.infinityball.farestash` registration failed: `FAILED bundleId lookup rejected: FORBIDDEN_ERROR.PLA_NOT_ACCEPTED`. The account owner must accept the latest Apple Developer Program License Agreement in the Apple Developer portal, then rerun registration. Four ASC repository secrets (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID`) are already configured.
