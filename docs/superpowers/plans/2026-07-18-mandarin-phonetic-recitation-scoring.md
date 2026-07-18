# Mandarin Phonetic Recitation Scoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Score simplified and traditional Chinese recitations by context-aware, toneless Mandarin pronunciation after the user finishes, while preserving raw ASR characters for genuine pronunciation errors.

**Architecture:** Refactor the existing exact alignment behind a comparator interface, then add an offline Mandarin comparator that encodes context-aware pinyin and performs exact-first weighted Damerau-Levenshtein alignment. Persist phonetic-correct counts as a subset of total correct counts so statistics, achievements, and Ebbinghaus behavior adopt the new accuracy without breaking old rows.

**Tech Stack:** Flutter 3.44.4, Dart 3.12, `lpinyin` 2.0.3, bundled JSON pronunciation overrides, SQLite schema migration, existing Riverpod/recitation UI and Flutter tests.

## Global Constraints

- Enable phonetic scoring only for `cmn-cu89s` and `cmn-cu89t`.
- Ignore tone completely; compare lowercase toneless pinyin syllables.
- Exact characters outrank phonetic matches when alignment costs tie.
- Never accept any arbitrary pronunciation of a polyphonic character; use phrase context and the Bible override dictionary.
- During live recognition, do not replace homophone characters.
- Only the finished result corrects phonetic matches to target characters.
- A pronunciation mismatch keeps the ASR-recognized character visible.
- English `eng-web` and all unknown translations preserve exact-text behavior.
- `correct_count` remains total credited correctness; `phonetic_correct_count` is a subset.
- Existing rows migrate with `phonetic_correct_count = 0` and unchanged accuracy.
- Do not persist recordings or full transcripts.
- A pinyin failure falls back to exact comparison; it must never lose a completed recitation.
- Every task uses TDD and ends with a focused commit.

---

## File Map

**Create:**

- `lib/src/features/recitation/domain/recitation_comparator.dart` — comparator contract and translation strategy selection.
- `lib/src/features/recitation/domain/exact_text_comparator.dart` — current behavior extracted without semantic change.
- `lib/src/features/recitation/domain/mandarin_phonetic_comparator.dart` — toneless phonetic alignment.
- `lib/src/features/recitation/domain/bible_pronunciation_lexicon.dart` — validated asset loading and deterministic longest-phrase lookup.
- `lib/src/features/recitation/application/recitation_scoring_provider.dart` — asynchronously load the lexicon and expose the finished comparator.
- `assets/pronunciation/bible_pinyin_overrides.json` — phrase pronunciations for simplified/traditional biblical text.
- `test/recitation/exact_text_comparator_test.dart`
- `test/recitation/bible_pronunciation_lexicon_test.dart`
- `test/recitation/mandarin_phonetic_comparator_test.dart`
- `test/recitation/recitation_scoring_strategy_test.dart`

**Modify:**

- `pubspec.yaml` — add `lpinyin` and pronunciation asset.
- `lib/src/features/recitation/domain/recitation_alignment.dart` — add `phoneticCorrect` and count semantics.
- `lib/src/features/recitation/presentation/recitation_practice_screen.dart` — exact live comparison, phonetic finished comparison and summary.
- `lib/src/features/statistics/domain/recitation_result.dart` — phonetic subset field.
- `lib/src/features/plans/data/sqlite_plan_repository.dart` — schema version 6 migration and persistence.
- `test/recitation/recitation_alignment_test.dart`
- `test/recitation/recitation_practice_screen_test.dart`
- `test/statistics/statistics_repository_test.dart`
- `test/review/ebbinghaus_repository_test.dart`
- `test/app/platform_configuration_test.dart`

---

### Task 1: Extract Exact Comparison Behind a Stable Interface

**Files:**
- Create: `lib/src/features/recitation/domain/recitation_comparator.dart`
- Create: `lib/src/features/recitation/domain/exact_text_comparator.dart`
- Create: `test/recitation/exact_text_comparator_test.dart`
- Modify: `lib/src/features/recitation/domain/recitation_alignment.dart`
- Modify: `test/recitation/recitation_alignment_test.dart`

**Interfaces:**
- Produces: `abstract interface class RecitationComparator` with `compare(target, transcript, {finished})`.
- Produces: `ExactTextComparator.compare` with byte-for-byte equivalent token text/kinds and counts to the current static implementation.
- Produces: public immutable `RecitationAlignment.fromTokens({required tokens, required targetLength})` for comparator implementations.

- [ ] **Step 1: Copy the current behavior into characterization tests**

Add cases for punctuation restoration, wrong character, middle omission, adjacent transposition, trailing pending/finished, extra leading/trailing characters, repeated characters, and English case folding. Assert the complete token `(text, kind)` list, not just accuracy.

```dart
expect(
  const ExactTextComparator().compare('神爱世人', '神碍世人', finished: true)
      .tokens
      .map((token) => (token.text, token.kind)),
  [('神', RecitationTokenKind.correct),
   ('碍', RecitationTokenKind.incorrect),
   ('世', RecitationTokenKind.correct),
   ('人', RecitationTokenKind.correct)],
);
```

- [ ] **Step 2: Run and verify failure**

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\recitation\exact_text_comparator_test.dart`

Expected: FAIL because `ExactTextComparator` is missing.

- [ ] **Step 3: Define the comparator interface**

```dart
abstract interface class RecitationComparator {
  const RecitationComparator();
  RecitationAlignment compare(
    String target,
    String transcript, {
    required bool finished,
  });
}
```

- [ ] **Step 4: Move the current algorithm without changing it**

Move normalization, dynamic-programming matrix, backtracking, original-text projection and helper types into `ExactTextComparator`. Change `RecitationAlignment` to a result-only model with:

```dart
const RecitationAlignment.fromTokens({
  required this.tokens,
  required this.targetLength,
});
```

Update `RecitationPracticeScreen` to hold `static const _exactComparator = ExactTextComparator()` and replace both existing static calls with `_exactComparator.compare(...)`. Update existing alignment tests to construct and call `ExactTextComparator`; do not introduce a circular import from the result model back to a comparator.

- [ ] **Step 5: Run old and new tests**

Run:

```powershell
D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\recitation\recitation_alignment_test.dart test\recitation\exact_text_comparator_test.dart
```

Expected: all existing and characterization tests PASS.

- [ ] **Step 6: Commit**

```powershell
git add lib/src/features/recitation/domain lib/src/features/recitation/presentation/recitation_practice_screen.dart test/recitation/recitation_alignment_test.dart test/recitation/exact_text_comparator_test.dart
git commit -m "refactor: isolate exact recitation comparison"
```

### Task 2: Add and Validate the Bible Pronunciation Lexicon

**Files:**
- Create: `lib/src/features/recitation/domain/bible_pronunciation_lexicon.dart`
- Create: `assets/pronunciation/bible_pinyin_overrides.json`
- Create: `test/recitation/bible_pronunciation_lexicon_test.dart`
- Modify: `pubspec.yaml`
- Modify: `test/app/platform_configuration_test.dart`

**Interfaces:**
- Produces: `BiblePronunciationLexicon.load(AssetBundle)`.
- Produces: immutable `Map<String, List<String>> entries` and `LexiconMatch? longestMatchAt(List<String> characters, int start)`.

- [ ] **Step 1: Pin dependency and declare asset**

```yaml
dependencies:
  lpinyin: 2.0.3

flutter:
  assets:
    - assets/pronunciation/bible_pinyin_overrides.json
```

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat pub get`

Expected: dependency resolves and lockfile records 2.0.3.

- [ ] **Step 2: Write lexicon validation tests**

Test nonempty phrase, one syllable per comparable Han character, lowercase ASCII toneless syllables, duplicate conflicts, simplified/traditional pairs, malformed JSON, and longest-match preference when phrases overlap.

```dart
expect(lexicon.entries['长子'], ['zhang', 'zi']);
expect(lexicon.entries['長子'], ['zhang', 'zi']);
expect(lexicon.entries['行为'], ['xing', 'wei']);
expect(lexicon.entries['行為'], ['xing', 'wei']);
```

- [ ] **Step 3: Create the initial explicit dictionary**

```json
{
  "长子": ["zhang", "zi"],
  "長子": ["zhang", "zi"],
  "行为": ["xing", "wei"],
  "行為": ["xing", "wei"],
  "耶和华": ["ye", "he", "hua"],
  "耶和華": ["ye", "he", "hua"],
  "便雅悯": ["bian", "ya", "min"],
  "便雅憫": ["bian", "ya", "min"],
  "该撒": ["gai", "sa"],
  "該撒": ["gai", "sa"]
}
```

- [ ] **Step 4: Implement validation and deterministic longest-match lookup**

Build an immutable first-character index of phrases sorted by descending character length. `longestMatchAt` returns the longest exact simplified/traditional phrase and its toneless syllables. The comparator applies this lexicon before calling lpinyin for uncovered spans, so behavior does not depend on mutable global dictionaries or undocumented acceptance of toneless overrides.

- [ ] **Step 5: Add packaging regression assertions and run tests**

Assert `pubspec.yaml` contains both `lpinyin: 2.0.3` and the asset path.

Run:

```powershell
D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\recitation\bible_pronunciation_lexicon_test.dart test\app\platform_configuration_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add pubspec.yaml pubspec.lock assets/pronunciation lib/src/features/recitation/domain/bible_pronunciation_lexicon.dart test/recitation/bible_pronunciation_lexicon_test.dart test/app/platform_configuration_test.dart
git commit -m "feat: add offline Bible pronunciation lexicon"
```

### Task 3: Implement Exact-First Toneless Mandarin Alignment

**Files:**
- Create: `lib/src/features/recitation/domain/mandarin_phonetic_comparator.dart`
- Create: `test/recitation/mandarin_phonetic_comparator_test.dart`
- Modify: `lib/src/features/recitation/domain/recitation_alignment.dart`

**Interfaces:**
- Consumes: `RecitationComparator`, lexicon from Tasks 1–2.
- Produces: `MandarinPhoneticComparator({required BiblePronunciationLexicon lexicon})` and `RecitationTokenKind.phoneticCorrect`.
- Produces counts: `exactCorrectCount`, `phoneticCorrectCount`, `correctCount` as their sum.

- [ ] **Step 1: Write phonetic behavior tests**

Cover:

```dart
test('corrects toneless homophones to target text', () {
  final result = comparator.compare('神爱世人', '神碍是人', finished: true);
  expect(result.tokens.map((token) => token.text).join(), '神爱世人');
  expect(result.exactCorrectCount, 2);
  expect(result.phoneticCorrectCount, 2);
  expect(result.accuracy, 1);
});

test('ignores tone differences', () {
  final result = comparator.compare('日期', '日骑', finished: true);
  expect(result.phoneticCorrectCount, 1); // 期 qi1 / 骑 qi2
});

test('keeps genuine pronunciation errors as ASR text', () {
  final result = comparator.compare('神爱', '声爱', finished: true);
  expect(result.tokens.first.text, '声');
  expect(result.tokens.first.kind, RecitationTokenKind.incorrect);
});

test('does not match an arbitrary polyphonic candidate', () {
  final result = comparator.compare('银行', '隐形', finished: true);
  expect(result.phoneticCorrectCount, 1);
  expect(result.incorrectCount, 1); // 行 is hang in 银行, not xing
});
```

Also cover simplified/traditional, punctuation, middle omission, extra word, repeated syllables, transposition, conversion failure and empty target.

- [ ] **Step 2: Run and verify failure**

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\recitation\mandarin_phonetic_comparator_test.dart`

Expected: FAIL because comparator and token kind are missing.

- [ ] **Step 3: Add alignment result semantics**

Add `phoneticCorrect` to the enum. Store immutable tokens and target length; compute:

```dart
int get exactCorrectCount => _count(RecitationTokenKind.correct);
int get phoneticCorrectCount => _count(RecitationTokenKind.phoneticCorrect);
int get correctCount => exactCorrectCount + phoneticCorrectCount;
double get accuracy => targetLength == 0 ? 0 : correctCount / targetLength;
```

- [ ] **Step 4: Implement context pinyin encoding**

Strip noncomparable characters while retaining original indices. Scan left-to-right, applying `longestMatchAt` first. For uncovered spans, call `PinyinHelper.getPinyinE` on the full span with a sentinel separator and `PinyinFormat.WITHOUT_TONE`, then require exactly one emitted syllable per character. On mismatch/exception, mark only affected units as exact-only rather than treating conversion failure as a phonetic match.

- [ ] **Step 5: Implement lexicographic dynamic-programming cost**

Use a score tuple `(editErrors, negativeExactMatches, negativePhoneticMatches, editOperations)` and choose lexicographic minimum. Substitution produces exact, phoneticCorrect, or incorrect. Preserve insertion, deletion and adjacent transposition backtracking. Project exact/phonetic matches to target characters; project incorrect and extra steps to ASR characters.

- [ ] **Step 6: Run focused and regression tests**

Run:

```powershell
D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\recitation\mandarin_phonetic_comparator_test.dart test\recitation\exact_text_comparator_test.dart test\recitation\recitation_alignment_test.dart
```

Expected: Mandarin tests PASS and exact comparator tests remain unchanged.

- [ ] **Step 7: Commit**

```powershell
git add lib/src/features/recitation/domain/mandarin_phonetic_comparator.dart lib/src/features/recitation/domain/recitation_alignment.dart test/recitation
git commit -m "feat: align Mandarin recitation by toneless pinyin"
```

### Task 4: Select Scoring Strategy and Integrate Finished-Only Correction

**Files:**
- Modify: `lib/src/features/recitation/domain/recitation_comparator.dart`
- Create: `lib/src/features/recitation/application/recitation_scoring_provider.dart`
- Create: `test/recitation/recitation_scoring_strategy_test.dart`
- Modify: `lib/src/features/recitation/presentation/recitation_practice_screen.dart`
- Modify: `test/recitation/recitation_practice_screen_test.dart`

**Interfaces:**
- Produces: `RecitationComparator comparatorForTranslation(String translationId, {required bool finished, required MandarinPhoneticComparator mandarin})`.
- Produces: `mandarinPhoneticComparatorProvider`, a `FutureProvider<MandarinPhoneticComparator>` that loads the bundled lexicon once.
- Consumes: exact and Mandarin comparators.

- [ ] **Step 1: Write strategy tests**

```dart
expect(comparatorForTranslation('cmn-cu89s', finished: true, mandarin: mandarin),
    isA<MandarinPhoneticComparator>());
expect(comparatorForTranslation('cmn-cu89t', finished: true, mandarin: mandarin),
    isA<MandarinPhoneticComparator>());
expect(comparatorForTranslation('cmn-cu89s', finished: false, mandarin: mandarin),
    isA<ExactTextComparator>());
expect(comparatorForTranslation('eng-web', finished: true, mandarin: mandarin),
    isA<ExactTextComparator>());
```

- [ ] **Step 2: Write screen tests before integration**

For target `神爱世人` and ASR `神碍是人`, assert live RichText contains `神碍是人` and no “同音修正” summary; after tapping finish assert output is `神爱世人`, accuracy is 100%, and summary contains `原字正确 2 字 · 同音修正 2 字`. Add an English test proving `love/love` behavior is unchanged and wrong words stay wrong.

- [ ] **Step 3: Run and verify failure**

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\recitation\recitation_scoring_strategy_test.dart test\recitation\recitation_practice_screen_test.dart`

Expected: FAIL on missing strategy and phonetic summary.

- [ ] **Step 4: Integrate comparator selection**

The live `_alignment` getter always uses the exact comparator. Initialize the async Mandarin provider before enabling recording for a Chinese translation; a provider load error stores an exact-comparator fallback and a nonblocking local warning. In `_stopRecording`, stop the recognizer first, then run the finished comparator selected by `request.translationId`, set `_finished`, and save that exact result instance. Catch pinyin exceptions and fall back to finished exact comparison before saving.

- [ ] **Step 5: Update result colors and summary**

Map `phoneticCorrect` to the same green as correct. Show exact and phonetic counts only after finish; do not add a second percentage or change existing Ebbinghaus threshold UI.

- [ ] **Step 6: Run tests and commit**

Run:

```powershell
D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\recitation\recitation_scoring_strategy_test.dart test\recitation\recitation_practice_screen_test.dart
```

Expected: PASS.

```powershell
git add lib/src/features/recitation/application lib/src/features/recitation/domain lib/src/features/recitation/presentation test/recitation
git commit -m "feat: apply phonetic scoring after recitation"
```

### Task 5: Migrate SQLite and Persist Phonetic Correct Counts

**Files:**
- Modify: `lib/src/features/statistics/domain/recitation_result.dart`
- Modify: `lib/src/features/plans/data/sqlite_plan_repository.dart`
- Modify: `test/statistics/statistics_repository_test.dart`
- Modify: `test/review/ebbinghaus_repository_test.dart`

**Interfaces:**
- Adds: `phoneticCorrectCount` defaulting to 0 in `NewRecitationResult` and required through `RecitationResult` construction.
- Keeps: `correctCount = exact + phonetic`, so downstream accuracy and achievements remain compatible.

- [ ] **Step 1: Write migration tests against a version-5 in-memory database**

Create the old `recitation_result` schema without `phonetic_correct_count`, insert an 80% row, construct the repository, and assert the new column exists with value 0, row accuracy is still 0.8, and `PRAGMA user_version` is 6.

- [ ] **Step 2: Write new-result persistence tests**

Save a result with `correctCount: 10`, `phoneticCorrectCount: 3`; read it back and assert both values and unchanged accuracy. Assert achievements and an 80% Ebbinghaus threshold use total correct/accuracy, not exact-only count.

- [ ] **Step 3: Run and verify failure**

Run:

```powershell
D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\statistics\statistics_repository_test.dart test\review\ebbinghaus_repository_test.dart
```

Expected: FAIL on missing field and schema column.

- [ ] **Step 4: Implement transactional schema migration**

Read `PRAGMA table_info(recitation_result)`, then inside `BEGIN IMMEDIATE` add:

```sql
ALTER TABLE recitation_result
ADD COLUMN phonetic_correct_count INTEGER NOT NULL DEFAULT 0;
PRAGMA user_version = 6;
```

Commit on success and roll back on failure. Update CREATE TABLE, insert column/value, row mapping and domain constructors. Do not overwrite stored `accuracy`.

- [ ] **Step 5: Pass phonetic count from recitation save**

Set `correctCount: alignment.correctCount` and `phoneticCorrectCount: alignment.phoneticCorrectCount`. Existing callers compile because the new input field defaults to zero.

- [ ] **Step 6: Run repository, review and screen tests**

Run:

```powershell
D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\statistics test\review test\recitation\recitation_practice_screen_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```powershell
git add lib/src/features/statistics/domain/recitation_result.dart lib/src/features/plans/data/sqlite_plan_repository.dart lib/src/features/recitation/presentation/recitation_practice_screen.dart test/statistics test/review test/recitation/recitation_practice_screen_test.dart
git commit -m "feat: persist phonetic recitation accuracy"
```

### Task 6: Performance, Full Regression and Real-Phone Acceptance

**Files:**
- Modify only files from Tasks 1–5 if verification exposes defects.

**Interfaces:**
- Consumes: completed Mandarin scoring implementation.
- Produces: verified release behavior without regressions in English, achievements or Ebbinghaus scheduling.

- [ ] **Step 1: Add a long-passage performance test**

Build a target of at least 500 comparable Han characters with exact, homophone, omission and transposition regions. Run finished comparison 20 times and assert each result is stable and one comparison completes under 250ms in profile-appropriate test conditions. If CI timing is noisy, assert under 1 second in unit tests and record real-device timing under 250ms separately.

- [ ] **Step 2: Run full automated verification**

Run:

```powershell
D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test
D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat analyze
git diff --check
```

Expected: all tests PASS, `No issues found!`, and no whitespace errors.

- [ ] **Step 3: Build the signed release APK**

Run the versioned build script with the effective version/build assigned by the update plan. Verify `aapt dump badging` reports the expected version and `apksigner verify --verbose --print-certs` reports v2 true and certificate SHA-256 ending `39b5a7e7`.

- [ ] **Step 4: Verify Chinese behavior on the connected phone**

Complete one simplified and one traditional recitation containing:

- a different character with the same toneless pronunciation;
- a different tone with the same initial/final;
- one genuine pronunciation mismatch;
- one omitted character;
- one adjacent reversal.

Before finish, confirm ASR characters remain visible. After finish, confirm only homophones change to target text, genuine errors remain ASR text, and the displayed counts match the saved “最近背诵” accuracy.

- [ ] **Step 5: Verify English and data preservation**

Complete one `eng-web` recitation and confirm exact scoring is unchanged. Upgrade over a database containing old results and confirm old rows report zero phonetic corrections, achievements remain unlocked, and Ebbinghaus due tasks remain present.

- [ ] **Step 6: Commit verification corrections only when needed**

If a defect is found, fix it in its owning file, rerun the focused test and full gates, then commit the explicit files changed. If no defect is found, do not create an empty commit.
