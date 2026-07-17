import 'package:bible_recite/l10n/generated/app_localizations.dart';
import 'package:bible_recite/src/features/plans/application/plan_providers.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/statistics/domain/recitation_result.dart';
import 'package:bible_recite/src/features/statistics/presentation/statistics_screen.dart';
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

    await tester.tap(find.byKey(const Key('ebbinghaus-toggle')));
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(
      find.byKey(const Key('ebbinghaus-threshold')),
    );
    slider.onChanged!(0.85);
    slider.onChangeEnd!(0.85);
    await tester.pumpAndSettle();

    final settings = await repository.getEbbinghausSettings();
    expect(settings.enabled, isTrue);
    expect(settings.passThreshold, 0.85);
  });

  testWidgets('shows summary cards and recent recitation results', (
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
    expect(find.text('平均正确率 80%'), findsOneWidget);
    expect(find.textContaining('约翰福音 3:16–17'), findsOneWidget);
    expect(find.text('我的成就'), findsOneWidget);
    expect(find.text('初次开口'), findsOneWidget);
    expect(
      find.byKey(const Key('achievement-first_recitation-unlocked')),
      findsOneWidget,
    );
  });
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
