import 'dart:async';

import 'package:bible_recite/src/features/plans/application/plan_providers.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_result.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_scope.dart';
import 'package:bible_recite/src/features/quiz/presentation/quiz_practice_request.dart';
import 'package:bible_recite/src/features/quiz/presentation/quiz_practice_screen.dart';
import 'package:bible_recite/src/features/recitation/domain/recognition_models.dart';
import 'package:bible_recite/src/features/recitation/domain/speech_recognizer.dart';
import 'package:bible_recite/src/features/scripture/application/scripture_providers.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  testWidgets('records one word and shows the correct original word', (
    tester,
  ) async {
    final recognizer = FakeQuizRecognizer();
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    await tester.pumpWidget(_app(repository, recognizer));
    await tester.pumpAndSettle();

    expect(find.text('请朗读被隐藏的词语'), findsOneWidget);
    expect(find.byKey(const Key('quiz-mic-inline')), findsOneWidget);

    // Tap the mic to start recording.
    await tester.tap(find.byKey(const Key('quiz-mic-inline')));
    await tester.pumpAndSettle();
    recognizer.emit(const RecognitionFinal('世人'));
    await tester.pumpAndSettle();
    // Stop recording.
    await tester.tap(find.byKey(const Key('quiz-record-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('quiz-correct-word')), findsOneWidget);
    expect(find.text('答对了！'), findsOneWidget);
    expect(find.textContaining('正确答案'), findsOneWidget);
    expect(find.text('世人'), findsWidgets);
  });

  testWidgets('hint shows length but never exposes answer letters', (
    tester,
  ) async {
    final recognizer = FakeQuizRecognizer();
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    await tester.pumpWidget(_app(repository, recognizer));
    await tester.pumpAndSettle();

    final hintButton = find.byKey(const Key('quiz-hint-button'));
    expect(find.text('提示'), findsOneWidget);
    expect(find.textContaining('_'), findsNothing);

    await tester.tap(hintButton);
    await tester.pumpAndSettle();
    expect(find.text('提示：2 个字'), findsOneWidget);
    expect(find.text('提示：世'), findsNothing);

    await tester.tap(hintButton);
    await tester.pumpAndSettle();
    expect(find.text('词性：名词'), findsOneWidget);

    await tester.tap(hintButton);
    await tester.pumpAndSettle();
    expect(find.text('字面解释：世上的人'), findsOneWidget);
    expect(find.textContaining('世人：世上的人'), findsNothing);
  });

  testWidgets(
    'a phonetic-correct answer fills the original word, not ASR text',
    (tester) async {
      final recognizer = FakeQuizRecognizer();
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      await tester.pumpWidget(_app(repository, recognizer));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('quiz-mic-inline')));
      await tester.pumpAndSettle();
      recognizer.emit(const RecognitionFinal('世任'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quiz-record-button')));
      await tester.pumpAndSettle();

      final filledWord = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('quiz-correct-word')),
          matching: find.byType(Text),
        ),
      );
      expect(filledWord.data, '世人');
      expect(find.text('你读的：世任'), findsOneWidget);
    },
  );

  testWidgets('shows the current question progress', (tester) async {
    final recognizer = FakeQuizRecognizer();
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    await tester.pumpWidget(_app(repository, recognizer));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('quiz-progress')), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quiz-next-button')));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('next and previous buttons switch questions', (tester) async {
    final recognizer = FakeQuizRecognizer();
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    await tester.pumpWidget(_app(repository, recognizer));
    await tester.pumpAndSettle();

    expect(find.text('约翰福音 3:16'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quiz-next-button')));
    await tester.pumpAndSettle();
    expect(find.text('约翰福音 3:17'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quiz-previous-button')));
    await tester.pumpAndSettle();
    expect(find.text('约翰福音 3:16'), findsOneWidget);
  });

  testWidgets('wrong answer still shows the green original word', (
    tester,
  ) async {
    final recognizer = FakeQuizRecognizer();
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    await tester.pumpWidget(_app(repository, recognizer));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('quiz-mic-inline')));
    await tester.pumpAndSettle();
    recognizer.emit(const RecognitionFinal('世人世人'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quiz-record-button')));
    await tester.pumpAndSettle();

    expect(find.text('没答对'), findsOneWidget);
    expect(find.byKey(const Key('quiz-correct-word')), findsOneWidget);
  });
}

Widget _app(SqlitePlanRepository repository, FakeQuizRecognizer recognizer) =>
    ProviderScope(
      overrides: [
        planRepositoryProvider.overrideWith((ref) async => repository),
        scriptureRepositoryProvider.overrideWith(
          (ref) async => _FakeScripture(),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: QuizPracticeScreen(
          request: QuizPracticeRequest(
            scope: const QuizScope(
              translationId: 'cmn-cu89s',
              bookId: 'JHN',
              startChapter: 3,
              startVerse: 16,
              endChapter: 3,
              endVerse: 17,
            ),
            questions: [_question(16), _question(17)],
          ),
          recognizer: recognizer,
        ),
      ),
    );

PendingQuizQuestion _question(int verse) => PendingQuizQuestion(
  id: verse == 16 ? 1 : 2,
  translationId: 'cmn-cu89s',
  bookId: 'JHN',
  chapter: 3,
  verse: verse,
  start: 2,
  end: 4,
  word: '世人',
  partOfSpeech: '名词',
  meaning: '世上的人',
  reference: verse == 16 ? '3:16' : '3:17',
);

final class _FakeScripture implements ScriptureRepository {
  @override
  Future<List<VerseUnit>> getChapter(
    String translationId,
    String book,
    int chapter,
  ) async => [
    VerseUnit(
      translationId: translationId,
      start: (
        canonId: CanonId.protestant66,
        osisBookId: book,
        chapter: chapter,
        verse: 16,
      ),
      end: (
        canonId: CanonId.protestant66,
        osisBookId: book,
        chapter: chapter,
        verse: 16,
      ),
      text: '神爱世人',
      status: SourceTextStatus.present,
    ),
    VerseUnit(
      translationId: translationId,
      start: (
        canonId: CanonId.protestant66,
        osisBookId: book,
        chapter: chapter,
        verse: 17,
      ),
      end: (
        canonId: CanonId.protestant66,
        osisBookId: book,
        chapter: chapter,
        verse: 17,
      ),
      text: '神爱世人',
      status: SourceTextStatus.present,
    ),
  ];

  @override
  Future<List<TranslationInfo>> listTranslations() =>
      throw UnimplementedError();
  @override
  Future<TranslationInfo> getTranslation(String id) =>
      throw UnimplementedError();
  @override
  Future<List<BibleBook>> listBooks(String translationId, CanonId canonId) =>
      throw UnimplementedError();
  @override
  Future<Passage> getPassage(String translationId, PassageRange range) =>
      throw UnimplementedError();
  @override
  Future<SelectedPassage> getSelection(
    String translationId,
    PassageSelection selection,
  ) => throw UnimplementedError();
  @override
  Future<ParallelPassage> resolveParallelPassage(
    LocatedPassageRange sourceRange,
    String targetTranslationId,
  ) => throw UnimplementedError();
}

final class FakeQuizRecognizer implements OfflineSpeechRecognizer {
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
