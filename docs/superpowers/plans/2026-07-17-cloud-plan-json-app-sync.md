# Cloud Plan JSON App Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two cross-book preset plans, configurable translations, and non-destructive synchronization from a generic public JSON feed, then publish the project and official feed to GitHub.

**Architecture:** Keep Feishu Base as the authoring system and export its pushed rows into a versioned static JSON manifest. The app parses the same bundled manifest for presets and an HTTPS manifest for cloud synchronization. SQLite stores a book on every task plus immutable cloud identity metadata, while local translation and dates remain editable.

**Tech Stack:** Flutter, Dart, Riverpod, sqlite3, `dart:io` HTTPS client, GitHub CLI.

## Global Constraints

- The bundled manifest contains exactly 2 plans, 20 classic passages, and 66 key-verse passages.
- Multi-verse ranges from `每卷书钥节.md` must remain intact.
- A plan task may reference a different book from the preceding task.
- Cloud passage content is read-only; translation and dates remain locally editable.
- Synchronization imports only `push: true` plans and never deletes local plans.
- The source URL is user-configurable and defaults to the official public JSON feed.
- Existing single-book plans and SQLite data must migrate without loss.
- No paid backend is required.

---

### Task 1: Versioned JSON publication manifest

**Files:**
- Create: `tool/cloud_plan/lib/cloud_plan_json.dart`
- Create: `tool/cloud_plan/bin/generate_cloud_plan_json.dart`
- Create: `tool/cloud_plan/test/cloud_plan_json_test.dart`
- Create: `assets/cloud_plans.json`
- Modify: `pubspec.yaml`

**Interfaces:**
- Produces `CloudPlanJsonGenerator.generate(...)` and protocol version 1 JSON with `plans[].passages[]`.

- [ ] Write a failing test asserting protocol version, two pushed plans, exact 20/66 counts, and preserved multi-verse endings.
- [ ] Run `dart test tool/cloud_plan/test/cloud_plan_json_test.dart -r expanded` and confirm it fails because the generator is absent.
- [ ] Implement deterministic JSON generation using the existing Markdown parser and chapter catalog validation.
- [ ] Run the focused test and generate `assets/cloud_plans.json` from the two supplied Markdown files.
- [ ] Re-run all publisher tests.

### Task 2: Cross-book plan persistence and migration

**Files:**
- Modify: `lib/src/features/plans/domain/plan_models.dart`
- Modify: `lib/src/features/plans/data/sqlite_plan_repository.dart`
- Modify: `lib/src/features/plans/domain/plan_draft_builder.dart`
- Modify: `lib/src/features/dashboard/presentation/today_screen.dart`
- Modify: `test/plans/sqlite_plan_repository_test.dart`
- Modify: `test/dashboard/today_screen_test.dart`

**Interfaces:**
- `NewPlanTask.bookId` and `PlanTask.bookId` identify each task's book.
- `MemorizationPlan.sourceKind`, `sourceUrl`, `externalId`, `revision`, and `contentLocked` expose cloud provenance.

- [ ] Add failing repository tests for cross-book tasks, legacy migration, cloud metadata, and uniqueness by source URL plus external ID.
- [ ] Run focused tests and confirm failures identify the missing fields/schema.
- [ ] Add idempotent SQLite migrations, persist the fields, and use task book IDs in Today navigation.
- [ ] Run repository and Today tests until green.

### Task 3: Manifest parser, scheduler, and non-destructive synchronizer

**Files:**
- Create: `lib/src/features/plans/domain/cloud_plan_manifest.dart`
- Create: `lib/src/features/plans/domain/cloud_plan_importer.dart`
- Create: `lib/src/features/plans/data/cloud_plan_feed_client.dart`
- Create: `test/plans/cloud_plan_manifest_test.dart`
- Create: `test/plans/cloud_plan_importer_test.dart`

**Interfaces:**
- `CloudPlanManifest.parse(String)` validates protocol 1 and passage ranges.
- `CloudPlanImporter.importPushed(...)` inserts or revises pushed plans without deleting absent/unpublished local plans.
- `CloudPlanFeedClient.fetch(Uri)` returns validated manifest JSON over HTTPS with bounded timeout and size.

- [ ] Write failing parser tests for valid bundled data, malformed ranges, and unsupported protocols.
- [ ] Implement the minimal immutable manifest model and parser, then make the tests pass.
- [ ] Write failing importer tests for cross-book scheduling, duplicate sync, revision update, preserved local dates/translation, and non-deletion.
- [ ] Implement importer and repository upsert behavior, then make focused tests pass.
- [ ] Add feed-client tests using an injected byte loader and implement HTTPS/size/error handling.

### Task 4: Two presets, translation/date editing, cloud settings and badges

**Files:**
- Modify: `lib/src/features/plans/application/plan_providers.dart`
- Modify: `lib/src/features/plans/presentation/plan_editor_dialog.dart`
- Modify: `lib/src/features/plans/presentation/plans_screen.dart`
- Modify: `test/plans/plan_editor_dialog_test.dart`
- Modify: `test/plans/plans_screen_test.dart`

**Interfaces:**
- Presets are loaded from bundled `assets/cloud_plans.json`.
- Settings persist `cloud_plan_source_url`; the sync action imports pushed plans and reports inserted/updated/unchanged counts.

- [ ] Change widget tests first to require exactly the two named presets, a translation dropdown, locked cloud content, a cloud badge, URL setting, and sync action.
- [ ] Run focused widget tests and confirm the expected failures.
- [ ] Implement preset loading, a reusable template configuration dialog, translation/date editing, cloud source settings, and sync feedback.
- [ ] Run focused widget tests until green.

### Task 5: Full verification and GitHub publication

**Files:**
- Modify: `.gitignore`
- Create: `assets/models/README.md`
- Create: `README.md`

**Interfaces:**
- Private code repository: `kobe24o/bible_recite`.
- Public feed repository: `kobe24o/bible-recite-plans`, containing `cloud-plans.json`.
- Default app URL: `https://raw.githubusercontent.com/kobe24o/bible-recite-plans/main/cloud-plans.json`.

- [ ] Exclude the 181 MB model binaries from ordinary Git history and document their local installation/build path.
- [ ] Run `dart test tool/cloud_plan/test -r expanded`, full `flutter test`, `flutter analyze`, and a release APK build.
- [ ] Review `git diff --check`, staged scope, and secret scan before committing.
- [ ] Re-authenticate `gh`, create the private code repo and public feed repo, push the code branch/default branch and feed data.
- [ ] Verify both remote repositories and anonymously fetch/parse the public feed URL.
