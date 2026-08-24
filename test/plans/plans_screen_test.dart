import 'package:bible_recite/l10n/generated/app_localizations.dart';
import 'package:bible_recite/src/features/plans/presentation/plans_screen.dart';
import 'package:bible_recite/src/features/plans/application/plan_providers.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/plans/domain/cloud_plan_manifest.dart';
import 'package:bible_recite/src/features/plans/domain/plan_models.dart';
import 'package:bible_recite/src/features/scripture/application/scripture_providers.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqlite3/sqlite3.dart';

import '../scripture/scripture_browser_screen_test.dart'
    show FakeRepositoryForPassage;

void main() {
  testWidgets('shows exactly the two bundled cross-book plans', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: PlansScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('圣经经典篇章'), findsOneWidget);
    expect(find.text('每卷书钥节'), findsOneWidget);
    expect(find.text('诗篇 23篇'), findsNothing);
    expect(find.text('马太福音 5–7章'), findsNothing);
    expect(find.byKey(const Key('cloud-plan-source-button')), findsOneWidget);
    expect(find.byKey(const Key('sync-cloud-plans-button')), findsOneWidget);
    expect(
      find.byKey(const Key('import-cloud-plan-file-button')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.text('自定义计划'), 240);
    expect(find.text('自定义计划'), findsOneWidget);
  });

  testWidgets('saving a preset plan does not show its completion animation', (
    tester,
  ) async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWith((ref) async => repository),
          bundledCloudPlanManifestProvider.overrideWith(
            (ref) async => const CloudPlanManifest(
              protocolVersion: 1,
              publisher: 'test',
              plans: [
                CloudPlanTemplate(
                  id: 'preset-test',
                  title: '预置保存测试',
                  description: '',
                  push: false,
                  revision: 1,
                  defaultTranslationId: 'eng-web',
                  defaultStartDate: null,
                  defaultEndDate: null,
                  sourceName: 'test',
                  tag: '',
                  passages: [
                    CloudPlanPassage(
                      order: 1,
                      bookId: 'JHN',
                      startChapter: 3,
                      startVerse: 16,
                      endChapter: 3,
                      endVerse: 16,
                    ),
                  ],
                ),
              ],
            ),
          ),
          scriptureRepositoryProvider.overrideWith(
            (ref) async => FakeRepositoryForPassage(),
          ),
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
          home: PlansScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('预置保存测试'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-preset-plan-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-plan-button')));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('获得新成就'), findsNothing);
    expect(find.byKey(const Key('achievement-unlock-animation')), findsNothing);
    expect(
      (await repository.listPlans()).map((plan) => plan.title),
      contains('预置保存测试'),
    );
  });

  testWidgets('opens an existing plan for chapter and date editing', (
    tester,
  ) async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final planId = await repository.createPlan(
      NewMemorizationPlan(
        title: '可编辑计划',
        translationId: 'eng-web',
        bookId: 'JHN',
        startChapter: 1,
        endChapter: 1,
        startDate: DateTime(2026, 7, 15),
        endDate: DateTime(2026, 7, 20),
        tasks: const [
          NewPlanTask(
            dayIndex: 0,
            startChapter: 1,
            startVerse: 1,
            endChapter: 1,
            endVerse: 5,
          ),
        ],
        sourceKind: PlanSourceKind.cloud,
        sourceUrl: 'https://example.com/cloud-plans.json',
        externalId: 'cloud-plan',
        revision: 1,
        contentLocked: true,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWith((ref) async => repository),
          scriptureRepositoryProvider.overrideWith(
            (ref) async => FakeRepositoryForPassage(),
          ),
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
          home: PlansScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(Key('plan-actions-$planId')), findsOneWidget);
    expect(find.text('云端'), findsOneWidget);
    expect(find.textContaining('0/1'), findsOneWidget);
    await tester.tap(find.byKey(Key('plan-actions-$planId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑计划'));
    await tester.pumpAndSettle();
    expect(find.text('编辑背诵计划'), findsOneWidget);
    expect(find.byKey(const Key('plan-translation')), findsOneWidget);
    expect(find.byKey(const Key('locked-plan-content-note')), findsOneWidget);
    expect(find.byKey(const Key('delete-plan-button')), findsOneWidget);
  });

  testWidgets('groups multiple passages scheduled for one day', (tester) async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    await repository.createPlan(
      NewMemorizationPlan(
        title: '压缩后的计划',
        translationId: 'eng-web',
        bookId: 'JHN',
        startChapter: 3,
        endChapter: 3,
        startDate: DateTime(2026, 7, 25),
        endDate: DateTime(2026, 7, 26),
        tasks: const [
          NewPlanTask(
            dayIndex: 0,
            bookId: 'JHN',
            startChapter: 3,
            startVerse: 16,
            endChapter: 3,
            endVerse: 18,
            blocks: [
              NewPlanTaskBlock(
                bookId: 'JHN',
                startChapter: 3,
                startVerse: 16,
                endChapter: 3,
                endVerse: 18,
              ),
            ],
          ),
          NewPlanTask(
            dayIndex: 0,
            bookId: 'GEN',
            startChapter: 1,
            startVerse: 1,
            endChapter: 1,
            endVerse: 1,
          ),
          NewPlanTask(
            dayIndex: 1,
            bookId: 'JHN',
            startChapter: 3,
            startVerse: 17,
            endChapter: 3,
            endVerse: 17,
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWith((ref) async => repository),
          scriptureRepositoryProvider.overrideWith(
            (ref) async => FakeRepositoryForPassage(
              chapterUnits: [
                for (final verse in [16, 17, 18])
                  VerseUnit(
                    translationId: 'eng-web',
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
                    text: '$verse',
                    status: SourceTextStatus.present,
                  ),
              ],
            ),
          ),
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
          home: PlansScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('压缩后的计划'));
    await tester.pumpAndSettle();

    expect(find.text('第 1 天'), findsOneWidget);
    expect(find.text('2026-07-25 · 2 条背诵'), findsOneWidget);
    expect(find.text('第 2 天'), findsOneWidget);

    final pendingTask = (await repository.listTasks(1)).first;
    await tester.tap(find.byKey(Key('move-task-${pendingTask.id}')));
    await tester.pumpAndSettle();
    expect(find.text('移动经文范围'), findsOneWidget);
    expect(find.byKey(const Key('move-range-start')), findsOneWidget);
    expect(find.byKey(const Key('move-range-end')), findsOneWidget);
    expect(find.byKey(const Key('move-range-target-day')), findsOneWidget);
    await tester.tap(find.byKey(const Key('move-range-start')));
    await tester.pumpAndSettle();
    expect(find.text('约翰福音 3:17'), findsNWidgets(2));
  });

  testWidgets('summarizes custom multi-book plans with Chinese book names', (
    tester,
  ) async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    await repository.createPlan(
      NewMemorizationPlan(
        title: '多卷摘要计划',
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        startChapter: 1,
        endChapter: 3,
        startDate: DateTime(2026, 7, 25),
        endDate: DateTime(2026, 7, 26),
        tasks: const [
          NewPlanTask(
            dayIndex: 0,
            bookId: 'JHN',
            startChapter: 1,
            startVerse: 1,
            endChapter: 1,
            endVerse: 5,
          ),
          NewPlanTask(
            dayIndex: 1,
            bookId: 'GEN',
            startChapter: 1,
            startVerse: 1,
            endChapter: 1,
            endVerse: 3,
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWith((ref) async => repository),
          scriptureRepositoryProvider.overrideWith(
            (ref) async => FakeRepositoryForPassage(),
          ),
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
          home: PlansScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('约翰福音等'), findsOneWidget);
    expect(find.textContaining('JHN'), findsNothing);
    expect(find.textContaining('1–3章'), findsNothing);
  });

  testWidgets('keeps read and recite actions after a task is completed', (
    tester,
  ) async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final planId = await repository.createPlan(
      NewMemorizationPlan(
        title: '已完成计划',
        translationId: 'eng-web',
        bookId: 'JHN',
        startChapter: 3,
        endChapter: 3,
        startDate: DateTime(2026, 7, 30),
        endDate: DateTime(2026, 7, 30),
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
    await repository.setTaskCompleted(task.id, true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWith((ref) async => repository),
          scriptureRepositoryProvider.overrideWith(
            (ref) async => FakeRepositoryForPassage(),
          ),
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
          home: PlansScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('已完成计划'));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('read-task-${task.id}')), findsOneWidget);
    expect(find.byKey(Key('recite-task-${task.id}')), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('returns from reading to the open plan detail sheet', (
    tester,
  ) async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final planId = await repository.createPlan(
      NewMemorizationPlan(
        title: '继续查看计划',
        translationId: 'eng-web',
        bookId: 'JHN',
        startChapter: 3,
        endChapter: 3,
        startDate: DateTime(2026, 7, 30),
        endDate: DateTime(2026, 7, 30),
        tasks: const [
          NewPlanTask(
            dayIndex: 0,
            startChapter: 3,
            startVerse: 16,
            endChapter: 4,
            endVerse: 2,
          ),
        ],
      ),
    );
    final task = (await repository.listTasks(planId)).single;
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const PlansScreen())],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWith((ref) async => repository),
          scriptureRepositoryProvider.overrideWith(
            (ref) async => FakeRepositoryForPassage(),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续查看计划'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('read-task-${task.id}')));
    await tester.pumpAndSettle();
    expect(find.text('约翰福音 3章'), findsOneWidget);
    expect(find.byKey(const Key('next-plan-passage-button')), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('每天背诵安排 · 1 天'), findsOneWidget);
    expect(find.byKey(Key('recite-task-${task.id}')), findsOneWidget);
  });

  testWidgets('plan recitation exposes the prepared quiz entry', (
    tester,
  ) async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final planId = await repository.createPlan(
      NewMemorizationPlan(
        title: '答题背诵计划',
        translationId: 'eng-web',
        bookId: 'JHN',
        startChapter: 3,
        endChapter: 3,
        startDate: DateTime(2026, 8, 12),
        endDate: DateTime(2026, 8, 12),
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
          scriptureRepositoryProvider.overrideWith(
            (ref) async => FakeRepositoryForPassage(),
          ),
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
          home: PlansScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('答题背诵计划'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('recite-task-${task.id}')));
    await tester.pump();

    expect(find.byKey(const Key('today-quiz-entry-button')), findsOneWidget);
  });
}
