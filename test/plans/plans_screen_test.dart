import 'package:bible_recite/l10n/generated/app_localizations.dart';
import 'package:bible_recite/src/features/plans/presentation/plans_screen.dart';
import 'package:bible_recite/src/features/plans/application/plan_providers.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/plans/domain/plan_models.dart';
import 'package:bible_recite/src/features/scripture/application/scripture_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
    expect(find.text('自定义计划'), findsOneWidget);
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

    expect(find.byKey(Key('edit-plan-$planId')), findsOneWidget);
    expect(find.text('云端'), findsOneWidget);
    await tester.tap(find.byKey(Key('edit-plan-$planId')));
    await tester.pumpAndSettle();
    expect(find.text('编辑背诵计划'), findsOneWidget);
    expect(find.byKey(const Key('plan-translation')), findsOneWidget);
    expect(find.byKey(const Key('locked-plan-content-note')), findsOneWidget);
    expect(find.byKey(const Key('delete-plan-button')), findsOneWidget);
  });
}
