import 'package:bible_recite/l10n/generated/app_localizations.dart';
import 'package:bible_recite/src/features/plans/application/plan_providers.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_models.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_scope.dart';
import 'package:bible_recite/src/features/statistics/domain/recitation_result.dart';
import 'package:bible_recite/src/features/statistics/presentation/statistics_screen.dart';
import 'package:bible_recite/src/features/statistics/presentation/random_quiz_options_dialog.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  testWidgets('shows Ebbinghaus settings before any recitation exists', (
    tester,
  ) async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    await _pumpScreen(tester, repository);

    expect(find.widgetWithText(AppBar, '我的'), findsOneWidget);
    expect(find.text('艾宾浩斯背诵法'), findsOneWidget);
    expect(find.text('通过阈值 80%'), findsOneWidget);
    expect(find.text('复习间隔：1、2、4、7、15、30 天'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('show-recitation-scripture-toggle')),
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('show-recitation-scripture-toggle')),
          )
          .value,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('show-recitation-scripture-toggle')));
    await tester.pumpAndSettle();
    expect(
      await repository.getSetting('show_recitation_scripture', 'true'),
      'false',
    );

    expect(find.byKey(const Key('ebbinghaus-toggle')), findsNothing);
    final slider = tester.widget<Slider>(
      find.byKey(const Key('ebbinghaus-threshold')),
    );
    slider.onChanged!(0.85);
    slider.onChangeEnd!(0.85);
    await tester.pumpAndSettle();

    final settings = await repository.getEbbinghausSettings();
    expect(settings.enabled, isFalse);
    expect(settings.passThreshold, 0.85);
  });

  testWidgets('shows summary cards without recent recitation results', (
    tester,
  ) async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    await repository.saveRecitationResult(
      NewRecitationResult(
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        chapter: 3,
        startVerse: 16,
        endVerse: 17,
        mode: 'continuous',
        durationSeconds: 42,
        correctCount: 20,
        incorrectCount: 2,
        omittedCount: 1,
        reorderedCount: 1,
        accuracy: 0.8,
        completedAt: DateTime.now(),
      ),
    );
    await _pumpScreen(tester, repository);

    expect(find.text('背诵 1 次'), findsOneWidget);
    expect(find.text('背诵正确率 80%'), findsOneWidget);
    expect(find.text('目前连续背诵 1 天 · 最高连续背诵 1 天'), findsOneWidget);
    expect(find.text('目前连续背诵 2 节 · 最高连续背诵 2 节'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('背诵 1 次')).dy,
      lessThan(tester.getTopLeft(find.text('艾宾浩斯背诵法')).dy),
    );
    expect(find.text('最近背诵'), findsNothing);
    expect(find.text('我的成就'), findsOneWidget);
    expect(find.text('初次开口'), findsOneWidget);
    expect(
      find.byKey(const Key('achievement-first_recitation-unlocked')),
      findsOneWidget,
    );
    expect(find.text('已获得 · 100%'), findsWidgets);
    expect(find.text('89%'), findsOneWidget);

    final firstBadge = find.byKey(
      const Key('achievement-first_recitation-unlocked'),
    );
    await tester.ensureVisible(firstBadge);
    await tester.tap(firstBadge);
    await tester.pumpAndSettle();
    expect(find.textContaining('当前进度：100%'), findsOneWidget);
    final timeText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .firstWhere((text) => text.contains('获得时间：'));
    expect(timeText, isNot(contains(RegExp(r':\d{2}\.\d'))));
  });

  testWidgets('keeps quiz statistics separate from recitation statistics', (
    tester,
  ) async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    await repository.saveQuizQuestions([
      const ValidatedQuizQuestion(
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        chapter: 3,
        verse: 16,
        start: 9,
        end: 12,
        word: '世人',
        partOfSpeech: '名词',
        meaning: '人类',
        reference: '约翰福音 3:16',
        verseText: '神爱世人',
      ),
    ]);
    final question = (await repository.listPendingQuizQuestions(
      const QuizScope(
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        startChapter: 3,
        startVerse: 16,
        endChapter: 3,
        endVerse: 16,
      ),
    )).single;
    await repository.completeQuizQuestion(
      questionId: question.id,
      correct: true,
      answeredAt: DateTime.now(),
    );

    await _pumpScreen(tester, repository);

    expect(find.text('答题 1 道'), findsOneWidget);
    expect(find.text('答对 1 道'), findsOneWidget);
    expect(find.text('答题正确率 100%'), findsOneWidget);
    expect(find.text('最大连续答对 1 道'), findsOneWidget);
  });

  testWidgets('uses the configured name in the achievements heading', (
    tester,
  ) async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    await repository.setSetting('profile_name', '路得');
    await repository.saveRecitationResult(
      NewRecitationResult(
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        chapter: 3,
        startVerse: 16,
        endVerse: 16,
        mode: 'continuous',
        durationSeconds: 30,
        correctCount: 10,
        incorrectCount: 0,
        omittedCount: 0,
        reorderedCount: 0,
        accuracy: 1,
        completedAt: DateTime.now(),
      ),
    );

    await _pumpScreen(tester, repository);

    expect(find.text('路得的成就'), findsOneWidget);
    expect(find.text('我的成就'), findsNothing);
  });

  testWidgets(
    'random quiz dialog lets the user choose a scripture range and maximum count',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RandomQuizOptionsDialog(
              books: [
                BibleBook(
                  osisId: 'GEN',
                  ordinal: 1,
                  name: '创世记',
                  chapterCount: 50,
                ),
                BibleBook(
                  osisId: 'JHN',
                  ordinal: 43,
                  name: '约翰福音',
                  chapterCount: 21,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('开始卷'), findsOneWidget);
      expect(find.text('开始章'), findsOneWidget);
      expect(find.text('结束卷'), findsOneWidget);
      expect(find.text('结束章'), findsOneWidget);
      expect(find.text('最大题数'), findsOneWidget);
    },
  );
}

Future<void> _pumpScreen(
  WidgetTester tester,
  SqlitePlanRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        planRepositoryProvider.overrideWith((ref) async => repository),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: StatisticsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
