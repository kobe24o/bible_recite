import 'package:bible_recite/l10n/generated/app_localizations.dart';
import 'package:bible_recite/src/features/scripture/application/scripture_providers.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_repository.dart';
import 'package:bible_recite/src/features/scripture/presentation/scripture_browser_screen.dart';
import 'package:bible_recite/src/features/scripture/presentation/book_grid.dart';
import 'package:bible_recite/src/features/scripture/presentation/chapter_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('selects a book, hides the book grid, and restores it on return', (
    tester,
  ) async {
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
          home: ScriptureBrowserScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('World English Bible'), findsOneWidget);
    expect(find.text('创世记'), findsOneWidget);
    expect(find.byType(BookGrid), findsOneWidget);
    await tester.tap(find.text('新约'));
    await tester.pumpAndSettle();
    expect(find.text('约翰福音'), findsOneWidget);
    expect(find.text('JHN'), findsNothing);
    await tester.tap(find.text('约翰福音'));
    await tester.pumpAndSettle();

    // Selecting a book intentionally replaces the book grid with its chapters,
    // so the user has a shorter path to the desired chapter.
    expect(find.byType(BookGrid), findsNothing);
    expect(find.text('约翰福音'), findsOneWidget);
    expect(find.text('第 3 章'), findsOneWidget);

    await tester.tap(find.byTooltip('返回书卷'));
    await tester.pumpAndSettle();
    expect(find.byType(BookGrid), findsOneWidget);
    expect(find.text('约翰福音'), findsOneWidget);
  });

  testWidgets('book and chapter grids expose selected states', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              BookGrid(
                books: [
                  BibleBook(
                    osisId: 'JHN',
                    ordinal: 43,
                    name: '约翰福音',
                    chapterCount: 21,
                  ),
                ],
                selectedBookId: 'JHN',
                onSelected: (_) {},
              ),
              ChapterGrid(
                chapterCount: 3,
                selectedChapter: 2,
                onSelected: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('selected-book-JHN')), findsOneWidget);
    expect(find.byKey(const Key('selected-chapter-2')), findsOneWidget);
  });
}

final class FakeRepositoryForPassage implements ScriptureRepository {
  FakeRepositoryForPassage({this.chapterUnits});

  final List<VerseUnit>? chapterUnits;

  final translation = TranslationInfo(
    id: 'eng-web',
    languageTag: 'en',
    name: 'World English Bible',
    canonId: CanonId.protestant66,
    packId: 'fixture',
    versificationId: 'fixture-v1',
    semanticSha256: 'a' * 64,
  );

  @override
  Future<TranslationInfo> getTranslation(String id) async => translation;

  @override
  Future<List<TranslationInfo>> listTranslations() async => [translation];

  @override
  Future<List<BibleBook>> listBooks(
    String translationId,
    CanonId canonId,
  ) async => [
    BibleBook(osisId: 'GEN', ordinal: 1, name: 'GEN', chapterCount: 50),
    BibleBook(osisId: 'JHN', ordinal: 43, name: 'JHN', chapterCount: 21),
  ];

  @override
  Future<List<VerseUnit>> getChapter(
    String translationId,
    String osisBookId,
    int chapter,
  ) async =>
      chapterUnits ??
      [
        VerseUnit(
          translationId: translationId,
          start: (
            canonId: CanonId.protestant66,
            osisBookId: osisBookId,
            chapter: chapter,
            verse: 16,
          ),
          end: (
            canonId: CanonId.protestant66,
            osisBookId: osisBookId,
            chapter: chapter,
            verse: 16,
          ),
          text: 'For God so loved the world',
          status: SourceTextStatus.present,
        ),
      ];

  @override
  Future<Passage> getPassage(String translationId, PassageRange range) async =>
      Passage(
        range: range,
        translationId: translationId,
        units: [
          VerseUnit(
            translationId: translationId,
            start: range.start,
            end: range.start,
            text: 'For God so loved the world',
            status: SourceTextStatus.present,
          ),
        ],
      );

  @override
  Future<SelectedPassage> getSelection(
    String translationId,
    PassageSelection selection,
  ) => throw UnimplementedError();

  @override
  Future<ParallelPassage> resolveParallelPassage(
    LocatedPassageRange sourceRange,
    String targetTranslationId,
  ) => throw UnimplementedError();
}
