# Practice Plans and Live Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver editable offline memorization plans, navigable daily tasks, selected scripture states, live character-level recitation feedback, and persisted statistics.

**Architecture:** Extend the existing SQLite repository with additive migrations and keep scripture source interfaces unchanged. Put text alignment in a pure domain service, keep UI dialogs focused, and let Riverpod provide the single local user repository to plans, dashboard, recitation, and statistics.

**Tech Stack:** Flutter, Dart, Riverpod, go_router, sqlite3, flutter_test, sherpa_onnx.

## Global Constraints

- All recognition and comparison must work without internet access.
- Existing local plans and completed task state must survive schema migration.
- Plan duration is derived inclusively from start date and end date.
- Every behavior change starts with a failing automated test.
- Do not redownload Flutter, Android SDK, JDK, Gradle, or speech models.

---

### Task 1: Plan repository and daily-task behavior

**Files:**
- Modify: `lib/src/features/plans/domain/plan_models.dart`
- Modify: `lib/src/features/plans/data/sqlite_plan_repository.dart`
- Modify: `lib/src/features/dashboard/presentation/today_screen.dart`
- Modify: `test/plans/sqlite_plan_repository_test.dart`
- Create: `test/dashboard/today_screen_test.dart`

**Interfaces:**
- Produces: `updatePlan`, `deletePlan`, `setTaskCompleted`, completed-inclusive `dueTasks`, and `endDate` on plan models.

- [ ] Add repository tests proving inclusive dates, edit/delete, preserved completion, and undo.
- [ ] Run `flutter test test/plans/sqlite_plan_repository_test.dart` and confirm failures are missing APIs/behavior.
- [ ] Add the schema migration and minimal repository implementation.
- [ ] Run the repository test and confirm it passes.
- [ ] Add widget tests proving task-tile navigation and completed-section retention.
- [ ] Implement Today screen grouping, navigation, completion and undo.
- [ ] Run dashboard and plan tests.

### Task 2: Selected scripture state and plan dialogs

**Files:**
- Modify: `lib/src/features/scripture/presentation/book_grid.dart`
- Modify: `lib/src/features/scripture/presentation/chapter_grid.dart`
- Modify: `lib/src/features/scripture/presentation/scripture_browser_screen.dart`
- Modify: `lib/src/features/scripture/presentation/passage_screen.dart`
- Modify: `lib/src/features/plans/presentation/plans_screen.dart`
- Create: `lib/src/features/plans/presentation/plan_editor_dialog.dart`
- Modify: `test/scripture/scripture_browser_screen_test.dart`
- Modify: `test/scripture/passage_screen_test.dart`
- Modify: `test/plans/plans_screen_test.dart`

**Interfaces:**
- Produces: selected book/chapter keys, `PlanEditorDraft`, and reusable editor dialog returning a validated draft.

- [ ] Add failing widget tests for selected-state semantics, add-plan dialog, plan edit and delete controls.
- [ ] Implement selected styles and preserve selection while navigating.
- [ ] Implement the reusable name/book/chapter/date editor with inclusive day calculation.
- [ ] Wire passage add-to-plan and plan create/edit/delete flows.
- [ ] Run all scripture and plans widget tests.

### Task 3: Character alignment and distinct recitation modes

**Files:**
- Create: `lib/src/features/recitation/domain/recitation_alignment.dart`
- Create: `test/recitation/recitation_alignment_test.dart`
- Modify: `lib/src/features/recitation/presentation/recitation_practice_screen.dart`
- Create: `test/recitation/recitation_practice_screen_test.dart`

**Interfaces:**
- Produces: `RecitationAlignment.compare(target, transcript, {finished})`, colored alignment tokens, counts, and accuracy.

- [ ] Add failing pure tests for correct, wrong, omitted, reordered, punctuation, and unfinished text.
- [ ] Implement minimal dynamic-programming alignment and order classification.
- [ ] Run alignment tests and confirm all pass.
- [ ] Add failing widget tests proving verse mode advances one verse and continuous mode aligns the whole passage live.
- [ ] Render colored `TextSpan` output and implement distinct mode state transitions.
- [ ] Run recitation tests.

### Task 4: Persisted statistics and release verification

**Files:**
- Create: `lib/src/features/statistics/domain/recitation_result.dart`
- Modify: `lib/src/features/plans/data/sqlite_plan_repository.dart`
- Modify: `lib/src/features/recitation/presentation/recitation_practice_screen.dart`
- Modify: `lib/src/features/statistics/presentation/statistics_screen.dart`
- Create: `test/statistics/statistics_repository_test.dart`
- Create: `test/statistics/statistics_screen_test.dart`

**Interfaces:**
- Produces: `saveRecitationResult`, `listRecitationResults`, `getRecitationSummary`.

- [ ] Add failing persistence and summary tests.
- [ ] Add the additive result table and repository queries.
- [ ] Save a result exactly once when a session finishes.
- [ ] Render totals, average accuracy, and recent sessions.
- [ ] Run `flutter test` and `flutter analyze`.
- [ ] Build with the remembered local Flutter/SDK/JDK paths using `flutter build apk --release`.
- [ ] Record APK path, byte size and SHA-256.
