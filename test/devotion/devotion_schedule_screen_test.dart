import 'package:bible_recite/l10n/generated/app_localizations.dart';
import 'package:bible_recite/src/app/router.dart';
import 'package:bible_recite/src/features/devotion/application/devotion_providers.dart';
import 'package:bible_recite/src/features/devotion/data/devotion_feed_client.dart';
import 'package:bible_recite/src/features/devotion/presentation/devotion_schedule_screen.dart';
import 'package:bible_recite/src/features/plans/application/plan_providers.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'devotion_models_test.dart' show complete2026Json;

void main() {
  testWidgets(
    'Plans opens the schedule at today and allows browsing earlier days',
    (tester) async {
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      await repository.cacheDevotionManifest(complete2026Json);
      appRouter.go('/plans');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            planRepositoryProvider.overrideWith((ref) async => repository),
            devotionTodayProvider.overrideWithValue(DateTime(2026, 9, 17)),
          ],
          child: MaterialApp.router(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: appRouter,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-devotion-schedule')));
      await tester.pumpAndSettle();
      const date = '2026-09-17';
      expect(
        find.byKey(Key('devotion-day-$date')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('今天'), findsOneWidget);
      final list = find.byKey(const Key('devotion-schedule-list'));
      final controller = tester.widget<SingleChildScrollView>(list).controller!;
      final initialOffset = controller.offset;
      await tester.drag(list, const Offset(0, 400));
      await tester.pumpAndSettle();
      final browsedOffset = controller.offset;
      expect(browsedOffset, lessThan(initialOffset));
      ProviderScope.containerOf(
        tester.element(list),
      ).read(devotionRevisionProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(controller.offset, browsedOffset);
    },
  );

  for (final cached in [false, true]) {
    testWidgets(
      'failed sync ${cached ? 'keeps cached days' : 'offers retry on a new install'}',
      (tester) async {
        final repository = SqlitePlanRepository(sqlite3.openInMemory());
        addTearDown(repository.close);
        if (cached) await repository.cacheDevotionManifest(complete2026Json);
        var online = false;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              planRepositoryProvider.overrideWith((ref) async => repository),
              devotionTodayProvider.overrideWithValue(DateTime(2026, 9, 17)),
              devotionFeedClientProvider.overrideWithValue(
                DevotionFeedClient(
                  loader: (_) async {
                    if (!online) throw Exception('offline');
                    return complete2026Json;
                  },
                ),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const DevotionScheduleScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('sync-devotion')));
        await tester.pumpAndSettle();
        expect(find.text('重试同步'), findsOneWidget);
        expect(
          find.byKey(const Key('devotion-day-2026-09-17')),
          cached ? findsOneWidget : findsNothing,
        );
        online = true;
        await tester.tap(find.byKey(const Key('sync-devotion')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('devotion-day-2026-09-17')).hitTestable(),
          findsOneWidget,
        );
        expect(find.text('重试同步'), findsNothing);
      },
    );
  }
}
