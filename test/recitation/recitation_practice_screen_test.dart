import 'dart:async';

import 'package:bible_recite/src/features/recitation/domain/bible_pronunciation_lexicon.dart';
import 'package:bible_recite/src/features/recitation/domain/mandarin_phonetic_comparator.dart';
import 'package:bible_recite/src/features/recitation/domain/recognition_models.dart';
import 'package:bible_recite/src/features/recitation/domain/speech_recognizer.dart';
import 'package:bible_recite/src/features/recitation/presentation/recitation_practice_screen.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:bible_recite/src/features/plans/application/plan_providers.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart';

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
    await tester.pumpAndSettle();
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
    await tester.tap(find.byKey(const Key('next-verse-button')));
    await tester.pump();
    expect(find.text('第 2 / 2 节'), findsOneWidget);
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
    await repository.updateEbbinghausSettings(
      enabled: true,
      passThreshold: 0.8,
      now: DateTime.now().subtract(const Duration(minutes: 1)),
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
      hasLength(6),
    );
  });

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
