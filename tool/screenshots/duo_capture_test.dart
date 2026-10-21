import 'dart:io';
import 'dart:ui' as ui;

import 'package:bible_recite/l10n/generated/app_localizations.dart';
import 'package:bible_recite/src/app/responsive_shell.dart';
import 'package:bible_recite/src/features/dashboard/presentation/today_screen.dart';
import 'package:bible_recite/src/features/plans/application/plan_providers.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/plans/presentation/plans_screen.dart';
import 'package:bible_recite/src/features/scripture/application/scripture_providers.dart';
import 'package:bible_recite/src/features/scripture/data/sqlite_scripture_repository.dart';
import 'package:bible_recite/src/features/scripture/presentation/scripture_browser_screen.dart';
import 'package:bible_recite/src/features/statistics/presentation/statistics_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SqliteScriptureRepository scripture;
  setUpAll(() async {
    final registry = await ScripturePackRegistry.fromDirectories({
      for (final id in ['cmn-cu89s', 'cmn-cu89t', 'eng-web'])
        id: Directory('assets/scripture/$id'),
    });
    scripture = SqliteScriptureRepository(registry: registry);
    final font = FontLoader('DuoSystemFont');
    font.addFont(
      File(
        '/System/Library/Fonts/STHeiti Medium.ttc',
      ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
    await font.load();
  });

  testWidgets('capture production screens at iPhone Duo portrait size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1398, 2034);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const ResponsiveShell(child: TodayScreen()),
        ),
        GoRoute(
          path: '/bible',
          builder: (_, _) =>
              const ResponsiveShell(child: ScriptureBrowserScreen()),
        ),
        GoRoute(
          path: '/plans',
          builder: (_, _) => const ResponsiveShell(child: PlansScreen()),
        ),
        GoRoute(
          path: '/statistics',
          builder: (_, _) => const ResponsiveShell(
            child: StatisticsScreen(view: StatisticsScreenView.learningData),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    final captureKey = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWith((ref) async => repository),
          scriptureRepositoryProvider.overrideWith((ref) async => scripture),
        ],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          theme: ThemeData(
            platform: TargetPlatform.iOS,
            fontFamily: 'DuoSystemFont',
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF355E3B),
            ),
          ),
          builder: (_, child) =>
              RepaintBoundary(key: captureKey, child: child!),
        ),
      ),
    );
    for (final page in const [
      ('/', '01-start-reciting.png'),
      ('/bible', '02-scripture-library.png'),
      ('/plans', '03-memorization-plans.png'),
      ('/statistics', '04-learning-progress.png'),
    ]) {
      router.go(page.$1);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary =
          captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      expect(image.width, 1398);
      expect(image.height, 2034);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await tester.runAsync(() async {
        final dir = Directory('build/iphone_duo')..createSync(recursive: true);
        await File(
          '${dir.path}/${page.$2}',
        ).writeAsBytes(png.buffer.asUint8List());
      });
      image.dispose();
    }
    await tester.pumpWidget(const SizedBox());
  });
}
