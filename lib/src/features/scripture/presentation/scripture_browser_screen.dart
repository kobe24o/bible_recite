import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../plans/application/plan_providers.dart';
import '../../plans/domain/plan_models.dart';
import '../application/scripture_providers.dart';
import '../domain/scripture_models.dart';
import '../domain/book_name_catalog.dart';
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
  List<String> _recentSearches = const [];
  bool _showRecentSearches = false;

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
  }

  Future<void> _loadRecentSearches() async {
    final repository = await ref.read(planRepositoryProvider.future);
    try {
      final raw = await repository.getSetting(
        'recent_scripture_searches',
        '[]',
      );
      final values = jsonDecode(raw);
      if (values is! List || !mounted) return;
      setState(
        () => _recentSearches = [
          for (final value in values)
            if (value is String && value.trim().isNotEmpty) value,
        ].take(5).toList(growable: false),
      );
    } catch (_) {}
  }

  Future<void> _rememberSearch(String query) async {
    final searches = [
      query,
      ..._recentSearches.where((item) => item != query),
    ].take(5).toList(growable: false);
    setState(() {
      _recentSearches = searches;
      _showRecentSearches = false;
    });
    final repository = await ref.read(planRepositoryProvider.future);
    await repository.setSetting(
      'recent_scripture_searches',
      jsonEncode(searches),
    );
  }

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SearchBar(
                controller: _searchController,
                hintText: '搜索经文（精准匹配）',
                leading: const Icon(Icons.search_rounded),
                onTap: () => setState(() => _showRecentSearches = true),
                onSubmitted: (query) => _showSearchResults(query),
              ),
              if (_showRecentSearches && _recentSearches.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '最近搜索',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final query in _recentSearches)
                      ActionChip(
                        label: Text(query),
                        onPressed: () {
                          _searchController.text = query;
                          _showSearchResults(query);
                        },
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSearchResults(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    await _rememberSearch(trimmed);
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
        bookNames: ref.read(bookNameCatalogProvider),
        onOpen: (unit) async {
          await this.context.push(
            '/bible/$translation/${unit.start.osisBookId}/${unit.start.chapter}?verse=${unit.start.verse}&endVerse=${unit.end.verse}',
          );
        },
        onAdd: _addSearchVersesToPlan,
      ),
    );
  }

  Future<void> _addSearchVersesToPlan(List<VerseUnit> units) async {
    if (units.isEmpty) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(title: Text('加入背诵计划')),
            ListTile(
              leading: const Icon(Icons.add_circle_outline_rounded),
              title: const Text('新建计划'),
              onTap: () => Navigator.pop(context, 'new'),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text('加入已有计划'),
              onTap: () => Navigator.pop(context, 'existing'),
            ),
          ],
        ),
      ),
    );
    if (action == 'existing') return _appendSearchVersesToPlan(units);
    if (action != 'new') return;
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final catalog = ref.read(bookNameCatalogProvider);
    final first = units.first;
    final title = units.length == 1
        ? '${catalog.chapterLabel(first.start.osisBookId, first.start.chapter, Localizations.localeOf(context))} 背诵计划'
        : '搜索经文背诵计划';
    final repository = await ref.read(planRepositoryProvider.future);
    await repository.createPlan(
      NewMemorizationPlan(
        title: title,
        translationId: first.translationId,
        bookId: first.start.osisBookId,
        startChapter: first.start.chapter,
        endChapter: first.end.chapter,
        startDate: start,
        endDate: start.add(Duration(days: units.length - 1)),
        tasks: _searchTasks(units),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已新建背诵计划')));
    }
  }

  Future<void> _appendSearchVersesToPlan(List<VerseUnit> units) async {
    final repository = await ref.read(planRepositoryProvider.future);
    final plans = (await repository.listPlans())
        .where((plan) => !plan.contentLocked)
        .toList(growable: false);
    if (!mounted) return;
    final plan = await showModalBottomSheet<MemorizationPlan>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('选择要加入的背诵计划')),
            for (final item in plans)
              ListTile(
                title: Text(item.title),
                subtitle: Text('目前 ${item.totalTasks} 段经文'),
                onTap: () => Navigator.pop(context, item),
              ),
          ],
        ),
      ),
    );
    if (plan == null) return;
    await repository.appendDailyTasks(plan, _searchTasks(units));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已加入“${plan.title}”')));
    }
  }

  List<NewPlanTask> _searchTasks(List<VerseUnit> units) => [
    for (var index = 0; index < units.length; index++)
      NewPlanTask(
        dayIndex: index,
        bookId: units[index].start.osisBookId,
        startChapter: units[index].start.chapter,
        startVerse: units[index].start.verse,
        endChapter: units[index].end.chapter,
        endVerse: units[index].end.verse,
      ),
  ];
}

class _SearchResultsSheet extends StatefulWidget {
  const _SearchResultsSheet({
    required this.query,
    required this.translationId,
    required this.scripture,
    required this.onOpen,
    required this.bookNames,
    required this.onAdd,
  });
  final String query;
  final String translationId;
  final ScriptureRepository scripture;
  final Future<void> Function(VerseUnit) onOpen;
  final Future<void> Function(List<VerseUnit>) onAdd;
  final BookNameCatalog bookNames;
  @override
  State<_SearchResultsSheet> createState() => _SearchResultsSheetState();
}

class _SearchResultsSheetState extends State<_SearchResultsSheet> {
  final Set<int> _selected = <int>{};
  bool get _selecting => _selected.isNotEmpty;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_selecting,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) setState(_selected.clear);
    },
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .72,
      child: FutureBuilder<List<VerseUnit>>(
        future: widget.scripture.searchExactVerses(
          widget.translationId,
          widget.query,
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final units = snapshot.data!;
          return Column(
            children: [
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: ListTile(
                  title: Text(
                    _selecting
                        ? '已选择 ${_selected.length} 节'
                        : '“${widget.query}” · ${units.length} 条结果',
                  ),
                  subtitle: Text(
                    _selecting ? '点击结果可继续选择；返回取消多选' : '点击阅读定位；长按多选',
                  ),
                  trailing: _selecting
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '取消选择',
                              onPressed: () => setState(_selected.clear),
                              icon: const Icon(Icons.close_rounded),
                            ),
                            FilledButton.icon(
                              onPressed: () => widget.onAdd([
                                for (
                                  var index = 0;
                                  index < units.length;
                                  index++
                                )
                                  if (_selected.contains(index)) units[index],
                              ]),
                              icon: const Icon(Icons.playlist_add_rounded),
                              label: const Text('加入背诵计划'),
                            ),
                          ],
                        )
                      : null,
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: units.length,
                  itemBuilder: (context, index) {
                    final unit = units[index];
                    return ListTile(
                      selected: _selected.contains(index),
                      title: Text(
                        '${widget.bookNames.nameFor(unit.start.osisBookId, const Locale('zh', 'CN'))} ${unit.start.chapter}:${unit.start.verse}',
                      ),
                      subtitle: Text(
                        unit.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        if (!_selecting) {
                          widget.onOpen(unit);
                          return;
                        }
                        setState(() {
                          if (!_selected.add(index)) _selected.remove(index);
                        });
                      },
                      onLongPress: () => setState(() => _selected.add(index)),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
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
