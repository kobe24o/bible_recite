# AI 单词答题 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Add cached AI-generated single-word Bible quiz questions, voice answers, independent quiz analytics, and chapter swipe navigation.

**Architecture:** A quiz domain layer validates an OpenAI-compatible model response before SQLite persistence. A repository owns caching, result transactions, and aggregates. The new quiz screen reuses the existing offline recognizer and Mandarin phonetic comparator for one-word answers.

**Tech Stack:** Flutter, Riverpod, SQLite3, http, existing Sherpa speech recognition, lpinyin, Flutter tests.

## Global Constraints

- Exact plan and highlighted verse ranges must never expand into a whole chapter.
- Existing recitation, Ebbinghaus, achievement and plan-completion semantics stay unchanged.
- Validate all model output: reference, UTF-16 code-unit indices, end-exclusive length, meaningful-word policy, and duplicate positions.
- Default settings are the Zhipu compatible URL and GLM-4.7-Flash; API Key is empty and never committed, logged, exported, or placed in fixtures.
- Quiz accuracy and recitation accuracy stay independent.
- Write one quiz result only after recording stops and correctness is known.

---

### Task 1: Quiz types and strict model-output validation

**Files:**
- Create: lib/src/features/quiz/domain/quiz_models.dart
- Create: lib/src/features/quiz/domain/quiz_question_validator.dart
- Test: test/quiz/quiz_question_validator_test.dart

**Interfaces:**
- Produces QuizGenerationVerse(reference, text, translationId, bookId, chapter, verse).
- Produces ValidatedQuizQuestion(verse, start, end, word, partOfSpeech, meaning), with end exclusive.
- Produces QuizQuestionValidator.validate({required List<QuizGenerationVerse> verses, required Object decodedJson}) -> List<ValidatedQuizQuestion>.

- [ ] **Step 1: Write failing tests**

~~~dart
test('keeps an exact meaningful word', () {
  final verse = QuizGenerationVerse(reference: '约翰福音 3:16', text: '神爱世人', translationId: 'cmn-cu89s', bookId: 'JHN', chapter: 3, verse: 16);
  final json = [{'reference': '约翰福音 3:16', 'start': 2, 'end': 4, 'length': 2, 'partOfSpeech': '名词', 'meaning': '世上的人'}];
  expect(QuizQuestionValidator().validate(verses: [verse], decodedJson: json).single.word, '世人');
});
test('rejects wrong reference/index/length, duplicate offsets and function words', () { /* expect empty */ });
~~~

- [ ] **Step 2: Run the test**

Run: D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test/quiz/quiz_question_validator_test.dart

Expected: FAIL because the domain files do not exist.

- [ ] **Step 3: Implement minimal validation**

~~~dart
final word = verse.text.substring(start, end);
if (start < 0 || end <= start || end > verse.text.length ||
    end - start != length || duplicateOffsets.contains((reference, start, end)) ||
    _isFunctionWord(word) || partOfSpeech.trim().isEmpty || meaning.trim().isEmpty) continue;
~~~

Use Dart string code-unit indexing deliberately and document it as UTF-16. _isFunctionWord must reject punctuation-only values and 的、了、着、过、吗、呢、啊、呀、和、与、及、而、但、且、或、在、把、被、给、从、向、对、以、于.

- [ ] **Step 4: Verify and commit**

Run: D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test/quiz/quiz_question_validator_test.dart

Expected: PASS.

~~~bash
git add lib/src/features/quiz/domain test/quiz/quiz_question_validator_test.dart
git commit -m "feat: validate AI quiz questions"
~~~

### Task 2: Configurable model client and generation service

**Files:**
- Create: lib/src/features/quiz/domain/quiz_model_settings.dart
- Create: lib/src/features/quiz/data/quiz_model_client.dart
- Create: lib/src/features/quiz/application/quiz_generation_service.dart
- Modify: pubspec.yaml
- Test: test/quiz/quiz_model_client_test.dart

**Interfaces:**
- Produces QuizModelSettings(baseUrl, model, apiKey), defaulting to Zhipu URL, GLM-4.7-Flash, and an empty key.
- Produces QuizModelClient.generate(settings, verses) -> Future<Object> and testConnection(settings) -> Future<void>.
- Produces QuizGenerationService.prepare(QuizScope) -> Future<QuizGenerationOutcome>.

- [ ] **Step 1: Write failing client tests**

~~~dart
expect(request.headers['authorization'], 'Bearer secret');
expect(jsonDecode(request.body)['model'], 'GLM-4.7-Flash');
expect(request.body, contains('只返回 JSON 数组'));
expect(request.body, contains('经文语言版本'));
expect(request.body, isNot(contains('secret')));
~~~

Test local blank-key rejection, generic non-2xx errors that never echo a key, and a connection test request containing no scripture.

- [ ] **Step 2: Run the test**

Run: D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test/quiz/quiz_model_client_test.dart

Expected: FAIL because the client does not exist.

- [ ] **Step 3: Implement the client and prompt**

Add http. Use a bounded timeout and one request only. Input includes translation/language plus each {reference,text}. Require a JSON array of reference,start,end,length,partOfSpeech,meaning; no prose; semantic/pronounceable words only; no function words/punctuation; UTF-16 start/end and end-exclusive semantics. The generation service validates parsed results and retries once only if no valid question remains.

- [ ] **Step 4: Verify and commit**

Run: D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test/quiz/quiz_model_client_test.dart

Run: D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat analyze lib/src/features/quiz

Expected: PASS; no new diagnostics.

~~~bash
git add pubspec.yaml pubspec.lock lib/src/features/quiz test/quiz/quiz_model_client_test.dart
git commit -m "feat: add configurable quiz model client"
~~~

### Task 3: SQLite question cache, results, and quiz aggregates

**Files:**
- Modify: lib/src/features/plans/data/sqlite_plan_repository.dart
- Create: lib/src/features/quiz/domain/quiz_result.dart
- Test: test/quiz/quiz_repository_test.dart

**Interfaces:**
- Produces listPendingQuizQuestions(scope), missingQuizVerses(scope), saveQuizQuestions(questions), completeQuizQuestion(questionId, correct, answeredAt), getQuizSummary(), and getQuizMetrics({translationId, bookId, chapter, verse}).
- Completion returns QuizCompletion(totalAnswered, totalCorrect, currentCorrectStreak, maxCorrectStreak).

- [ ] **Step 1: Write failing repository tests**

~~~dart
await repository.saveQuizQuestions([questionFor(verse: 16)]);
expect(await repository.missingQuizVerses(scopeFor(verse: 16)), isEmpty);
await repository.completeQuizQuestion(questionId: 1, correct: true, answeredAt: now);
await repository.completeQuizQuestion(questionId: 2, correct: false, answeredAt: now);
expect((await repository.getQuizSummary()).currentCorrectStreak, 0);
expect((await repository.getQuizSummary()).maxCorrectStreak, 1);
~~~

Also assert a pending question suppresses regeneration, a fully answered verse becomes eligible, and getRecitationSummary() is unaffected.

- [ ] **Step 2: Run the test**

Run: D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test/quiz/quiz_repository_test.dart

Expected: FAIL because schema and methods are absent.

- [ ] **Step 3: Implement transactional persistence**

Create quiz_question with source identity/location, metadata, answered_at, is_correct; create quiz_result for completed attempts. In BEGIN IMMEDIATE, reject a completed question, insert one result, mark the question, and update current_quiz_correct_streak/max_quiz_correct_streak settings. Aggregate only quiz_result.

- [ ] **Step 4: Verify and commit**

Run: D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test/quiz/quiz_repository_test.dart test/statistics/statistics_repository_test.dart

Expected: PASS.

~~~bash
git add lib/src/features/plans/data/sqlite_plan_repository.dart lib/src/features/quiz/domain test/quiz/quiz_repository_test.dart
git commit -m "feat: persist quiz attempts and metrics"
~~~

### Task 4: Model settings and one-word voice quiz screen

**Files:**
- Create: lib/src/features/quiz/presentation/quiz_practice_screen.dart
- Modify: lib/src/features/statistics/presentation/statistics_screen.dart
- Modify: lib/src/app/router.dart
- Test: test/quiz/quiz_practice_screen_test.dart
- Modify: test/statistics/statistics_screen_test.dart

**Interfaces:**
- Consumes existing OfflineSpeechRecognizer, MandarinPhoneticComparator, and ignore_final_nasal.
- Produces route /quiz with QuizPracticeRequest(scope, questions).

- [ ] **Step 1: Write failing widget tests**

~~~dart
await tester.tap(find.byKey(const Key('quiz-record-button')));
await recognizer.emitFinal('世人');
await tester.tap(find.byKey(const Key('quiz-record-button')));
expect(find.byKey(const Key('quiz-correct-word')), findsOneWidget);
expect(find.text('世人'), findsWidgets);
~~~

Test three hints (one character, part of speech, meaning), next/previous controls, horizontal page swipe, wrong answer green original word, and settings save with masked key display.

- [ ] **Step 2: Run the test**

Run: D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test/quiz/quiz_practice_screen_test.dart test/statistics/statistics_screen_test.dart

Expected: FAIL because screen and settings card do not exist.

- [ ] **Step 3: Implement UI and scoring**

Use a horizontal PageView. Render verse spans and replace only [start,end) with mic/result content. On stop, compare only the target word using Mandarin comparison with the existing nasal setting; exact comparison remains fallback; score 1 is correct. Call completion once. Add a My-page card/dialog for quiz_model_url, quiz_model_name, quiz_model_api_key, default URL/model, masked saved key, clear action and no-scripture connection test.

- [ ] **Step 4: Verify and commit**

Run: D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test/quiz/quiz_practice_screen_test.dart test/statistics/statistics_screen_test.dart

Run: D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat analyze lib/src/features/quiz lib/src/features/statistics/presentation/statistics_screen.dart

Expected: PASS; no new diagnostics.

~~~bash
git add lib/src/features/quiz lib/src/features/statistics/presentation/statistics_screen.dart lib/src/app/router.dart test/quiz test/statistics/statistics_screen_test.dart
git commit -m "feat: add voice quiz practice and model settings"
~~~

### Task 5: Generate questions from the three entry flows

**Files:**
- Modify: lib/src/features/dashboard/presentation/today_screen.dart
- Modify: lib/src/features/recitation/presentation/recitation_practice_screen.dart
- Modify: lib/src/features/scripture/presentation/passage_screen.dart
- Modify: lib/src/features/plans/presentation/plans_screen.dart
- Test: test/quiz/quiz_entry_flow_test.dart

**Interfaces:**
- Consumes QuizGenerationService.prepare(scope).
- Produces QuizPracticeScreen navigation only when pending questions exist.

- [ ] **Step 1: Write failing entry-flow tests**

~~~dart
await tester.pump(const Duration(seconds: 5));
expect(tester.widget<FilledButton>(find.byKey(const Key('start-quiz-button')).first).onPressed, isNotNull);
~~~

Cover full exact plan scope after Today recitation, whole chapter after 5 seconds, highlighted plan-read range after 5 seconds, cancellation when leaving early, and no client invocation when cached pending questions exist.

- [ ] **Step 2: Run the test**

Run: D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test/quiz/quiz_entry_flow_test.dart

Expected: FAIL because entry generation is unwired.

- [ ] **Step 3: Implement lifecycle-safe entry wiring**

In PassageScreen, start/cancel a five-second timer; keep start-quiz-button disabled until cached/generated questions are available; show retry error only on failure. Add plan Read navigation carrying its exact highlighted range. Today starts plan-wide preparation as recitation begins and navigates to quiz after normal recitation persistence completes. Never use getChapter to replace the plan range.

- [ ] **Step 4: Verify and commit**

Run: D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test/quiz/quiz_entry_flow_test.dart test/dashboard/today_screen_test.dart test/scripture/passage_screen_test.dart test/recitation/recitation_practice_screen_test.dart

Expected: PASS.

~~~bash
git add lib/src/features/dashboard lib/src/features/recitation lib/src/features/scripture lib/src/features/plans test/quiz/quiz_entry_flow_test.dart
git commit -m "feat: generate quiz questions from learning entries"
~~~

### Task 6: Independent quiz statistics and map metrics

**Files:**
- Modify: lib/src/features/statistics/presentation/statistics_screen.dart
- Modify: lib/src/features/statistics/presentation/recitation_map_screen.dart
- Modify: lib/src/features/statistics/presentation/recitation_timeline_screen.dart
- Test: test/statistics/quiz_map_metrics_test.dart
- Modify: test/statistics/statistics_screen_test.dart

**Interfaces:**
- Consumes QuizSummary(totalAnswered, totalCorrect, accuracy, currentCorrectStreak, maxCorrectStreak) and QuizRangeMetric(answered, correct, accuracy).
- Produces explicitly labelled recitation and quiz metrics at each map level.

- [ ] **Step 1: Write failing UI tests**

~~~dart
expect(find.text('背诵准确率 80%'), findsOneWidget);
expect(find.text('答题准确率 50%'), findsOneWidget);
expect(find.text('答题多少道 2'), findsOneWidget);
expect(find.text('最大连续正确 1 道'), findsOneWidget);
~~~

Cover book/chapter/verse maps and assert empty scopes say 暂无答题.

- [ ] **Step 2: Run the test**

Run: D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test/statistics/statistics_screen_test.dart test/statistics/quiz_map_metrics_test.dart

Expected: FAIL because quiz metrics are not rendered.

- [ ] **Step 3: Implement separate projections**

Leave existing recitation calculations intact. Rename former bare labels to 背诵准确率; load/render quiz aggregates as 答题准确率 or 暂无答题 at map overview and every drill-down. Add answered, correct, rate, and best streak below the existing companionship card.

- [ ] **Step 4: Verify and commit**

Run: D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test/statistics/statistics_screen_test.dart test/statistics/quiz_map_metrics_test.dart

Expected: PASS.

~~~bash
git add lib/src/features/statistics test/statistics
git commit -m "feat: show independent quiz accuracy metrics"
~~~

### Task 7: Same-book chapter swipe navigation and final verification

**Files:**
- Modify: lib/src/features/scripture/presentation/passage_screen.dart
- Modify: test/scripture/passage_screen_test.dart
- Test: all test/quiz and affected existing suites.

**Interfaces:**
- Produces _goToChapter(int chapter) that routes to /bible/:translation/:book/:chapter without crossing a book boundary.

- [ ] **Step 1: Write failing gesture tests**

~~~dart
await tester.drag(find.byKey(const Key('passage-reading-area')), const Offset(-400, 0));
await tester.pumpAndSettle();
expect(router.location, '/bible/cmn-cu89s/JHN/4');
~~~

Test previous chapter, no change at first/last chapter, and vertical drag preserving chapter.

- [ ] **Step 2: Run the test**

Run: D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test/scripture/passage_screen_test.dart

Expected: FAIL because the reading gesture does not navigate.

- [ ] **Step 3: Implement and verify navigation**

Wrap only the normal reading list in a horizontal-drag detector. Use a distance/velocity threshold and the existing scripture/catalog chapter count; navigate only inside 1..chapterCount, preserve parallel/read controls and reset selection on navigation.

Run: D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test/scripture/passage_screen_test.dart

Expected: PASS.

- [ ] **Step 4: Run complete verification and live model test**

Run: D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test/quiz test/recitation test/scripture test/statistics test/dashboard test/plans

Run: D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat analyze

Use the user-provided Zhipu key only process-locally for one small live Chinese-verse request. Verify parsing and exact source mapping, and ensure the raw key does not appear in output. Run a secret scan for the given key prefix and generic api-key-looking values and verify git status only contains intended changes.

- [ ] **Step 5: Commit**

~~~bash
git add lib/src/features/scripture/presentation/passage_screen.dart test/scripture/passage_screen_test.dart
git commit -m "feat: swipe between Bible chapters"
~~~

