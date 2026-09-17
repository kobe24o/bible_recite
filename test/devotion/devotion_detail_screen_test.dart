import 'dart:convert';

import 'package:bible_recite/l10n/generated/app_localizations.dart';
import 'package:bible_recite/src/app/router.dart';
import 'package:bible_recite/src/features/plans/application/plan_providers.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/scripture/application/scripture_providers.dart';
import 'package:bible_recite/src/features/scripture/presentation/passage_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../scripture/scripture_browser_screen_test.dart'
    show FakeRepositoryForPassage;
import 'devotion_models_test.dart' show complete2026Json;

void main() {
  late Database database;
  late SqlitePlanRepository repository;
  final date = DateTime(2026, 9, 17);

  setUp(() async {
    database = sqlite3.openInMemory();
    repository = SqlitePlanRepository(database);
    final json = jsonDecode(complete2026Json) as Map<String, dynamic>;
    final days = json['years'][0]['days'] as List<dynamic>;
    (days.firstWhere((dynamic day) => day['date'] == '2026-09-17')
        as Map<String, dynamic>)['passages'] = [
      {
        'bookId': 'JHN',
        'startChapter': 3,
        'startVerse': 16,
        'endChapter': 4,
        'endVerse': 3,
      },
      {
        'bookId': 'JHN',
        'startChapter': 4,
        'startVerse': 8,
        'endChapter': 4,
        'endVerse': 9,
      },
      {
        'bookId': 'PSA',
        'startChapter': 1,
        'startVerse': 1,
        'endChapter': 1,
        'endVerse': 2,
      },
    ];
    await repository.cacheDevotionManifest(jsonEncode(json));
  });
  tearDown(() => repository.close());

  Future<void> pumpDetail(WidgetTester tester) async {
    appRouter.go('/devotion/2026-09-17');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWith((ref) async => repository),
          scriptureRepositoryProvider.overrideWith(
            (ref) async => FakeRepositoryForPassage(),
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
  }

  testWidgets('detail loads a note and persists explicit and automatic edits', (
    tester,
  ) async {
    await repository.saveDevotionNote(date, '原有笔记');
    await pumpDetail(tester);
    expect(find.text('原有笔记'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('devotion-note-input')),
      '愿我专心聆听',
    );
    await tester.tap(find.byKey(const Key('save-devotion-note')));
    await tester.pumpAndSettle();
    expect((await repository.devotionNoteFor(date))!.content, '愿我专心聆听');
    await tester.enterText(
      find.byKey(const Key('devotion-note-input')),
      '自动保存的领受',
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect((await repository.devotionNoteFor(date))!.content, '自动保存的领受');
    expect(find.text('已保存'), findsOneWidget);
  });

  testWidgets('save errors preserve typed notes for retry', (tester) async {
    database.execute(
      "CREATE TRIGGER reject_note BEFORE INSERT ON devotion_note BEGIN SELECT RAISE(FAIL, 'disk unavailable'); END",
    );
    await pumpDetail(tester);
    await tester.enterText(
      find.byKey(const Key('devotion-note-input')),
      '保留这段文字',
    );
    await tester.tap(find.byKey(const Key('save-devotion-note')));
    await tester.pumpAndSettle();
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(find.text('保留这段文字'), findsOneWidget);
    database.execute('DROP TRIGGER reject_note');
    await tester.tap(find.byKey(const Key('save-devotion-note')));
    await tester.pumpAndSettle();
    expect((await repository.devotionNoteFor(date))!.content, '保留这段文字');
  });

  testWidgets(
    'detail passes exact cross chapter and disjoint groups to reading',
    (tester) async {
      await pumpDetail(tester);
      await tester.tap(find.text('约翰福音 3:16–4:3'));
      await tester.pumpAndSettle();
      final passage = tester.widget<PassageScreen>(find.byType(PassageScreen));
      expect(passage.bookId, 'JHN');
      expect(passage.chapter, 3);
      expect(passage.initialEndChapter, isNull);
      expect(
        passage.planTaskGroups.map(
          (group) => '${group.bookId}:${group.chapter}',
        ),
        ['JHN:3', 'JHN:4', 'PSA:1'],
      );
      expect(passage.planTaskGroups[0].includesVerse(15), isFalse);
      expect(passage.planTaskGroups[0].includesVerse(16), isTrue);
      expect(passage.planTaskGroups[1].includesVerse(3), isTrue);
      expect(passage.planTaskGroups[1].includesVerse(4), isFalse);
      expect(passage.planTaskGroups[1].includesVerse(8), isTrue);
    },
  );
}
