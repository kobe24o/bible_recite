import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../plans/application/plan_providers.dart';
import '../../plans/domain/plan_models.dart';
import '../application/scripture_providers.dart';
import '../domain/scripture_models.dart';
import '../domain/scripture_repository.dart';
import '../domain/scripture_search.dart';
import 'book_grid.dart';
import 'chapter_grid.dart';
import 'translation_selector.dart';

class ScriptureBrowserScreen extends ConsumerStatefulWidget {
  const ScriptureBrowserScreen({super.key});

  @override
  ConsumerState<ScriptureBrowserScreen> createState() =>
      _ScriptureBrowserScreenState();
}

class _ScriptureBrowserScreenState
    extends ConsumerState<ScriptureBrowserScreen> {
  String? _translationId;
  bool? _newTestament = false;
  BibleBook? _book;
  int? _chapter;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(scriptureRepositoryProvider);
    final bookNames = ref.watch(bookNameCatalogProvider);
    final locale = Localizations.localeOf(context);
    return PopScope(
      canPop: _book == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _book != null) {
          setState(() {
            _book = null;
            _chapter = null;
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _book == null
              ? null
              : IconButton(
                  tooltip: '返回书卷',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => setState(() {
                    _book = null;
                    _chapter = null;
                  }),
                ),
          title: Text(AppLocalizations.of(context)?.bibleTitle ?? 'Bible'),
        ),
        body: repository.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => const _ErrorView(),
          data: (repository) => FutureBuilder(
            future: repository.listTranslations(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final translations = snapshot.data!;
              final translationId = _translationId ?? translations.first.id;
              return FutureBuilder(
                future: repository.listBooks(
                  translationId,
                  CanonId.protestant66,
                ),
                builder: (context, booksSnapshot) {
                  if (!booksSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final allBooks = booksSnapshot.data!
                      .map(
                        (book) => BibleBook(
                          osisId: book.osisId,
                          ordinal: book.ordinal,
                          name: bookNames.nameFor(book.osisId, locale),
                          chapterCount: book.chapterCount,
                        ),
                      )
                      .toList(growable: false);
                  final filtered = _newTestament == null
                      ? const <BibleBook>[]
                      : allBooks
                            .where(
                              (book) => _newTestament!
                                  ? book.ordinal >= 40
                                  : book.ordinal < 40,
                            )
                            .toList(growable: false);
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      TranslationSelector(
                        translations: translations,
                        value: translationId,
                        onChanged: (value) => setState(() {
                          _translationId = value;
                          _book = null;
                          _chapter = null;
                        }),
                      ),
                      const SizedBox(height: 16),
                      SegmentedButton<bool>(
                        emptySelectionAllowed: true,
                        segments: [
                          ButtonSegment(
                            value: false,
                            label: Text(
                              AppLocalizations.of(context)?.oldTestament ??
                                  'Old Testament',
                            ),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text(
                              AppLocalizations.of(context)?.newTestament ??
                                  'New Testament',
                            ),
                          ),
                        ],
                        selected: _newTestament == null ? {} : {_newTestament!},
                        onSelectionChanged: (selection) => setState(() {
                          _newTestament = selection.firstOrNull;
                          _book = null;
                          _chapter = null;
                        }),
                      ),
                      const SizedBox(height: 16),
                      if (_newTestament != null && _book == null)
                        BookGrid(
                          books: filtered,
                          selectedBookId: _book?.osisId,
                          onSelected: (book) => setState(() {
                            _book = book;
                            _chapter = null;
                          }),
                        ),
                      if (_book != null) ...[
                        const SizedBox(height: 20),
                        Text(
                          _book!.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        ChapterGrid(
                          chapterCount: _book!.chapterCount,
                          selectedChapter: _chapter,
                          onSelected: (chapter) {
                            setState(() => _chapter = chapter);
                            context.push(
                              '/bible/$translationId/${_book!.osisId}/$chapter',
                            );
                          },
                        ),
                      ],
                    ],
                  );
                },
              );
            },
          ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SearchBar(
            controller: _searchController,
            hintText: '搜索经文（精准匹配）',
            leading: const Icon(Icons.search_rounded),
            onSubmitted: (query) => _showSearchResults(query),
          ),
        ),
      ),
    );
  }

  Future<void> _showSearchResults(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final scripture = await ref.read(scriptureRepositoryProvider.future);
    final translations = await scripture.listTranslations();
    final translation = _translationId ?? translations.first.id;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _SearchResultsSheet(
        query: trimmed,
        translationId: translation,
        scripture: scripture,
        onOpen: (unit) {
          Navigator.pop(context);
          this.context.push(
            '/bible/$translation/${unit.start.osisBookId}/${unit.start.chapter}?verse=${unit.start.verse}&endVerse=${unit.end.verse}',
          );
        },
        onAdd: _addSearchVerseToPlan,
      ),
    );
  }

  Future<void> _addSearchVerseToPlan(VerseUnit unit) async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final catalog = ref.read(bookNameCatalogProvider);
    final title =
        '${catalog.chapterLabel(unit.start.osisBookId, unit.start.chapter, Localizations.localeOf(context))} 背诵计划';
    final repository = await ref.read(planRepositoryProvider.future);
    await repository.createPlan(
      NewMemorizationPlan(
        title: title,
        translationId: unit.translationId,
        bookId: unit.start.osisBookId,
        startChapter: unit.start.chapter,
        endChapter: unit.end.chapter,
        startDate: start,
        endDate: start,
        tasks: [
          NewPlanTask(
            dayIndex: 0,
            bookId: unit.start.osisBookId,
            startChapter: unit.start.chapter,
            startVerse: unit.start.verse,
            endChapter: unit.end.chapter,
            endVerse: unit.end.verse,
          ),
        ],
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已新建背诵计划')));
    }
  }
}

class _SearchResultsSheet extends StatelessWidget {
  const _SearchResultsSheet({
    required this.query,
    required this.translationId,
    required this.scripture,
    required this.onOpen,
    required this.onAdd,
  });
  final String query;
  final String translationId;
  final ScriptureRepository scripture;
  final ValueChanged<VerseUnit> onOpen;
  final Future<void> Function(VerseUnit) onAdd;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .72,
    child: FutureBuilder<List<VerseUnit>>(
      future: scripture.searchExactVerses(translationId, query),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final units = snapshot.data!;
        return ListView.builder(
          itemCount: units.length + 1,
          itemBuilder: (context, index) {
            if (index == 0)
              return ListTile(
                title: Text('“$query” · ${units.length} 条结果'),
                subtitle: const Text('点击阅读定位；长按加入计划'),
              );
            final unit = units[index - 1];
            return ListTile(
              title: Text(
                '${unit.start.osisBookId} ${unit.start.chapter}:${unit.start.verse}',
              ),
              subtitle: Text(
                unit.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => onOpen(unit),
              onLongPress: () async {
                await onAdd(unit);
                if (context.mounted) Navigator.pop(context);
              },
            );
          },
        );
      },
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView();

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      AppLocalizations.of(context)?.unableLoadBible ??
          'Unable to load the Bible',
    ),
  );
}
