import 'package:bible_recite/src/app/app.dart';
import 'package:bible_recite/src/app/router.dart';
import 'package:bible_recite/src/features/update/application/update_providers.dart';
import 'package:bible_recite/src/features/update/presentation/about_screen.dart';
import 'package:bible_recite/src/features/update/presentation/update_available_notification.dart';
import 'package:bible_recite/src/features/plans/application/plan_providers.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/plans/domain/cloud_plan_manifest.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  testWidgets('opens About when the update notification is selected', (
    tester,
  ) async {
    appRouter.go('/');
    await tester.pumpWidget(const ProviderScope(child: BibleReciteApp()));
    await tester.pump();

    UpdateAvailableNotification.openUpdatePage();
    await tester.pump();

    expect(appRouter.routerDelegate.currentConfiguration.uri.path, '/about');
  });

  testWidgets('routes the update notification payload after the app is ready', (
    tester,
  ) async {
    appRouter.go('/');
    await tester.pumpWidget(const ProviderScope(child: BibleReciteApp()));
    await tester.pump();

    UpdateAvailableNotification.handlePayload('open-update-about');
    await tester.pump();

    expect(appRouter.routerDelegate.currentConfiguration.uri.path, '/about');
  });

  testWidgets(
    'downloaded-update notification uses the registered installer action',
    (tester) async {
      var installs = 0;
      UpdateAvailableNotification.setDownloadedTapHandler(() async {
        installs++;
      });

      UpdateAvailableNotification.handlePayload('install-downloaded-update');
      await tester.pump();

      expect(installs, 1);
    },
  );

  setUp(() => appRouter.go('/'));
  tearDown(() => appRouter.go('/'));

  testWidgets('all four Chinese navigation tabs open localized pages', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    appRouter.go('/');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWith((ref) async => repository),
        ],
        child: const BibleReciteApp(locale: Locale('zh')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('今日任务'), findsOneWidget);

    await tester.tap(find.text('计划'));
    await tester.pumpAndSettle();
    expect(find.text('背诵计划'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '我的'), findsAtLeastNWidgets(1));

    await tester.tap(find.text('今日'));
    await tester.pumpAndSettle();
    expect(find.text('今日任务'), findsOneWidget);
  });

  testWidgets('About is the only route that checks for updates', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final actions = _CountingUpdateActions();
    appRouter.go('/');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWith((ref) async => repository),
          aboutUpdateActionsProvider.overrideWith((ref) => actions),
        ],
        child: const BibleReciteApp(locale: Locale('en')),
      ),
    );
    await tester.pumpAndSettle();
    expect(actions.checks, 0);

    appRouter.go('/about');
    await tester.pumpAndSettle();
    expect(actions.checks, 1);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
  });

  testWidgets('My About entry and scripture sources select real destinations', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final actions = _CountingUpdateActions();
    appRouter.go('/statistics');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWith((ref) async => repository),
          aboutUpdateActionsProvider.overrideWith((ref) => actions),
          bundledCloudPlanManifestProvider.overrideWith(
            (ref) async => const CloudPlanManifest(
              protocolVersion: 1,
              publisher: 'test',
              plans: [],
            ),
          ),
          installedPackageInfoProvider.overrideWith(
            (ref) async => PackageInfo(
              appName: 'Bible Recite',
              packageName: 'app.biblerecite',
              version: '1.0.4',
              buildNumber: '7',
              buildSignature: '',
            ),
          ),
        ],
        child: const BibleReciteApp(locale: Locale('en')),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
    final about = find.byKey(const Key('about-open')).last;
    await tester.ensureVisible(about);
    await tester.tap(about);
    await tester.pumpAndSettle();

    expect(appRouter.routerDelegate.currentConfiguration.uri.path, '/about');
    expect(find.widgetWithText(AppBar, 'About'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );

    appRouter.go('/about/scripture-sources');
    await tester.pumpAndSettle();

    expect(
      appRouter.routerDelegate.currentConfiguration.uri.path,
      '/about/scripture-sources',
    );
    expect(find.widgetWithText(AppBar, 'Scripture sources'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
  });
}

final class _CountingUpdateActions implements AboutUpdateActions {
  var checks = 0;

  @override
  Future<void> cancelDownload() async {}

  @override
  Future<void> cancelCellularDownload() async {}

  @override
  Future<void> check() async => checks++;

  @override
  Future<void> confirmCellularDownload() async {}

  @override
  Future<void> install() async {}

  @override
  Future<void> startDownload() async {}
}
