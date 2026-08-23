import 'package:bible_recite/l10n/generated/app_localizations.dart';
import 'package:bible_recite/src/features/plans/application/plan_providers.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/plans/domain/cloud_plan_manifest.dart';
import 'package:bible_recite/src/features/plans/domain/plan_models.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_models.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_scope.dart';
import 'package:bible_recite/src/features/statistics/domain/recitation_result.dart';
import 'package:bible_recite/src/features/statistics/presentation/statistics_screen.dart';
import 'package:bible_recite/src/features/statistics/presentation/random_quiz_options_dialog.dart';
import 'package:bible_recite/src/features/scripture/application/scripture_providers.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../scripture/scripture_browser_screen_test.dart'
    show FakeRepositoryForPassage;

const _bundledManifest = CloudPlanManifest(
  protocolVersion: 1,
  publisher: 'test',
  plans: [
    CloudPlanTemplate(
      id: 'classic-passages',
      title: '圣经经典篇章',
      description: '',
      push: false,
      revision: 1,
      defaultTranslationId: 'cmn-cu89s',
      defaultStartDate: null,
      defaultEndDate: null,
      sourceName: 'test',
      tag: '',
      passages: [
        CloudPlanPassage(
          order: 1,
          bookId: 'GEN',
          startChapter: 1,
          startVerse: 1,
          endChapter: 1,
          endVerse: 1,
        ),
      ],
    ),
  ],
);

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
    await _pumpScreen(
      tester,
      repository,
      view: StatisticsScreenView.learningData,
    );

    expect(find.text('背诵 1 次'), findsOneWidget);
    expect(find.text('背诵正确率 80%'), findsOneWidget);
    expect(find.text('目前连续背诵 1 天 · 最高连续背诵 1 天'), findsOneWidget);
    expect(find.text('目前连续背诵 2 节 · 最高连续背诵 2 节'), findsOneWidget);
    expect(find.text('最近背诵'), findsNothing);
    await _pumpScreen(
      tester,
      repository,
      view: StatisticsScreenView.achievements,
    );
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
    await tester.pump();
    final badgeAnimation = tester.widget<ScaleTransition>(
      find.byKey(const Key('achievement-detail-badge-animation')),
    );
    expect(badgeAnimation.scale.value, lessThan(1));
    await tester.pump(const Duration(milliseconds: 340));
    final badgeGlow = tester.widget<FadeTransition>(
      find.byKey(const Key('achievement-detail-badge-glow')),
    );
    expect(badgeGlow.opacity.value, greaterThan(.5));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('achievement-unlock-animation')),
      findsOneWidget,
    );
    final detailArtwork = find.byKey(
      const Key('achievement-detail-badge-artwork'),
    );
    expect(detailArtwork, findsOneWidget);
    expect(
      find.descendant(of: detailArtwork, matching: find.byType(Icon)),
      findsNothing,
    );
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

    await _pumpScreen(
      tester,
      repository,
      view: StatisticsScreenView.learningData,
    );

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

    await _pumpScreen(
      tester,
      repository,
      view: StatisticsScreenView.achievements,
    );

    expect(find.text('路得的成就'), findsOneWidget);
    expect(find.text('我的成就'), findsNothing);
  });

  testWidgets('keeps learning data and achievements off the My overview', (
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
    expect(find.byKey(const Key('learning-data-open')), findsOneWidget);
    expect(find.byKey(const Key('achievement-open')), findsOneWidget);
    expect(find.text('背诵 1 次'), findsNothing);
    expect(find.text('我的成就'), findsNothing);

    await _pumpScreen(
      tester,
      repository,
      view: StatisticsScreenView.learningData,
    );
    expect(find.widgetWithText(AppBar, '学习数据'), findsOneWidget);
    expect(find.text('背诵 1 次'), findsOneWidget);

    await _pumpScreen(
      tester,
      repository,
      view: StatisticsScreenView.achievements,
    );
    expect(find.widgetWithText(AppBar, '我的成就'), findsOneWidget);
    expect(
      find.byKey(const Key('achievement-first_recitation-unlocked')),
      findsOneWidget,
    );
  });

  testWidgets('unlocks a title badge after completing a preset plan', (
    tester,
  ) async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final planId = await repository.createPlan(
      NewMemorizationPlan(
        title: '恩典之路',
        translationId: 'eng-web',
        bookId: 'JHN',
        startChapter: 3,
        endChapter: 3,
        startDate: DateTime(2026, 8, 15),
        endDate: DateTime(2026, 8, 15),
        sourceKind: PlanSourceKind.preset,
        externalId: 'grace-path',
        contentLocked: true,
        tasks: const [
          NewPlanTask(
            dayIndex: 0,
            bookId: 'JHN',
            startChapter: 3,
            startVerse: 16,
            endChapter: 3,
            endVerse: 16,
          ),
        ],
      ),
    );
    final task = (await repository.listTasks(planId)).single;
    await repository.setTaskCompleted(task.id, true);
    await repository.saveRecitationResult(
      NewRecitationResult(
        translationId: 'eng-web',
        bookId: 'JHN',
        chapter: 3,
        startVerse: 16,
        endVerse: 16,
        planId: planId,
        verseMetrics: const [
          NewRecitationVerseMetric(
            bookId: 'JHN',
            chapter: 3,
            verse: 16,
            accuracy: 1,
            durationSeconds: 10,
          ),
        ],
        mode: 'continuous',
        durationSeconds: 10,
        correctCount: 10,
        incorrectCount: 0,
        omittedCount: 0,
        reorderedCount: 0,
        accuracy: 1,
        completedAt: DateTime(2026, 8, 15),
      ),
    );

    await _pumpScreen(
      tester,
      repository,
      scripture: FakeRepositoryForPassage(),
      view: StatisticsScreenView.achievements,
    );

    expect(find.text('恩典之路勋章'), findsWidgets);
    expect(
      find.byKey(const Key('achievement-preset_plan_grace-path-unlocked')),
      findsOneWidget,
    );
    expect(find.text('获得新成就'), findsNothing);
    final titleBadge = find.byKey(
      const Key('achievement-preset_plan_grace-path-unlocked'),
    );
    await tester.ensureVisible(titleBadge);
    await tester.tap(titleBadge);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('achievement-unlock-animation')),
      findsOneWidget,
    );
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
                  name: 'Genesis',
                  chapterCount: 50,
                ),
                BibleBook(
                  osisId: 'JHN',
                  ordinal: 43,
                  name: 'John',
                  chapterCount: 21,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('开始卷'), findsOneWidget);
      expect(find.text('创世记'), findsOneWidget);
      expect(find.text('开始章'), findsOneWidget);
      expect(find.text('结束卷'), findsOneWidget);
      expect(find.text('结束章'), findsOneWidget);
      expect(find.text('最大题数'), findsOneWidget);
    },
  );
}

Future<void> _pumpScreen(
  WidgetTester tester,
  SqlitePlanRepository repository, {
  FakeRepositoryForPassage? scripture,
  StatisticsScreenView view = StatisticsScreenView.overview,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        planRepositoryProvider.overrideWith((ref) async => repository),
        bundledCloudPlanManifestProvider.overrideWith(
          (ref) async => _bundledManifest,
        ),
        if (scripture != null)
          scriptureRepositoryProvider.overrideWith((ref) async => scripture),
      ],
      child: MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: StatisticsScreen(view: view),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
