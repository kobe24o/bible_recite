import 'dart:async';

import 'package:bible_recite/src/features/plans/application/plan_providers.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_result.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_scope.dart';
import 'package:bible_recite/src/features/quiz/presentation/quiz_practice_request.dart';
import 'package:bible_recite/src/features/quiz/presentation/quiz_practice_screen.dart';
import 'package:bible_recite/src/features/recitation/domain/recognition_models.dart';
import 'package:bible_recite/src/features/recitation/domain/speech_recognizer.dart';
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

  testWidgets('hint advances from characters to part of speech to meaning', (
    tester,
  ) async {
    final recognizer = FakeQuizRecognizer();
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    await tester.pumpWidget(_app(repository, recognizer));

    final hintButton = find.byKey(const Key('quiz-hint-button'));
    expect(find.textContaining('提示（2 个字）'), findsOneWidget);

    await tester.tap(hintButton);
    await tester.pumpAndSettle();
    expect(find.text('提示：世'), findsOneWidget);

    await tester.tap(hintButton);
    await tester.pumpAndSettle();
    expect(find.text('词性：名词'), findsOneWidget);

    await tester.tap(hintButton);
    await tester.pumpAndSettle();
    expect(find.text('字面解释：世上的人'), findsOneWidget);
  });

  testWidgets('next and previous buttons switch questions', (tester) async {
    final recognizer = FakeQuizRecognizer();
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    await tester.pumpWidget(_app(repository, recognizer));

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

Widget _app(
  SqlitePlanRepository repository,
  FakeQuizRecognizer recognizer,
) => ProviderScope(
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
        questions: [
          _question(16),
          _question(17),
        ],
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
  verseText: '神爱世人',
);

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
