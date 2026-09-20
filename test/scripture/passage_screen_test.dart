import 'package:bible_recite/l10n/generated/app_localizations.dart';
import 'package:bible_recite/src/features/devotion/domain/devotion_models.dart';
import 'package:bible_recite/src/features/plans/domain/plan_models.dart';
import 'package:bible_recite/src/features/plans/domain/plan_task_chapter_groups.dart';
import 'package:bible_recite/src/features/scripture/application/scripture_providers.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:bible_recite/src/features/scripture/presentation/passage_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'scripture_browser_screen_test.dart' show FakeRepositoryForPassage;

void main() {
  testWidgets('cross chapter devotion highlights exact endpoints only', (
    tester,
  ) async {
    final day = DevotionDay(
      date: DateTime(2026, 9, 17),
      passages: const [
        DevotionPassage(
          bookId: 'JHN',
          startChapter: 3,
          startVerse: 16,
          endChapter: 4,
          endVerse: 3,
        ),
        DevotionPassage(
          bookId: 'JHN',
          startChapter: 4,
          startVerse: 8,
          endChapter: 4,
          endVerse: 9,
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scriptureRepositoryProvider.overrideWith(
            (ref) async => FakeRepositoryForPassage(
              chapterUnitsByReference: {
                'JHN:3': [
                  for (final verse in [15, 16, 36])
                    _planReadingUnit(bookId: 'JHN', chapter: 3, verse: verse),
                ],
                'JHN:4': [
                  for (final verse in [1, 3, 4, 8, 9, 10])
                    _planReadingUnit(bookId: 'JHN', chapter: 4, verse: verse),
                ],
              },
            ),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PassageScreen(
            translationId: 'eng-web',
            bookId: 'JHN',
            chapter: 3,
            planTaskGroups: day.chapterGroups(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    void expectHighlighted(String reference, bool highlighted) {
      final text = find.text('Reading $reference');
      final material = tester.widget<Material>(
        find.ancestor(of: text, matching: find.byType(Material)).first,
      );
      final highlight = Theme.of(
        tester.element(text),
      ).colorScheme.primaryContainer;
      expect(material.color == highlight, highlighted, reason: reference);
    }

    expectHighlighted('JHN 3:15', false);
    expectHighlighted('JHN 3:16', true);
    expectHighlighted('JHN 3:36', true);
    await tester.tap(find.byKey(const Key('next-plan-passage-button')));
    await tester.pumpAndSettle();
    expectHighlighted('JHN 4:1', true);
    expectHighlighted('JHN 4:3', true);
    expectHighlighted('JHN 4:4', false);
    expectHighlighted('JHN 4:8', true);
    expectHighlighted('JHN 4:9', true);
    expectHighlighted('JHN 4:10', false);
  });
  testWidgets('renders a local chapter without network access', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
          supportedLocales: [Locale('zh'), Locale('en')],
          home: PassageScreen(
            translationId: 'eng-web',
            bookId: 'JHN',
            chapter: 3,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('约翰福音 3章'), findsOneWidget);
    expect(find.text('JHN 3'), findsNothing);
    expect(find.text('开始背诵'), findsOneWidget);
    expect(find.text('加入计划'), findsOneWidget);
    expect(find.textContaining('For God so loved the world'), findsOneWidget);
    expect(find.text('16'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-to-plan-button')));
    await tester.pumpAndSettle();
    expect(find.text('加入背诵计划'), findsOneWidget);
    expect(find.text('新建计划'), findsOneWidget);
    await tester.tap(find.text('新建计划'));
    await tester.pumpAndSettle();
    expect(find.text('编辑背诵计划'), findsOneWidget);
    expect(find.text('约翰福音 3章'), findsWidgets);
  });

  testWidgets('long press enables multi-verse selection', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
          supportedLocales: [Locale('zh'), Locale('en')],
          home: PassageScreen(
            translationId: 'eng-web',
            bookId: 'JHN',
            chapter: 3,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('16'));
    await tester.pumpAndSettle();

    expect(find.text('已选择 1 节'), findsOneWidget);
    expect(find.text('加入背诵计划（1）'), findsOneWidget);
  });

  testWidgets(
    'long pressing a devotion verse offers plan and formatted copy actions',
    (tester) async {
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied =
                  (call.arguments as Map<Object?, Object?>)['text'] as String?;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final day = DevotionDay(
        date: DateTime(2026, 9, 17),
        passages: const [
          DevotionPassage(
            bookId: 'JHN',
            startChapter: 3,
            startVerse: 16,
            endChapter: 3,
            endVerse: 16,
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scriptureRepositoryProvider.overrideWith(
              (ref) async => FakeRepositoryForPassage(),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: PassageScreen(
              translationId: 'eng-web',
              bookId: 'JHN',
              chapter: 3,
              planTaskGroups: day.chapterGroups(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('16'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add-to-plan-button')), findsOneWidget);
      expect(find.byKey(const Key('copy-selected-verses')), findsOneWidget);
      await tester.tap(find.byKey(const Key('copy-selected-verses')));

      expect(copied, '（约翰福音 3:16）  For God so loved the world');
    },
  );

  testWidgets(
    'search target is centered with a green background and only its keyword bold',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
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
            supportedLocales: [Locale('zh'), Locale('en')],
            home: PassageScreen(
              translationId: 'eng-web',
              bookId: 'JHN',
              chapter: 3,
              initialVerse: 16,
              searchQuery: 'loved',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final verseText = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.textSpan?.toPlainText() == 'For God so loved the world',
      );
      expect(verseText, findsOneWidget);
      expect(tester.widget<Text>(verseText).textAlign, TextAlign.center);

      final materials = tester.widgetList<Material>(
        find.ancestor(of: verseText, matching: find.byType(Material)),
      );
      final colorScheme = Theme.of(tester.element(verseText)).colorScheme;
      expect(
        materials.any(
          (material) => material.color == colorScheme.primaryContainer,
        ),
        isTrue,
      );
    },
  );

  testWidgets('centers a searched verse in a long reading viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      passageTestApp(initialVerse: 20, units: longChapterUnits()),
    );
    await tester.pumpAndSettle();

    expectVerseCentered(tester, '20');
  });

  testWidgets('centers the first planned verse in the reading viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      passageTestApp(initialVerse: 1, units: longChapterUnits()),
    );
    await tester.pumpAndSettle();

    expectVerseCentered(tester, '1');
  });

  testWidgets('highlights every verse in a cross-chapter plan range', (
    tester,
  ) async {
    final units = [
      crossChapterUnit(chapter: 3, verse: 30),
      crossChapterUnit(chapter: 3, verse: 31),
      crossChapterUnit(chapter: 3, verse: 36),
      crossChapterUnit(chapter: 4, verse: 1),
      crossChapterUnit(chapter: 4, verse: 2),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scriptureRepositoryProvider.overrideWith(
            (ref) async => FakeRepositoryForPassage(passageUnits: units),
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
          supportedLocales: [Locale('zh'), Locale('en')],
          home: PassageScreen(
            translationId: 'eng-web',
            bookId: 'JHN',
            chapter: 3,
            initialVerse: 30,
            initialEndChapter: 4,
            initialEndVerse: 2,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final selectedColor = Theme.of(
      tester.element(find.text('Cross chapter 3:30')),
    ).colorScheme.primaryContainer;
    for (final unit in units) {
      final text = find.text(
        'Cross chapter ${unit.start.chapter}:${unit.start.verse}',
      );
      final material = tester.widget<Material>(
        find.ancestor(of: text, matching: find.byType(Material)).first,
      );
      expect(material.color, selectedColor);
    }
  });

  testWidgets(
    'shows a whole chapter with task blocks highlighted and moves to the next task chapter',
    (tester) async {
      final chapterThree = [
        for (var verse = 1; verse <= 4; verse++)
          _planReadingUnit(bookId: 'JHN', chapter: 3, verse: verse),
      ];
      final genesisOne = [
        _planReadingUnit(bookId: 'GEN', chapter: 1, verse: 1),
      ];
      final groups = groupPlanTaskBlocksByChapter(const [
        PlanTaskBlock(
          id: 1,
          taskId: 1,
          sortOrder: 0,
          bookId: 'JHN',
          startChapter: 3,
          startVerse: 1,
          endChapter: 3,
          endVerse: 1,
        ),
        PlanTaskBlock(
          id: 2,
          taskId: 1,
          sortOrder: 1,
          bookId: 'JHN',
          startChapter: 3,
          startVerse: 3,
          endChapter: 3,
          endVerse: 3,
        ),
        PlanTaskBlock(
          id: 3,
          taskId: 1,
          sortOrder: 2,
          bookId: 'GEN',
          startChapter: 1,
          startVerse: 1,
          endChapter: 1,
          endVerse: 1,
        ),
      ]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scriptureRepositoryProvider.overrideWith(
              (ref) async => FakeRepositoryForPassage(
                chapterUnitsByReference: {
                  'JHN:3': chapterThree,
                  'GEN:1': genesisOne,
                },
              ),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: const [Locale('zh'), Locale('en')],
            home: PassageScreen(
              translationId: 'eng-web',
              bookId: 'JHN',
              chapter: 3,
              planTaskGroups: groups,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reading JHN 3:1'), findsOneWidget);
      expect(find.text('Reading JHN 3:2'), findsOneWidget);
      expect(find.text('Reading JHN 3:3'), findsOneWidget);
      expect(find.text('Reading JHN 3:4'), findsOneWidget);
      final selectedColor = Theme.of(
        tester.element(find.text('Reading JHN 3:1')),
      ).colorScheme.primaryContainer;
      for (final verse in [1, 3]) {
        final text = find.text('Reading JHN 3:$verse');
        final material = tester.widget<Material>(
          find.ancestor(of: text, matching: find.byType(Material)).first,
        );
        expect(material.color, selectedColor);
      }
      await tester.tap(find.byKey(const Key('next-plan-passage-button')));
      await tester.pumpAndSettle();
      expect(find.text('创世记 1章'), findsOneWidget);
      expect(find.text('Reading GEN 1:1'), findsOneWidget);
      expect(
        find.byKey(const Key('previous-plan-passage-button')),
        findsOneWidget,
      );
    },
  );

  testWidgets('centers the first scheduled verse when reading a plan chapter', (
    tester,
  ) async {
    final chapter = [
      for (var verse = 1; verse <= 40; verse++)
        _planReadingUnit(bookId: 'JHN', chapter: 3, verse: verse),
    ];
    final groups = groupPlanTaskBlocksByChapter(const [
      PlanTaskBlock(
        id: 1,
        taskId: 1,
        sortOrder: 0,
        bookId: 'JHN',
        startChapter: 3,
        startVerse: 20,
        endChapter: 3,
        endVerse: 20,
      ),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scriptureRepositoryProvider.overrideWith(
            (ref) async => FakeRepositoryForPassage(
              chapterUnitsByReference: {'JHN:3': chapter},
            ),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh'), Locale('en')],
          home: PassageScreen(
            translationId: 'eng-web',
            bookId: 'JHN',
            chapter: 3,
            planTaskGroups: groups,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final target = find.text('Reading JHN 3:20', skipOffstage: false);
    final reader = find.byKey(const Key('passage-reader'));
    expect(target, findsOneWidget);
    expect(
      (tester.getCenter(target).dy - tester.getCenter(reader).dy).abs(),
      lessThan(80),
    );
  });

  testWidgets(
    'opens the date editor when creating a plan from selected verses',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
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
            supportedLocales: [Locale('zh'), Locale('en')],
            home: PassageScreen(
              translationId: 'eng-web',
              bookId: 'JHN',
              chapter: 3,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.text('16'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-to-plan-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建计划'));
      await tester.pumpAndSettle();

      expect(find.text('编辑背诵计划'), findsOneWidget);
      expect(find.byKey(const Key('plan-start-date')), findsOneWidget);
      expect(find.byKey(const Key('plan-end-date')), findsOneWidget);
    },
  );

  testWidgets(
    'keeps chapter quiz entry disabled while its question is pending',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
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
            supportedLocales: [Locale('zh'), Locale('en')],
            home: PassageScreen(
              translationId: 'eng-web',
              bookId: 'JHN',
              chapter: 3,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final startQuiz = find.byKey(const Key('start-quiz-button'));
      expect(startQuiz, findsOneWidget);
      expect(tester.widget<FilledButton>(startQuiz).onPressed, isNull);
    },
  );

  testWidgets('swiping left opens the next chapter in the same book', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/bible/eng-web/JHN/3',
      routes: [
        GoRoute(
          path: '/bible/:translation/:book/:chapter',
          builder: (_, state) => PassageScreen(
            translationId: state.pathParameters['translation']!,
            bookId: state.pathParameters['book']!,
            chapter: int.parse(state.pathParameters['chapter']!),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
          supportedLocales: const [Locale('zh'), Locale('en')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.fling(
      find.byKey(const Key('passage-reader')),
      const Offset(-500, 0),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.text('约翰福音 4章'), findsOneWidget);
    expect(
      router.routeInformationProvider.value.uri.path,
      '/bible/eng-web/JHN/4',
    );
  });
}

Widget passageTestApp({
  required int initialVerse,
  required List<VerseUnit> units,
}) => ProviderScope(
  overrides: [
    scriptureRepositoryProvider.overrideWith(
      (ref) async => FakeRepositoryForPassage(chapterUnits: units),
    ),
  ],
  child: MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: const [Locale('zh'), Locale('en')],
    home: PassageScreen(
      translationId: 'eng-web',
      bookId: 'JHN',
      chapter: 3,
      initialVerse: initialVerse,
    ),
  ),
);

void expectVerseCentered(WidgetTester tester, String label) {
  final target = find.text(label, skipOffstage: false);
  final reader = find.byKey(const Key('passage-reader'));
  expect(target, findsOneWidget);
  expect(
    (tester.getCenter(target).dy - tester.getCenter(reader).dy).abs(),
    lessThan(80),
  );
}

List<VerseUnit> longChapterUnits() => List.generate(
  40,
  (index) => VerseUnit(
    translationId: 'eng-web',
    start: (
      canonId: CanonId.protestant66,
      osisBookId: 'JHN',
      chapter: 3,
      verse: index + 1,
    ),
    end: (
      canonId: CanonId.protestant66,
      osisBookId: 'JHN',
      chapter: 3,
      verse: index + 1,
    ),
    text: 'Verse ${index + 1} ' * 20,
    status: SourceTextStatus.present,
  ),
);

VerseUnit crossChapterUnit({required int chapter, required int verse}) =>
    VerseUnit(
      translationId: 'eng-web',
      start: (
        canonId: CanonId.protestant66,
        osisBookId: 'JHN',
        chapter: chapter,
        verse: verse,
      ),
      end: (
        canonId: CanonId.protestant66,
        osisBookId: 'JHN',
        chapter: chapter,
        verse: verse,
      ),
      text: 'Cross chapter $chapter:$verse',
      status: SourceTextStatus.present,
    );

VerseUnit _planReadingUnit({
  required String bookId,
  required int chapter,
  required int verse,
}) => VerseUnit(
  translationId: 'eng-web',
  start: (
    canonId: CanonId.protestant66,
    osisBookId: bookId,
    chapter: chapter,
    verse: verse,
  ),
  end: (
    canonId: CanonId.protestant66,
    osisBookId: bookId,
    chapter: chapter,
    verse: verse,
  ),
  text: 'Reading $bookId $chapter:$verse',
  status: SourceTextStatus.present,
);
