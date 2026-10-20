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
    'Plans opens the calendar at today and preserves the browsed month',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      await repository.cacheDevotionManifest(complete2026Json);
      appRouter.go('/plans');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            planRepositoryProvider.overrideWith((ref) async => repository),
            devotionClockProvider.overrideWithValue(
              () => DateTime(2026, 9, 17),
            ),
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
      expect(
        find.byKey(const Key('devotion-note-day-2026-09-17')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('previous-devotion-note-month')));
      await tester.pumpAndSettle();
      expect(find.text('2026年8月'), findsOneWidget);
      final day = find.byKey(const Key('devotion-note-day-2026-08-17'));
      await tester.ensureVisible(day);
      await tester.tap(day);
      await tester.pumpAndSettle();
      ProviderScope.containerOf(
        tester.element(day),
      ).read(devotionRevisionProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(find.text('2026年8月'), findsOneWidget);
      expect(
        find.byKey(const Key('devotion-note-day-2026-08-17')),
        findsOneWidget,
      );
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
              devotionClockProvider.overrideWithValue(
                () => DateTime(2026, 9, 17),
              ),
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
