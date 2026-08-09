# Quiz and Review Plan Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task by task.

**Goal:** Correct quiz speech scoring and entry feedback, make quiz configuration validation explicit, and replace global Ebbinghaus management with an independent setting and review plan for each memorization plan.

**Architecture:** Keep existing recitation and quiz models intact where possible. Add a plan-level Ebbinghaus flag and a source-plan foreign key to review cycles, migrate recoverable legacy cycles, and expose review data through repository/domain/UI layers. Quiz answer persistence becomes idempotent so repeated completion calls never duplicate metrics.

**Tech Stack:** Flutter/Dart, SQLite migrations, repository/domain presentation layers, Flutter widget tests.

## Global Constraints

- Preserve existing recitation behavior and independent recitation/quiz metrics.
- Ebbinghaus cycles are created only for successful recitations that came from a memorization plan whose own switch is enabled.
- Never create an `other` grouping for recitations outside a plan; source-less legacy cycles are canceled during migration.
- Keep exact stored verse ranges for every review; do not expand a review to a full chapter.
- A quiz model request requires nonempty endpoint, model ID, and API key. Missing configuration is reported before any request.
- A completed quiz question may be submitted again without an exception, and must contribute to statistics only once.

## Task 1: Make Mandarin scoring and persisted quiz completion robust

**Files:**

- Modify: `lib/src/features/quiz/application/mandarin_phonetic_comparator.dart`
- Modify: `lib/src/features/quiz/presentation/quiz_practice_screen.dart`
- Modify: `lib/src/features/plans/data/sqlite_plan_repository.dart`
- Modify: `lib/src/features/plans/domain/plan_repository.dart`
- Test: `test/quiz/mandarin_phonetic_comparator_test.dart`
- Test: `test/quiz/quiz_practice_screen_test.dart`
- Test: `test/plans/sqlite_plan_repository_test.dart`

1. Add a comparison helper that accepts a correct answer when its normalized per-character pinyin sequence is a contiguous match in the recognized sequence; retain the final-nasal preference in normalization.
2. Use this helper for Chinese quiz scoring, while keeping non-Chinese scoring unchanged.
3. Change `completeQuizQuestion` so an already answered row returns its recorded completion state and current summary instead of throwing; never insert a second `quiz_result` or change streak counters.
4. Add tests for `耶和华` being accepted within `耶稣耶和华`, final-nasal configuration, and double completion remaining one recorded answer.

## Task 2: Validate configuration before generation and surface Today-task failures

**Files:**

- Modify: `lib/src/features/quiz/domain/quiz_model_settings.dart`
- Modify: `lib/src/features/quiz/application/quiz_generation_service.dart`
- Modify: `lib/src/features/recitation/presentation/recitation_practice_screen.dart`
- Modify: `lib/src/features/recitation/application/plan_recitation_builder.dart`
- Test: `test/quiz/quiz_generation_service_test.dart`
- Test: `test/recitation/recitation_practice_screen_test.dart`
- Test: `test/recitation/plan_recitation_builder_test.dart`

1. Make `isConfigured` require API endpoint, model ID, and API key, with a reusable human-readable missing-configuration message.
2. Return a typed preparation failure before loading/requesting the model when configuration is incomplete.
3. Retain quiz preparation failure information in the recitation screen instead of swallowing it; after a planned recitation succeeds, open the prepared quiz when ready, otherwise show the specific reason and preserve the recitation result.
4. Confirm the Today-task selected item supplies the whole-plan quiz scope and add regression coverage for both ready and unready generation paths.

## Task 3: Repair custom-plan validation and selected-scripture plan date editing

**Files:**

- Modify: `lib/src/features/plans/presentation/plan_editor_dialog.dart`
- Modify: `lib/src/features/scripture/presentation/passage_screen.dart`
- Modify: `lib/src/features/plans/application/plan_draft_builder.dart`
- Test: `test/plans/plan_editor_dialog_test.dart`
- Test: `test/scripture/passage_screen_test.dart`
- Test: `test/plans/plan_draft_builder_test.dart`

1. Split empty-passage validation from title/date validation so a custom plan without passages shows exactly `请添加经文`.
2. Route long-press scripture selection through the same draft/build pipeline used by the plan editor, preserving the exact selected ranges.
3. Reproduce and fix editing a selection-created plan's dates, then add widget/domain regression coverage for create, edit dates, and save.

## Task 4: Add per-plan Ebbinghaus storage and safe migration

**Files:**

- Modify: `lib/src/core/database/app_database.dart`
- Modify: `lib/src/features/plans/data/sqlite_plan_repository.dart`
- Modify: `lib/src/features/plans/domain/memorization_plan.dart`
- Modify: `lib/src/features/plans/domain/ebbinghaus_review.dart`
- Modify: `lib/src/features/plans/domain/plan_repository.dart`
- Test: `test/review/ebbinghaus_repository_test.dart`
- Test: `test/plans/sqlite_plan_repository_test.dart`

1. Bump the database version and add `memorization_plan.ebbinghaus_enabled` with a non-null default of false, plus nullable `ebbinghaus_cycle.source_plan_id` referencing `memorization_plan`.
2. During migration, initialize legacy plan flags from the old global enabled setting; map each old cycle through `recitation_result.plan_id`; cancel source-less cycles and their pending reviews without deleting recitation statistics.
3. Update plan creation, read, update, and copy paths for the new flag.
4. Update successful recitation processing to create a cycle only when `result.planId` exists and that plan has Ebbinghaus enabled. Persist `source_plan_id` with every cycle.
5. Replace range-based pause/resume queries with source-plan-ID queries, preserving all exact cycle ranges.
6. Add migration, planned-recitation, standalone-recitation, pause/resume, and exact-range tests.

## Task 5: Build independent review-plan management UI and per-plan setting controls

**Files:**

- Modify: `lib/src/features/plans/presentation/plans_screen.dart`
- Modify: `lib/src/features/plans/presentation/plan_editor_dialog.dart`
- Modify: `lib/src/features/settings/presentation/settings_screen.dart`
- Modify: `lib/src/features/recitation/application/plan_recitation_builder.dart`
- Create: `lib/src/features/review/presentation/review_plan_detail_screen.dart`
- Modify: `lib/src/app/router.dart`
- Test: `test/plans/plans_screen_test.dart`
- Test: `test/review/review_plan_detail_screen_test.dart`
- Test: `test/settings/settings_screen_test.dart`

1. Rename the existing plan section to `我的背诵计划`, and add `我的复习计划（艾宾浩斯）` containing one review-plan card per source memorization plan with active/pause status and next review details.
2. Add a detail page that lists each scheduled review by day number, status/pass result, scheduled date, and exact scripture range; route both highlight reading and recitation through those stored ranges.
3. Add pause/resume for an individual review plan. `再次执行` opens the original plan's exact ranges for recitation; a new passing result creates a new cycle under that same plan rather than cloning old records.
4. Move the global Ebbinghaus enable control out of Settings. Keep only global review threshold settings there, and make plan-level enable switches available in plan edit/manage UI.
5. Ensure disabled plans neither generate new cycles nor show an unrelated source-less grouping.

## Task 6: Update labels, tests, documentation, and release verification

**Files:**

- Modify: all accuracy-label call sites found by `rg "准确率" lib test`
- Modify: `README.md`
- Modify: release/update notes file used by the project
- Test: focused quiz, recitation, plans, review, settings, scripture suites

1. Rename ambiguous labels to `背诵准确率` or `答题准确率` consistently, including map drill-down and profile summaries.
2. Add an update note explaining the new per-plan review switch, no standalone review bucket, voice-answer tolerance, and clearer quiz configuration errors.
3. Run formatter, focused tests, complete `flutter analyze`, and complete `flutter test` using `.toolchains\\flutter\\bin\\flutter.bat`.
4. Inspect `git diff`, confirm no credentials were committed, then build/release only after the implementation and verification pass.

## Execution Order

1. Tasks 1 and 2 establish quiz correctness and entry behavior.
2. Task 3 fixes plan authoring before new plan fields/UI are added.
3. Task 4 introduces the migration and repository contract.
4. Task 5 consumes the new contract in the UI.
5. Task 6 performs broad regression verification and documentation/release work.

## Plan Review

- Covered every requested behavior: scoring, entry, configuration, plan editing/validation, per-plan Ebbinghaus, idempotency, and label clarity.
- No placeholder tasks remain; each task names concrete source and test files.
- Database migration precedes UI work, so legacy data is handled before new controls expose it.
