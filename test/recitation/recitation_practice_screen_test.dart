import 'dart:async';

import 'package:bible_recite/src/features/recitation/domain/bible_pronunciation_lexicon.dart';
import 'package:bible_recite/src/features/recitation/domain/mandarin_phonetic_comparator.dart';
import 'package:bible_recite/src/features/recitation/domain/recognition_models.dart';
import 'package:bible_recite/src/features/recitation/domain/speech_recognizer.dart';
import 'package:bible_recite/src/features/recitation/presentation/recitation_practice_screen.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:bible_recite/src/features/plans/application/plan_providers.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/plans/domain/plan_models.dart';
import 'package:bible_recite/src/features/quiz/application/quiz_generation_service.dart';
import 'package:bible_recite/src/features/quiz/application/quiz_providers.dart';
import 'package:bible_recite/src/features/quiz/data/quiz_model_client.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_model_settings.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart';

import '../scripture/scripture_browser_screen_test.dart'
    show FakeRepositoryForPassage;

void main() {
  testWidgets('verse mode aligns live then advances one verse at a time', (
    tester,
  ) async {
    final recognizer = FakeRecognizer();
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWith((ref) async => repository),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: RecitationPracticeScreen(
            request: _request(RecitationMode.verse),
            recognizer: recognizer,
          ),
        ),
      ),
    );

    expect(find.text('第 1 / 2 节'), findsOneWidget);
    expect(find.text('当前背诵：约翰福音 3:16'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('record-button')));
    await tester.tap(find.byKey(const Key('record-button')));
    await tester.pumpAndSettle();
    recognizer.emit(const RecognitionPartial('神爱'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('alignment-output')), findsOneWidget);

    await tester.tap(find.byKey(const Key('record-button')));
    await tester.pumpAndSettle();
    expect(await repository.listRecitationResults(), hasLength(1));
    expect(find.text('获得新成就'), findsOneWidget);
    await tester.tap(find.text('太棒了'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('next-verse-button')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('next-verse-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('next-verse-button')));
    await tester.pump();
    expect(find.text('第 2 / 2 节'), findsOneWidget);
    expect(find.text('当前背诵：约翰福音 3:17'), findsOneWidget);
  });

  testWidgets('continuous mode presents the whole passage as one session', (
    tester,
  ) async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWith((ref) async => repository),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: RecitationPracticeScreen(
            request: _request(RecitationMode.continuous),
            recognizer: FakeRecognizer(),
          ),
        ),
      ),
    );

    expect(find.text('连续背诵 · 2 节'), findsOneWidget);
    expect(find.byKey(const Key('next-verse-button')), findsNothing);
    expect(find.text('约翰福音 3:16'), findsWidgets);
    expect(find.text('约翰福音 3:17'), findsWidgets);
  });

  testWidgets('live result restores punctuation from the selected scripture', (
    tester,
  ) async {
    final recognizer = FakeRecognizer();
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWith((ref) async => repository),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: RecitationPracticeScreen(
            request: RecitationRequest(
              translationId: 'cmn-cu89s',
              bookId: 'JHN',
              chapter: 3,
              mode: RecitationMode.verse,
              units: [_unit(16, '「　神爱世人，甚至将他的独生子赐给他们。」')],
            ),
            recognizer: recognizer,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('record-button')));
    await tester.pumpAndSettle();
    recognizer.emit(const RecognitionPartial('神爱世人甚至将他的独生子赐给他们'));
    await tester.pumpAndSettle();

    final output = tester.widget<RichText>(
      find.byKey(const Key('alignment-output')),
    );
    expect(output.text.toPlainText(), '「　神爱世人，甚至将他的独生子赐给他们。」');
  });

  testWidgets('a passed recitation schedules Ebbinghaus chapter reviews', (
    tester,
  ) async {
    final recognizer = FakeRecognizer();
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final today = DateTime.now();
    final planId = await repository.createPlan(
      NewMemorizationPlan(
        title: '约翰福音 3 章',
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        startChapter: 3,
        endChapter: 3,
        startDate: today,
        endDate: today,
        ebbinghausEnabled: true,
        tasks: const [
          NewPlanTask(
            dayIndex: 0,
            startChapter: 3,
            startVerse: 16,
            endChapter: 3,
            endVerse: 16,
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWith((ref) async => repository),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: RecitationPracticeScreen(
            request: RecitationRequest(
              translationId: 'cmn-cu89s',
              bookId: 'JHN',
              chapter: 3,
              mode: RecitationMode.continuous,
              units: [_unit(16, '神爱世人')],
              reviewId: null,
              planId: planId,
            ),
            recognizer: recognizer,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('record-button')));
    await tester.pumpAndSettle();
    recognizer.emit(const RecognitionFinal('神爱世人'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('record-button')));
    await tester.pumpAndSettle();
    expect(
      await repository.dueEbbinghausReviews(
        DateTime.now().add(const Duration(days: 30)),
      ),
      hasLength(1),
    );
  });

  testWidgets(
    'finishing the last task due today celebrates on the recitation page',
    (tester) async {
      final recognizer = FakeRecognizer();
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      final today = DateTime.now();
      final planId = await repository.createPlan(
        NewMemorizationPlan(
          title: '今日任务',
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          startChapter: 3,
          endChapter: 3,
          startDate: today,
          endDate: today,
          tasks: const [
            NewPlanTask(
              dayIndex: 0,
              startChapter: 3,
              startVerse: 16,
              endChapter: 3,
              endVerse: 16,
            ),
          ],
        ),
      );
      final task = (await repository.listTasks(planId)).single;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            planRepositoryProvider.overrideWith((ref) async => repository),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: const [Locale('zh')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: RecitationPracticeScreen(
              request: RecitationRequest(
                translationId: 'cmn-cu89s',
                bookId: 'JHN',
                chapter: 3,
                mode: RecitationMode.continuous,
                planTaskId: task.id,
                units: [_unit(16, '神爱世人')],
              ),
              recognizer: recognizer,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('record-button')));
      await tester.pumpAndSettle();
      recognizer.emit(const RecognitionFinal('神爱世人'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('record-button')));
      await tester.pump(const Duration(seconds: 1));

      expect((await repository.listTasks(planId)).single.completed, isTrue);
      expect(
        find.byKey(const Key('recitation-completion-confetti')),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 8));
    },
  );

  testWidgets('finished Chinese recitation records phonetic corrections', (
    tester,
  ) async {
    final recognizer = FakeRecognizer();
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWith((ref) async => repository),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: RecitationPracticeScreen(
            request: RecitationRequest(
              translationId: 'cmn-cu89s',
              bookId: 'JHN',
              chapter: 3,
              mode: RecitationMode.verse,
              units: [_unit(16, '喜乐')],
            ),
            recognizer: recognizer,
            mandarinComparator: MandarinPhoneticComparator(
              lexicon: BiblePronunciationLexicon.fromJson('{}'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('record-button')));
    await tester.pumpAndSettle();
    recognizer.emit(const RecognitionFinal('洗了'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('record-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('同音修正 2'), findsWidgets);
    expect(
      (await repository.listRecitationResults()).single.phoneticCorrectCount,
      2,
    );
  });

  testWidgets(
    'shows quiz preparation error after a recitation with a quiz scope',
    (tester) async {
      final recognizer = FakeRecognizer();
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            planRepositoryProvider.overrideWith((ref) async => repository),
            quizGenerationServiceProvider.overrideWith(
              (ref) async => QuizGenerationService(
                repository: repository,
                scripture: FakeRepositoryForPassage(),
                client: QuizModelClient(),
                settingsLoader: () async => const QuizModelSettings(
                  baseUrl: 'https://example.test/v1',
                  model: 'test-model',
                  apiKey: '',
                ),
              ),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: const [Locale('zh')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: RecitationPracticeScreen(
              request: RecitationRequest(
                translationId: 'cmn-cu89s',
                bookId: 'JHN',
                chapter: 3,
                mode: RecitationMode.verse,
                units: [_unit(16, '神爱世人')],
                quizScope: const QuizScope(
                  translationId: 'cmn-cu89s',
                  bookId: 'JHN',
                  startChapter: 3,
                  startVerse: 16,
                  endChapter: 3,
                  endVerse: 16,
                ),
              ),
              recognizer: recognizer,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('record-button')));
      await tester.pumpAndSettle();
      recognizer.emit(const RecognitionFinal('神爱世人'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('record-button')));
      await tester.pumpAndSettle();
      if (find.text('获得新成就').evaluate().isNotEmpty) {
        await tester.tap(find.text('太棒了'));
        await tester.pumpAndSettle();
      }

      expect(await repository.listRecitationResults(), hasLength(1));
      expect(find.textContaining('缺少答题模型配置：API Key'), findsOneWidget);
    },
  );
}

RecitationRequest _request(RecitationMode mode) => RecitationRequest(
  translationId: 'cmn-cu89s',
  bookId: 'JHN',
  chapter: 3,
  mode: mode,
  units: [_unit(16, '神爱世人'), _unit(17, '不是定世人的罪')],
);

VerseUnit _unit(int verse, String text) => VerseUnit(
  translationId: 'cmn-cu89s',
  start: (
    canonId: CanonId.protestant66,
    osisBookId: 'JHN',
    chapter: 3,
    verse: verse,
  ),
  end: (
    canonId: CanonId.protestant66,
    osisBookId: 'JHN',
    chapter: 3,
    verse: verse,
  ),
  text: text,
  status: SourceTextStatus.present,
);

final class FakeRecognizer implements OfflineSpeechRecognizer {
  final _events = StreamController<RecognitionEvent>.broadcast();
  void emit(RecognitionEvent event) => _events.add(event);

  @override
  Stream<RecognitionEvent> get events => _events.stream;
  @override
  Future<void> dispose() => _events.close();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> start({required String languageTag}) async {}
  @override
  Future<void> stop() async {}
}
