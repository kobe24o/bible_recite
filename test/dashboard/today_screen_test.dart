import 'package:bible_recite/l10n/generated/app_localizations.dart';
import 'package:bible_recite/src/features/dashboard/presentation/today_screen.dart';
import 'package:bible_recite/src/features/plans/application/plan_providers.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/plans/domain/plan_models.dart';
import 'package:bible_recite/src/features/statistics/domain/recitation_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  testWidgets('opens a due Ebbinghaus review chapter with its review id', (
    tester,
  ) async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await repository.updateEbbinghausSettings(
      enabled: true,
      passThreshold: 0.8,
      now: yesterday.subtract(const Duration(minutes: 1)),
    );
    final resultId = await repository.saveRecitationResult(
      NewRecitationResult(
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        chapter: 3,
        startVerse: 1,
        endVerse: 36,
        chapterVerseCount: 36,
        mode: 'continuous',
        durationSeconds: 60,
        correctCount: 80,
        incorrectCount: 20,
        omittedCount: 0,
        reorderedCount: 0,
        accuracy: 0.8,
        completedAt: yesterday,
      ),
    );
    await repository.processEbbinghausResult(resultId: resultId);
    final review = (await repository.dueEbbinghausReviews(
      DateTime.now(),
    )).single;
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const TodayScreen()),
        GoRoute(
          path: '/bible/:translation/:book/:chapter',
          builder: (_, state) => Scaffold(body: Text('复习章节已打开:${state.extra}')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWith((ref) async => repository),
        ],
        child: MaterialApp.router(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('艾宾浩斯复习'), findsOneWidget);
    await tester.tap(find.text('艾宾浩斯复习'));
    await tester.pumpAndSettle();
    expect(find.text('复习章节已打开:${review.id}'), findsOneWidget);
  });

  testWidgets('opens a task passage and keeps completed tasks with undo', (
    tester,
  ) async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final today = DateTime.now();
    await repository.createPlan(
      NewMemorizationPlan(
        title: '今日约翰福音',
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        startChapter: 1,
        endChapter: 1,
        startDate: today,
        endDate: today,
        tasks: const [
          NewPlanTask(
            dayIndex: 0,
            startChapter: 1,
            startVerse: 1,
            endChapter: 1,
            endVerse: 5,
          ),
        ],
      ),
    );
    final task = (await repository.listTasks(1)).single;
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const TodayScreen()),
        GoRoute(
          path: '/bible/:translation/:book/:chapter',
          builder: (_, _) => const Scaffold(body: Text('经文详情已打开')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWith((ref) async => repository),
        ],
        child: MaterialApp.router(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('complete-task-${task.id}')));
    await tester.pumpAndSettle();
    expect(find.text('今日已完成'), findsOneWidget);
    expect(find.text('今日约翰福音'), findsOneWidget);

    await tester.tap(find.byKey(Key('undo-task-${task.id}')));
    await tester.pumpAndSettle();
    expect(find.text('待完成'), findsOneWidget);

  });
}
