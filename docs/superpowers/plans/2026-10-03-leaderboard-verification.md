# Leaderboard verification — 2026-10-03

Baseline: `3834c30cec9f6b8741a5504daa88106d14f96a10`, branch `codex/release-repeatable-achievements`.

## Implementation ledger

- Task 1: upstream domain and aggregate tests retained; rerun passed (2 tests).
- Task 2: build defines, safe persistent installation aliases, pinned Supabase SDK and device-model dependency implemented; configuration/alias tests RED → GREEN.
- Task 3: generated migration `20261003050608_leaderboard.sql`, own-row RLS, guarded submit RPC, seven-metric read RPC, indexes and pgTAP assertions supplied. Local Supabase pgTAP and advisors unavailable (Postgres `127.0.0.1:54322` refused connection). An isolated PGlite 0.3.14 embedded PostgreSQL smoke check with emulated `auth.users`/`auth.uid()` successfully executed the migration and checked monotonic guards, current-streak/accuracy decreases, invalid values, own-row RLS, raw-write denial, metric allowlist, top limit plus caller outside top, zero-answer exclusion, authentication and anon denial. This does not validate real Supabase Auth, PostgREST or advisors.
- Task 4: injectable gateway/transport, anonymous session reuse, complete aggregate RPC payload, durable per-metric caches, 15-minute throttle, refresh override, offline fallback and concurrent-write preservation implemented; controller/transport tests RED → GREEN.
- Task 5: durable notifications at successful SQLite writes for recitation, quiz, plan completion, profile name and new awards; launch/resume and periodic maintenance; write/lifecycle tests RED → GREEN. Day-sensitive current streak is recalculated even without a new learning event.
- Task 6: My entry, route, seven selectors, caller highlight, local summary, cache timestamps, unavailable/empty states, pull-to-refresh; widget/route tests RED → GREEN.
- Task 7: configuration and verification instructions in README. Configured real-project smoke remains intentionally unperformed.

## Automated results before final review

- Flutter 3.44.9, Dart 3.12.2, Supabase CLI 2.119.0.
- `flutter pub get`: exit 0. Existing locked packages (including `test: 1.31.0`) remain unchanged; 27 feature dependencies added.
- `TZ=UTC flutter test --no-pub test/leaderboard test/statistics/statistics_screen_test.dart test/app/app_navigation_test.dart --reporter expanded`: 51 passed.
- `TZ=UTC flutter test --no-pub --reporter expanded`: 495 passed, 1 skipped (existing Zhipu live integration test requires `ZHIPU_API_KEY`), exit 0.
- `flutter analyze`: exit 1 solely for 17 pre-existing info-level diagnostics in untouched plans/quiz/update/tool files; no errors/warnings introduced. `flutter analyze --no-fatal-infos`: exit 0. `flutter analyze lib/src/features/leaderboard test/leaderboard`: no issues, exit 0.
- UTC avoids pre-existing devotion test fixture duplication across DST; two navigation tests initially failed under the cloud default DST timezone, then passed under UTC without unrelated code changes.

## Rulings and practical costs

1. Use compatible Flutter 3.44.9/Dart 3.12.2; preserve `test: 1.31.0` and other upstream versions. Existing CI 3.47.3 is incompatible with the original test pin; owner must separately reconcile CI/toolchain.
2. Real project/database access is prohibited. Supply migrations/tests and isolated SQL smoke; actual Supabase deployment, pgTAP/advisors and auth/HTTP integration remain pending.
3. Public SECURITY INVOKER RPC wrappers delegate privilege elevation to private functions; direct raw writes are forbidden. `leaderboard_private` must stay outside the Data API exposed schemas.
4. Use device_info_plus 12.4.0 instead of planned 13.3.0, to preserve package_info_plus 9.0.1/win32 5.x. Newer device plugin APIs are unavailable.
5. Notify at SQLite mutation boundaries instead of repeating notifications in presentation screens. The repository owns leaderboard metadata keys; these cover callers and transactions with no network in writes.
6. Keep pre-existing info diagnostics and DST-sensitive fixtures untouched, respecting feature scope. Default strict analyze remains nonzero until unrelated diagnostics are cleaned up.

## Real project handoff

Need project URL, publishable (or legacy anon) key supplied in the owner's build environment; anonymous sign-ins enabled; migration applied by an administrator; public RPCs exposed and private schema not exposed; anonymous-auth/RPC rate-limit policy; CAPTCHA token integration if CAPTCHA is enabled. No service-role key belongs in the client. No real project has been connected, no keys written, no release or PR created.
