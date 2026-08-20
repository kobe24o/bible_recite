# Quiz Bank Quality v3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a dictionary-backed, quality-v3 quiz snapshot and atomically replace the local active bank without losing historical quiz results.

**Architecture:** `bible-recite-plans` owns the lexicon, deterministic quality tools and stable snapshot publisher. `bible_recite` parses the replacement snapshot metadata, stages all validated shards and activates them in one SQLite transaction.

**Tech Stack:** Python 3, Jieba 0.42.1 for publishing-only audit, JSON, SQLite, Dart, Flutter, flutter_test.

**Spec:** `docs/superpowers/specs/2026-08-21-quiz-bank-quality-v3-design.md`

## Global Constraints

- Every shard is below 10 MiB and a stable snapshot increments its global revision exactly once.
- Freeze generation while assembling and publishing a quality snapshot.
- A question must use an original UTF-16 slice, a full lexical boundary, a non-overlapping position and a specific answer-free meaning.
- The effective per-verse count is the lesser of five, its length target and qualified non-overlapping candidates; never add filler.
- A failed shard leaves the active bank untouched.
- A completed replace deletes all current/imported questions, but preserves result, accuracy, streak and achievement inputs.

---

### Task 1: Build the versioned Bible lexicon

**Files:**
- Create: `bible-recite-plans/lexicon/bible_terms.v1.json`
- Create: `bible-recite-plans/lexicon/meaning_rules.v1.json`
- Create: `bible-recite-plans/requirements-quality.txt`
- Create: `bible-recite-plans/tools/quiz_lexicon.py`
- Test: `bible-recite-plans/tools/test_quiz_lexicon.py`

**Interfaces:** `load_terms(Path) -> tuple[LexiconTerm, ...]`, `find_overlapping_terms(text, start, end, terms) -> list[LocatedTerm]`, `target_question_limit(text) -> int`.

- [ ] **Step 1: Write the failing tests**

```python
def test_suffix_candidate_finds_complete_israel_term() -> None:
    found = find_overlapping_terms("以色列人出埃及", 1, 3, TERMS)
    assert [(item.term.term, item.start, item.end) for item in found] == [("以色列", 0, 3)]

def test_target_count_is_capped_at_five() -> None:
    assert target_question_limit("短句") == 1
    assert target_question_limit("甲" * 120) == 5
```

- [ ] **Step 2: Run the test and verify RED**

Run: `python tools/test_quiz_lexicon.py`

Expected: `ModuleNotFoundError: No module named 'quiz_lexicon'`.

- [ ] **Step 3: Implement the lexicon and helper module**

Add JSON records with `term`, `aliases`, `kind`, `meaning` and `source`; seed `以色列` with `雅各后裔形成的民族及其国家称谓`, and `法利赛人` with `犹太教中重视律法传统的宗教群体成员`. Add `jieba==0.42.1`. The helper loads custom terms into Jieba only for audit, returns all overlapping full terms in UTF-16 offsets, and applies length targets: 1 under 20 CJK characters, 2 at 20-39, 3 at 40-69, 4 at 70-99, and 5 at 100+.

- [ ] **Step 4: Verify GREEN and commit**

Run: `python tools/test_quiz_lexicon.py`

Expected: suffix, pronoun-prefix, and every length-band test pass. Commit only the five files listed above with message `feat: add versioned Bible term lexicon`.

### Task 2: Audit and deterministically repair bad words and meanings

**Files:**
- Create: `bible-recite-plans/tools/audit_quiz_bank_quality.py`
- Create: `bible-recite-plans/tools/repair_quiz_bank_quality.py`
- Modify: `bible-recite-plans/tools/validate_quiz_bank.py`
- Test: `bible-recite-plans/tools/test_audit_quiz_bank_quality.py`
- Test: `bible-recite-plans/tools/test_repair_quiz_bank_quality.py`

**Interfaces:** `audit_questions(questions, scripture, terms, rules) -> list[QualityFinding]`; `repair_questions(questions, scripture, terms, rules) -> RepairResult`.

- [ ] **Step 1: Write failing repair tests**

```python
def test_partial_name_is_critical() -> None:
    findings = audit_questions([question("色列", 1, 3)], {"GEN:1:1": "以色列人"}, TERMS, RULES)
    assert [(item.severity, item.code) for item in findings] == [("critical", "partial_lexicon_term")]

def test_unambiguous_fragment_is_repaired() -> None:
    result = repair_questions([question("们法", 1, 3)], {"MAT:23:1": "你们法利赛人"}, TERMS, RULES)
    assert result.published[0]["word"] == "法利赛人"
    assert result.published[0]["meaning"] == "犹太教中重视律法传统的宗教群体成员"

def test_bare_generic_meaning_is_removed() -> None:
    assert repair_questions([question("城", 0, 1, meaning="地名")], {"GEN:1:1": "城"}, TERMS, RULES).published == []
```

- [ ] **Step 2: Run tests and verify RED**

Run: `python tools/test_audit_quiz_bank_quality.py` and `python tools/test_repair_quiz_bank_quality.py`

Expected: missing module errors.

- [ ] **Step 3: Implement quality rules**

Repair only if exactly one lexicon term overlaps, that term occurs once in the verse, and it does not overlap a retained position. Replace its offsets, word and meaning from the lexicon, revalidate the slice, then rank lexicon matches before common words and retain non-overlapping candidates up to the length target. Omit ambiguous candidates. Make exact normalized generic meanings invalid: `人名`, `地名`, `专名`, `人物`, `地点`, `事物`, `相关对象`, `某个人`, `某个地方`. Emit every omitted/repaired key to JSON and Markdown reports. Extend `validate_quiz_bank.py` with `--lexicon`, `--meaning-rules` and `--quality-report`; critical findings exit 1.

- [ ] **Step 4: Verify GREEN and commit**

Run: `python tools/test_audit_quiz_bank_quality.py`, `python tools/test_repair_quiz_bank_quality.py`, and `python tools/validate_quiz_bank.py --help`.

Expected: all tests pass and help lists all three quality options. Commit the two production tools, validator and two tests with message `feat: audit and repair quiz word quality`.

### Task 3: Publish a stable multi-shard quality snapshot

**Files:**
- Create: `bible-recite-plans/tools/publish_quiz_snapshot.py`
- Modify: `bible-recite-plans/tools/split_quiz_bank.py`
- Modify: `bible-recite-plans/README.md`
- Test: `bible-recite-plans/tools/test_publish_quiz_snapshot.py`

**Interfaces:** `publish_snapshot(input_bank, output_dir, index_path, revision) -> dict[str, Any]`; manifest includes `snapshotMode: "replace"` and `qualityVersion: 3`.

- [ ] **Step 1: Write failing publisher tests**

```python
def test_snapshot_has_replace_metadata_and_small_shards(tmp_path: Path) -> None:
    manifest = publish_snapshot(BANK, tmp_path, tmp_path / "quiz-bank.index.json", revision=702)
    assert manifest["snapshotMode"] == "replace"
    assert manifest["qualityVersion"] == 3
    assert all((tmp_path / item["path"]).stat().st_size < 10 * 1024 * 1024 for item in manifest["shards"])

def test_snapshot_rejects_reused_revision(tmp_path: Path) -> None:
    with pytest.raises(ValueError, match="must exceed"):
        publish_snapshot(BANK, tmp_path, INDEX_AT_702, revision=702)
```

- [ ] **Step 2: Run test and verify RED**

Run: `python tools/test_publish_quiz_snapshot.py`

Expected: missing publisher module.

- [ ] **Step 3: Implement staged publication**

Write shards in a temporary sibling directory while testing actual UTF-8 bytes after every appended question, with a 1024-byte safety margin. Build a manifest only after all shards validate. Reject a revision not strictly above the published revision. Atomically replace all shard files and the index only after the temporary tree is complete; remove stale shard files only in that final replacement phase.

- [ ] **Step 4: Verify GREEN and commit**

Run: `python tools/test_publish_quiz_snapshot.py`, `python tools/test_quiz_lexicon.py`, `python tools/test_audit_quiz_bank_quality.py`, and `python tools/test_repair_quiz_bank_quality.py`.

Expected: all tests pass, including one-byte-over-limit and stale-shard tests. Commit with message `feat: publish stable quality snapshots`.

### Task 4: Parse replacement metadata in the app

**Files:**
- Modify: `lib/src/features/quiz/domain/quiz_bank_index.dart`
- Test: `test/quiz/quiz_bank_index_test.dart`

**Interfaces:** `enum QuizBankSnapshotMode { incremental, replace }`; `QuizBankIndex.snapshotMode`; `QuizBankIndex.qualityVersion`.

- [ ] **Step 1: Write failing parser tests**

```dart
test('parses a v3 replace snapshot', () {
  final index = QuizBankIndex.parse(jsonEncode(replaceIndex));
  expect(index.snapshotMode, QuizBankSnapshotMode.replace);
  expect(index.qualityVersion, 3);
});

test('keeps a legacy index incremental', () {
  final index = QuizBankIndex.parse(jsonEncode(oldIndex));
  expect(index.snapshotMode, QuizBankSnapshotMode.incremental);
  expect(index.qualityVersion, 2);
});
```

- [ ] **Step 2: Run test and verify RED**

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test --no-pub test/quiz/quiz_bank_index_test.dart`

Expected: missing enum/properties compilation error.

- [ ] **Step 3: Implement backward-compatible strict parsing**

Missing metadata maps to incremental/2. Accept only `replace` and `incremental` when mode is supplied; reject all other mode values. Require a supplied quality version to be an integer above zero.

- [ ] **Step 4: Verify GREEN and commit**

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test --no-pub test/quiz/quiz_bank_index_test.dart`

Expected: parser tests pass. Commit with message `feat: parse quality snapshot metadata`.

### Task 5: Stage and atomically replace active questions

**Files:**
- Modify: `lib/src/features/plans/data/sqlite_plan_repository.dart`
- Test: `test/quiz/quiz_repository_test.dart`

**Interfaces:** `stageQuizBankSnapshot(revision, questions)`, `activateStagedQuizBankSnapshot(revision)`, `discardStagedQuizBankSnapshot(revision)`.

- [ ] **Step 1: Write failing repository tests**

```dart
test('replacement removes active questions and preserves results', () async {
  await repository.saveQuizQuestions([oldQuestion]);
  await repository.completeQuizQuestion(questionId: 1, correct: true, answeredAt: now);
  await repository.stageQuizBankSnapshot(702, [newQuestion]);
  await repository.activateStagedQuizBankSnapshot(702);
  expect(await repository.listQuizBankQuestions(), [newQuestion]);
  expect((await repository.getQuizSummary()).totalAnswered, 1);
  expect(database.select('SELECT question_id FROM quiz_result').single['question_id'], isNull);
});

test('staging never changes the active bank', () async {
  await repository.saveQuizQuestions([oldQuestion]);
  await repository.stageQuizBankSnapshot(702, [newQuestion]);
  expect(await repository.listQuizBankQuestions(), [oldQuestion]);
});
```

- [ ] **Step 2: Run test and verify RED**

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test --no-pub test/quiz/quiz_repository_test.dart`

Expected: missing staging API compilation error.

- [ ] **Step 3: Implement migration and transaction**

Rebuild `quiz_result` with nullable `question_id` and no cascading foreign key while copying every result field unchanged. Add `quiz_bank_snapshot_staging` with revision plus a unique question-position index. Activation begins `IMMEDIATE`, detaches historical `question_id`, deletes every `quiz_question`, inserts staged questions as unanswered quality-v3 rows, clears staging and commits. Any failure rolls back the active bank.

- [ ] **Step 4: Verify GREEN and commit**

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test --no-pub test/quiz/quiz_repository_test.dart`

Expected: migration, atomic rollback and history tests pass. Commit with message `feat: atomically replace active quiz bank`.

### Task 6: Stage all replacement shards before activation

**Files:**
- Modify: `lib/src/features/quiz/application/quiz_bank_sync.dart`
- Modify: `lib/src/features/statistics/presentation/statistics_screen.dart`
- Test: `test/quiz/quiz_bank_sync_test.dart`

**Interfaces:** `QuizBankSyncResult.replacedSnapshot`; success copy `题库质量更新完成：已替换 N 道题；历史答题记录已保留。`.

- [ ] **Step 1: Write failing synchronization tests**

```dart
test('replace activates only after every shard validates', () async {
  final result = await syncQuizBank(repository: repositoryWithOldQuestion, scripture: _FakeScripture(), client: clientFor(replaceIndexWithTwoShards));
  expect(result.replacedSnapshot, isTrue);
  expect(await repositoryWithOldQuestion.listQuizBankQuestions(), hasLength(2));
});

test('bad later shard preserves the old active bank', () async {
  await expectLater(syncQuizBank(repository: repositoryWithOldQuestion, scripture: _FakeScripture(), client: clientFor(indexWithBadSecondShard)), throwsA(isA<QuizBankFeedException>()));
  expect(await repositoryWithOldQuestion.listQuizBankQuestions(), [oldQuestion]);
});
```

- [ ] **Step 2: Run test and verify RED**

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test --no-pub test/quiz/quiz_bank_sync_test.dart`

Expected: current additive synchronization leaves the old question and imports the first shard before the later failure.

- [ ] **Step 3: Implement the replacement branch**

On `snapshotMode == replace`, clear only staging for that revision, download and validate every changed shard into staging, activate only after the loop, then save hashes/revision/status. On any exception discard staging and rethrow. Preserve the existing incremental path unchanged. Render replacement success copy only for the completed branch.

- [ ] **Step 4: Verify GREEN and commit**

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test --no-pub test/quiz/quiz_bank_sync_test.dart test/quiz/quiz_repository_test.dart test/dashboard/today_screen_test.dart test/recitation/recitation_practice_screen_test.dart`

Expected: all focused tests pass and failure never claims a reset. Commit with message `feat: stage quality snapshot syncs`.

### Task 7: Build, publish and release the verified v3 snapshot

**Files:**
- Modify: `bible-recite-plans/quiz-bank-*.json`
- Modify: `bible-recite-plans/quiz-bank.index.json`
- Modify: `bible_recite/pubspec.yaml` and release metadata required by the existing Android workflow.

- [ ] **Step 1: Freeze generation and prepare the final bank**

Run `audit_quiz_bank_quality.py`, `repair_quiz_bank_quality.py` and `validate_quiz_bank.py` with the new lexicon/rules. Require zero critical findings; unresolved items exist only in the audit report.

- [ ] **Step 2: Publish a single revision**

Run `publish_quiz_snapshot.py` with the next monotonic revision, then validate each listed shard and the index. Commit/push the lexicon, tools, snapshot files and index once with `feat: publish quality v3 quiz snapshot`.

- [ ] **Step 3: Verify public serving before mobile release**

For every index shard, fetch GitHub Raw, Fastly, CDN and Gcore bytes; require each UTF-8 size and SHA-256 to equal the index. Do not release while one source differs.

- [ ] **Step 4: Build, sign and device-verify**

Run focused tests and the existing Android release workflow. Verify CI conclusion, APK digest and signing certificate continuity. On a device/emulator with a historic quiz result, sync and assert: active count equals the v3 report, an old question is not selectable, and historic totals remain. Commit/push only the verified version/release metadata with `release: publish quality v3 quiz sync`.
