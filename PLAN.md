# Fare Stash — implementation plan

## Scope and architecture

Flutter stable, Dart single codebase, Windows/Android/iOS runners. `com.infinityball.farestash` across Android applicationId, iOS bundle ID, Windows MSIX identity where applicable. Enabled native iPad and Android tablet support. No server. Pure Dart immutable domain functions compute pass state from starting units and timestamped ride deductions; SQLite stores append-only ride events and pass definitions with versioned migrations. JSON backup round-trip preserves event IDs and timestamps; CSV export is read-only. No remote APIs.

A ride pack counts integral trips; stored-value passes store integer minor currency units, currency code, and explicit user-entered deduction per ride; time-based passes track validity dates but never infer automatic fare deductions. Prevent overdrawing, negative inputs, duplicate imported event IDs, and incompatible currency arithmetic. User chooses correction via reversal/new event, not destructive history rewrite. System clock changes do not silently mutate recorded events.

## Platform-authentic UX strategy A

Small adaptive widget layer for shared pass lists, pass detail, logging forms and dialogs. Cupertino on iOS/iPadOS, Material 3 on Android, Fluent design on Windows. Never Material look on iOS, Cupertino on Android, or phone UI on Windows. Native back behavior, platform-specific date pickers, safe areas, scroll physics, text scaling and focus traversal. On phones: simple bottom/tab navigation; tablets: split pane; Windows: resizeable navigation view, mouse hover, keyboard shortcuts and context menu. Widget/golden tests for `TargetPlatform.iOS`, `TargetPlatform.android`, and `TargetPlatform.windows`, covering phone (390px), tablet (800px), and desktop (1200px) layouts.

## Milestones and dependencies

1. Flutter project skeleton, `windows/`, `android/`, `ios/`, pinned `toolchain.json`, GitHub Actions Windows CI (test + `flutter build windows --release`), Android debug APK in Linux/Docker CI. Keep iOS compiling on macOS lane when runner available; do not claim Linux checks prove iOS builds.
2. Pure Dart pass/ride domain with deterministic unit tests for ride count, currency balance, expiration and correction.
3. SQLite schema/migration tests and transactional import/recovery (depends on #2).
4. Pass setup and manual ride logging including conflict/validation feedback (depends on #3).
5. Adaptive platform-native UI and accessibility/golden checks (depends on #4).
6. JSON restore/export and CSV trip export with redacted support examples (depends on #3 and #4).
7. Actual OpenAI Images icon (via spark-media), platform icon wiring, listing-copy review, Windows release workflow (depends on #1 and #5).

## Testing and release

Run `flutter test` on Windows with platform goldens and on Linux inside pinned Flutter Docker. `flutter build windows --release` on `windows-latest`; `flutter build apk --debug` in Linux/Docker CI. Dedicated macOS iOS compile check when available. Test data migrations, failed imports, integer balance arithmetic, time boundaries, and backup/restore fidelity. Accessibility: full keyboard navigation on Windows, screen reader labels, scalable text and high contrast.

`.github/workflows/release.yml` triggers on `v*` tags/manual dispatch: `windows-latest` produces zipped portable release and attaches it to GitHub Release. TestFlight and Play are later opt-in milestones using existing secret names ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, ASC_TEAM_ID; no secret values in logs. AppStore/description.txt must match shipped features. AppStore/icon.png generated from OpenAI Images via spark-media, inspected, then installed into Windows .ico runner and Android/iOS launcher asset sets; no placeholder. ASC registration currently blocked by `FAILED bundleId lookup rejected: FORBIDDEN_ERROR.PLA_NOT_ACCEPTED` and needs account-owner agreement acceptance.

## Risks and non-goals

Manual pass balances can differ from transit operator systems; show "user-entered estimate" and never present as authoritative fare or valid ticket. Expiration is based on entered dates and device clock, not agency status. Currency-specific integer minor units avoid rounding loss; no exchange rate conversion. Local SQLite/JSON backups need export guidance; user owns export copies. No NFC reading, automated fare detection, purchasing, GPS, live arrival info, ticket validation, subscription, or cloud sync.
