# Leaderboard verification — 2026-10-03

Baseline: `3834c30cec9f6b8741a5504daa88106d14f96a10`, branch `codex/release-repeatable-achievements`.

## Implementation ledger

- Task 1: upstream domain and aggregate tests retained; rerun passed (2 tests).
- Task 2: build defines, safe persistent installation aliases, pinned Supabase SDK and device-model dependency implemented; configuration/alias tests RED → GREEN.
- Task 3: generated migration `20261003050608_leaderboard.sql`, own-row RLS, guarded submit RPC, seven-metric read RPC, indexes and pgTAP assertions supplied. Local Supabase pgTAP and advisors unavailable (Postgres `127.0.0.1:54322` refused connection). An isolated PGlite 0.3.14 embedded PostgreSQL smoke check with emulated `auth.users`/`auth.uid()` successfully executed the migration and checked monotonic guards, current-streak/accuracy decreases, invalid values, own-row RLS, raw-write denial, metric allowlist, top limit plus caller outside top, zero-answer exclusion, authentication and anon denial. This does not validate real Supabase Auth, PostgREST or advisors.
- Task 4: injectable gateway/transport, anonymous session reuse, complete aggregate RPC payload, durable per-metric caches, 15-minute throttle, refresh override, offline fallback and concurrent-write preservation implemented; controller/transport tests RED → GREEN.
- Task 5: durable notifications at successful SQLite writes for recitation, quiz, plan completion, profile name and new awards; launch/resume and periodic maintenance; write/lifecycle tests RED → GREEN. Day-sensitive current streak is recalculated even without a new learning event.
- Task 6: My entry, route, seven selectors, caller highlight, local summary, cache timestamps, unavailable/empty states, pull-to-refresh; widget/route tests RED → GREEN.
- Task 7: configuration and verification instructions in README. Real-project anonymous-auth/read-RPC smoke completed on 2026-10-03; score submission remains deliberately untested to avoid leaving fabricated public leaderboard records.

## Automated results

- Flutter 3.44.9, Dart 3.12.2, Supabase CLI 2.119.0.
- `flutter pub get`: exit 0. Existing locked packages (including `test: 1.31.0`) remain unchanged; 27 feature dependencies added.
- `TZ=UTC flutter test --no-pub test/leaderboard test/statistics/statistics_screen_test.dart test/app/app_navigation_test.dart --reporter expanded`: 52 passed.
- `TZ=UTC flutter test --no-pub --reporter expanded`: 496 passed, 1 skipped (existing Zhipu live integration test requires `ZHIPU_API_KEY`), exit 0.
- `flutter analyze`: exit 1 solely for 17 pre-existing info-level diagnostics in untouched plans/quiz/update/tool files; no errors/warnings introduced. `flutter analyze --no-fatal-infos`: exit 0. `flutter analyze lib/src/features/leaderboard test/leaderboard`: no issues, exit 0.
- UTC avoids pre-existing devotion test fixture duplication across DST; two navigation tests initially failed under the cloud default DST timezone, then passed under UTC without unrelated code changes.

## Real Supabase smoke — 2026-10-03

- The configured project has Anonymous Sign-ins enabled (`anonymous_users: true`).
- The deployed `get_leaderboard` RPC rejects an unauthenticated caller, as intended. A parameterless call is not a valid existence check because `metric` is required.
- A fresh anonymous session successfully called `get_leaderboard` with `metric: total_sessions` and `limit_count: 1`: HTTP 200 with a JSON `entries` array.
- No `submit_leaderboard_snapshot` request was made in the real project, so no fabricated leaderboard score was added. The guarded-write path remains covered by the isolated SQL smoke and Flutter transport/controller tests; it should be exercised with genuine app learning data before a production release.
- The cloud CLI session cannot persist its login across processes, so real-project `supabase test db` and `supabase db advisors` were not run. No client secret or service-role key was used.

## Rulings and practical costs

1. Use compatible Flutter 3.44.9/Dart 3.12.2; preserve `test: 1.31.0` and other upstream versions. Existing CI 3.47.3 is incompatible with the original test pin; owner must separately reconcile CI/toolchain.
2. The real project is connected only through its publishable client configuration. Anonymous authentication and the read RPC are live-verified; administrator-only CLI database tests/advisors remain pending because the cloud CLI login is not persistent.
3. Public SECURITY INVOKER RPC wrappers delegate privilege elevation to private functions; direct raw writes are forbidden. `leaderboard_private` must stay outside the Data API exposed schemas.
4. Use device_info_plus 12.4.0 instead of planned 13.3.0, to preserve package_info_plus 9.0.1/win32 5.x. Newer device plugin APIs are unavailable.
5. Notify at SQLite mutation boundaries instead of repeating notifications in presentation screens. The repository owns leaderboard metadata keys; these cover callers and transactions with no network in writes.
6. Keep pre-existing info diagnostics and DST-sensitive fixtures untouched, respecting feature scope. Default strict analyze remains nonzero until unrelated diagnostics are cleaned up.

7. Combine cache/controller and SQLite write-hook work in one commit, while keeping UI/lifecycle work separate. Commit boundaries differ from the suggested per-task sequence; functionality and test coverage remain traceable.

## Final independent review

Verdict: With fixes. Both findings addressed; no minor findings deferred.

- Important: reproduced lost pending changes when a local write occurred between the asynchronous revision read and dirty-marker cleanup. Added a regression spanning 16 microtask interleavings (RED at two microtasks), then replaced read-and-clear with one conditional SQLite UPDATE (GREEN).
- Minor: background maintenance now invalidates the last-sync provider so My updates its synchronization timestamp without another learning event.
- Final full test/analyzer checks were rerun after these fixes. The deployed Auth/PostgREST read path is verified separately; embedded SQL checks remain distinct from administrator CLI tests and an intentional real-score submission.

## Real project handoff

For a device build, supply the project URL and publishable (or legacy anon) key through the documented Dart defines. Keep `leaderboard_private` outside exposed schemas, set anonymous-auth/RPC rate limits, and add CAPTCHA token handling if CAPTCHA is enabled. No service-role key belongs in the client. Before a production release, validate the guarded submit RPC through genuine app learning data and run the administrator CLI tests/advisors from a persistently authenticated environment. No release or PR was created.
