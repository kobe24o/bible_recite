import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../plans/application/plan_providers.dart';
import '../../plans/domain/plan_draft_builder.dart';
import '../../plans/domain/plan_models.dart';
import '../../plans/presentation/plan_editor_dialog.dart';
import '../../quiz/application/quiz_preparation_controller.dart';
import '../../quiz/application/quiz_providers.dart';
import '../../quiz/domain/quiz_scope.dart';
import '../../quiz/presentation/quiz_practice_request.dart';
import '../../recitation/presentation/recitation_practice_screen.dart';
import '../application/scripture_providers.dart';
import '../domain/scripture_models.dart';
import '../domain/scripture_repository.dart';
import 'scripture_search_highlight.dart';

class PassageScreen extends ConsumerStatefulWidget {
  const PassageScreen({
    required this.translationId,
    required this.bookId,
    required this.chapter,
    this.initialVerse,
    this.initialEndVerse,
    this.searchQuery,
    this.reviewId,
    super.key,
  });

  final String translationId;
  final String bookId;
  final int chapter;
  final int? initialVerse;
  final int? initialEndVerse;
  final String? searchQuery;
  final int? reviewId;

  @override
  ConsumerState<PassageScreen> createState() => _PassageScreenState();
}

class _PassageScreenState extends ConsumerState<PassageScreen> {
  String? _parallelTranslationId;
  final Set<int> _selectedVerseIndexes = <int>{};
  bool _selectingVerses = false;
  QuizPreparationController? _quizPreparation;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(PassageScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chapter != widget.chapter ||
        oldWidget.bookId != widget.bookId ||
        oldWidget.translationId != widget.translationId ||
        oldWidget.initialVerse != widget.initialVerse ||
        oldWidget.initialEndVerse != widget.initialEndVerse) {
      _parallelTranslationId = null;
      _selectingVerses = false;
      _selectedVerseIndexes.clear();
      _resetQuiz();
    }
  }

  @override
  void dispose() {
    _disposeQuizPreparation();
    super.dispose();
  }

  void _resetQuiz() {
    _disposeQuizPreparation();
    setState(() {
      _quizPreparation = null;
    });
  }

  void _armQuiz(List<VerseUnit> units) {
    if (_quizPreparation != null) return;
    final scope = widget.initialVerse != null
        ? QuizScope(
            translationId: widget.translationId,
            bookId: widget.bookId,
            startChapter: widget.chapter,
            startVerse: widget.initialVerse!,
            endChapter: widget.chapter,
            endVerse: (widget.initialEndVerse ?? widget.initialVerse)!,
          )
        : QuizScope(
            translationId: widget.translationId,
            bookId: widget.bookId,
            startChapter: widget.chapter,
            startVerse: 1,
            endChapter: widget.chapter,
            endVerse: units.isNotEmpty ? units.last.end.verse : 1,
          );
    final preparation = QuizPreparationController(
      scope: scope,
      serviceLoader: () => ref.read(quizGenerationServiceProvider.future),
    );
    preparation.addListener(_onQuizPreparationChanged);
    _quizPreparation = preparation;
    preparation.arm();
  }

  void _onQuizPreparationChanged() {
    if (mounted) setState(() {});
  }

  void _disposeQuizPreparation() {
    final preparation = _quizPreparation;
    if (preparation == null) return;
    preparation.removeListener(_onQuizPreparationChanged);
    preparation.dispose();
  }

  void _openQuiz() {
    final preparation = _quizPreparation;
    if (preparation == null ||
        preparation.phase != QuizPreparationPhase.ready ||
        preparation.questions.isEmpty) {
      return;
    }
    context.push(
      '/quiz',
      extra: QuizPracticeRequest(
        scope: preparation.scope,
        questions: preparation.questions,
      ),
    );
  }

  Future<_PassageData> _load(ScriptureRepository repository) async {
    final values = await Future.wait<Object>([
      repository.listTranslations(),
      repository.listBooks(widget.translationId, CanonId.protestant66),
    ]);
    final translations = values[0] as List<TranslationInfo>;
    final books = values[1] as List<BibleBook>;
    final units = await repository.getChapter(
      widget.translationId,
      widget.bookId,
      widget.chapter,
    );
    ParallelPassage? parallel;
    if (_parallelTranslationId != null && units.isNotEmpty) {
      parallel = await repository.resolveParallelPassage(
        LocatedPassageRange(
          translationId: widget.translationId,
          range: PassageRange(start: units.first.start, end: units.last.end),
        ),
        _parallelTranslationId!,
      );
    }
    return _PassageData(
      translations: translations,
      units: units,
      parallel: parallel,
      chapterCount: books
          .firstWhere((book) => book.osisId == widget.bookId)
          .chapterCount,
    );
  }

  void _onChapterSwipe(double? velocity, int chapterCount) {
    if (_selectingVerses || velocity == null || velocity.abs() < 300) return;
    final chapter = velocity < 0 ? widget.chapter + 1 : widget.chapter - 1;
    if (chapter < 1 || chapter > chapterCount) return;
    context.go('/bible/${widget.translationId}/${widget.bookId}/$chapter');
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(scriptureRepositoryProvider);
    final bookNames = ref.watch(bookNameCatalogProvider);
    final title = bookNames.chapterLabel(
      widget.bookId,
      widget.chapter,
      Localizations.localeOf(context),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectingVerses ? '已选择 ${_selectedVerseIndexes.length} 节' : title,
        ),
        actions: [
          if (_selectingVerses)
            IconButton(
              tooltip: '取消选择',
              onPressed: () => setState(() {
                _selectingVerses = false;
                _selectedVerseIndexes.clear();
              }),
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      body: repository.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text(
            AppLocalizations.of(context)?.unableLoadPassage ??
                'Unable to load the passage',
          ),
        ),
        data: (repository) => FutureBuilder<_PassageData>(
          future: _load(repository),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _armQuiz(data.units);
            });
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          key: const Key('parallel-translation-selector'),
                          initialValue: _parallelTranslationId,
                          decoration: const InputDecoration(
                            labelText: 'Parallel translation',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('Single translation'),
                            ),
                            for (final translation in data.translations)
                              if (translation.id != widget.translationId)
                                DropdownMenuItem(
                                  value: translation.id,
                                  child: Text(translation.name),
                                ),
                          ],
                          onChanged: (value) =>
                              setState(() => _parallelTranslationId = value),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Scripture sources',
                        onPressed: () => GoRouter.maybeOf(
                          context,
                        )?.push('/about/scripture-sources'),
                        icon: const Icon(Icons.info_outline),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('start-recitation-button'),
                          onPressed: data.units.isEmpty
                              ? null
                              : () =>
                                    _chooseRecitationMode(context, data.units),
                          icon: const Icon(Icons.mic_rounded),
                          label: Text(
                            AppLocalizations.of(context)!.startRecitation,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('add-to-plan-button'),
                          onPressed:
                              data.units.isEmpty ||
                                  (_selectingVerses &&
                                      _selectedVerseIndexes.isEmpty)
                              ? null
                              : () => _showAddToPlan(context, data.units),
                          icon: const Icon(Icons.playlist_add_rounded),
                          label: Text(
                            _selectingVerses
                                ? '加入背诵计划（${_selectedVerseIndexes.length}）'
                                : AppLocalizations.of(context)!.addToPlan,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.icon(
                        key: const Key('start-quiz-button'),
                        onPressed:
                            _quizPreparation?.phase ==
                                    QuizPreparationPhase.ready &&
                                _quizPreparation!.questions.isNotEmpty
                            ? _openQuiz
                            : null,
                        icon: const Icon(Icons.quiz_outlined),
                        label: Text(
                          _quizPreparation?.phase ==
                                  QuizPreparationPhase.preparing
                              ? '正在生成答题题目…'
                              : _quizPreparation?.phase ==
                                        QuizPreparationPhase.ready &&
                                    _quizPreparation!.questions.isNotEmpty
                              ? '开始答题'
                              : '开始答题（题目准备中）',
                        ),
                      ),
                      if (_quizPreparation?.phase ==
                              QuizPreparationPhase.failed &&
                          _quizPreparation?.error != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _quizPreparation!.error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        TextButton(
                          key: const Key('retry-quiz-generation-button'),
                          onPressed:
                              _quizPreparation == null ||
                                  _quizPreparation?.phase ==
                                      QuizPreparationPhase.preparing
                              ? null
                              : () {
                                  _quizPreparation!.prepare();
                                },
                          child: const Text('重试生成'),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    key: const Key('passage-reader'),
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragEnd: (details) => _onChapterSwipe(
                      details.primaryVelocity,
                      data.chapterCount,
                    ),
                    child: data.parallel == null
                        ? _SinglePassage(
                            units: data.units,
                            initialVerse: widget.initialVerse,
                            initialEndVerse: widget.initialEndVerse,
                            searchQuery: widget.searchQuery ?? '',
                            selecting: _selectingVerses,
                            selectedIndexes: _selectedVerseIndexes,
                            onLongPress: (index) => setState(() {
                              _selectingVerses = true;
                              _selectedVerseIndexes.add(index);
                            }),
                            onTap: (index) {
                              if (!_selectingVerses) return;
                              setState(() {
                                if (!_selectedVerseIndexes.add(index)) {
                                  _selectedVerseIndexes.remove(index);
                                }
                              });
                            },
                          )
                        : _ParallelPassageView(passage: data.parallel!),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _showAddToPlan(
    BuildContext context,
    List<VerseUnit> units,
  ) async {
    final selected = _selectingVerses
        ? [
            for (var index = 0; index < units.length; index++)
              if (_selectedVerseIndexes.contains(index)) units[index],
          ]
        : units;
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(chinese ? '加入背诵计划' : 'Add to memorization plan'),
        content: Text(
          chinese
              ? '可新建计划，或前往计划页选择并编辑已有计划。'
              : 'Create a plan or edit an existing plan on the Plans page.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(chinese ? '取消' : 'Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              if (_selectingVerses) {
                _chooseExistingPlan(selected);
              } else {
                context.go('/plans');
              }
            },
            child: Text(chinese ? '选择已有计划' : 'Existing plans'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              if (_selectingVerses) {
                await _createPlanFromSelection(selected);
              } else {
                await _openNewPlanEditor();
              }
            },
            child: Text(chinese ? '新建计划' : 'New plan'),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseExistingPlan(List<VerseUnit> selected) async {
    final repository = await ref.read(planRepositoryProvider.future);
    final plans = (await repository.listPlans())
        .where((plan) => !plan.contentLocked)
        .toList(growable: false);
    if (!mounted) return;
    if (plans.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可编辑的本地计划，请先新建计划')));
      return;
    }
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
                leading: const Icon(Icons.playlist_add_rounded),
                title: Text(item.title),
                subtitle: Text('目前 ${item.days} 天 · ${item.totalTasks} 段'),
                onTap: () => Navigator.pop(context, item),
              ),
          ],
        ),
      ),
    );
    if (plan == null || !mounted) return;
    try {
      await repository.appendDailyTasks(plan, _tasksFor(selected));
      if (!mounted) return;
      setState(() {
        _selectingVerses = false;
        _selectedVerseIndexes.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已加入“${plan.title}”，按新增日期安排背诵')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加入计划失败：$error')));
      }
    }
  }

  Future<void> _createPlanFromSelection(List<VerseUnit> selected) async {
    final saved = await _openNewPlanEditor(
      initialPassages: [
        for (final unit in selected)
          PlanPassageSelection(
            bookId: unit.start.osisBookId,
            startChapter: unit.start.chapter,
            startVerse: unit.start.verse,
            endChapter: unit.end.chapter,
            endVerse: unit.end.verse,
          ),
      ],
    );
    if (saved && mounted) {
      setState(() {
        _selectingVerses = false;
        _selectedVerseIndexes.clear();
      });
    }
  }

  List<NewPlanTask> _tasksFor(List<VerseUnit> units) => [
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

  Future<bool> _openNewPlanEditor({
    List<PlanPassageSelection> initialPassages = const [],
  }) async {
    final locale = Localizations.localeOf(context);
    try {
      final scripture = await ref.read(scriptureRepositoryProvider.future);
      final rawBooks = await scripture.listBooks(
        widget.translationId,
        CanonId.protestant66,
      );
      final catalog = ref.read(bookNameCatalogProvider);
      final books = rawBooks
          .map(
            (book) => BibleBook(
              osisId: book.osisId,
              ordinal: book.ordinal,
              name: catalog.nameFor(book.osisId, locale),
              chapterCount: book.chapterCount,
            ),
          )
          .toList(growable: false);
      if (!mounted) return false;
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day);
      final chapterTitle = catalog.chapterLabel(
        widget.bookId,
        widget.chapter,
        locale,
      );
      final result = await showDialog<PlanEditorResult>(
        context: context,
        builder: (_) => PlanEditorDialog(
          books: books,
          initial: PlanEditorDraft(
            title: '$chapterTitle 背诵计划',
            translationId: widget.translationId,
            bookId: widget.bookId,
            startChapter: widget.chapter,
            endChapter: widget.chapter,
            startDate: start,
            endDate: start.add(
              Duration(
                days: initialPassages.isEmpty ? 6 : initialPassages.length - 1,
              ),
            ),
            passages: initialPassages,
          ),
        ),
      );
      if (result?.draft == null || !mounted) return false;
      final plan = await buildPlanFromDraft(scripture, result!.draft!);
      final repository = await ref.read(planRepositoryProvider.future);
      await repository.createPlan(plan);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('计划已保存到本机')));
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('创建计划失败：$error')));
      }
      return false;
    }
  }

  Future<void> _chooseRecitationMode(
    BuildContext context,
    List<VerseUnit> units,
  ) async {
    final localizations = AppLocalizations.of(context)!;
    final mode = await showModalBottomSheet<RecitationMode>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                localizations.chooseRecitationMode,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.pop(context, RecitationMode.verse),
                icon: const Icon(Icons.format_list_numbered_rounded),
                label: Text(localizations.verseMode),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () =>
                    Navigator.pop(context, RecitationMode.continuous),
                icon: const Icon(Icons.multitrack_audio_rounded),
                label: Text(localizations.continuousMode),
              ),
            ],
          ),
        ),
      ),
    );
    if (mode == null || !context.mounted) return;
    await context.push(
      '/recitation',
      extra: RecitationRequest(
        translationId: widget.translationId,
        bookId: widget.bookId,
        chapter: widget.chapter,
        mode: mode,
        units: List.unmodifiable(units),
        reviewId: widget.reviewId,
      ),
    );
  }
}

class _SinglePassage extends StatefulWidget {
  const _SinglePassage({
    required this.units,
    this.initialVerse,
    this.initialEndVerse,
    required this.searchQuery,
    required this.selecting,
    required this.selectedIndexes,
    required this.onLongPress,
    required this.onTap,
  });
  final List<VerseUnit> units;
  final int? initialVerse;
  final int? initialEndVerse;
  final String searchQuery;
  final bool selecting;
  final Set<int> selectedIndexes;
  final ValueChanged<int> onLongPress;
  final ValueChanged<int> onTap;

  @override
  State<_SinglePassage> createState() => _SinglePassageState();
}

class _SinglePassageState extends State<_SinglePassage> {
  late final ScrollController _controller;
  late final GlobalKey _targetVerseKey;
  late final int _targetVerseIndex;

  @override
  void initState() {
    super.initState();
    _targetVerseIndex = widget.initialVerse == null
        ? 0
        : widget.units.indexWhere(
            (unit) =>
                unit.start.verse <= widget.initialVerse! &&
                unit.end.verse >= widget.initialVerse!,
          );
    _targetVerseKey = GlobalKey();
    _controller = ScrollController();
    if (_targetVerseIndex >= 0 && widget.initialVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final targetContext = _targetVerseKey.currentContext;
        if (targetContext == null) return;
        Scrollable.ensureVisible(
          targetContext,
          alignment: .5,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: _controller,
      padding: const EdgeInsets.all(20),
      itemCount: widget.units.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final unit = widget.units[index];
        final isTarget =
            widget.initialVerse != null &&
            unit.start.verse <=
                (widget.initialEndVerse ?? widget.initialVerse!) &&
            unit.end.verse >= widget.initialVerse!;
        return _VerseRow(
          key: index == _targetVerseIndex ? _targetVerseKey : null,
          unit: unit,
          selected:
              widget.selectedIndexes.contains(index) ||
              (widget.searchQuery.trim().isEmpty && isTarget),
          searchQuery: widget.searchQuery,
          selectable: widget.selecting,
          onLongPress: () => widget.onLongPress(index),
          onTap: () => widget.onTap(index),
        );
      },
    );
  }
}

class _VerseRow extends StatelessWidget {
  const _VerseRow({
    required this.unit,
    this.searchQuery = '',
    this.selected = false,
    this.selectable = false,
    this.onLongPress,
    this.onTap,
    super.key,
  });
  final VerseUnit unit;
  final String searchQuery;
  final bool selected;
  final bool selectable;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = unit.start.verse == unit.end.verse
        ? '${unit.start.verse}'
        : '${unit.start.verse}–${unit.end.verse}';
    return Semantics(
      label:
          '${unit.translationId} ${unit.start.osisBookId} '
          '${unit.start.chapter}:$label',
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onLongPress: onLongPress,
          onTap: selectable ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                Expanded(child: _buildVerseText(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerseText(BuildContext context) {
    final text = unit.status == SourceTextStatus.omitted
        ? AppLocalizations.of(context)?.omittedVerse ??
              'This verse is omitted in this translation.'
        : unit.text;
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
      fontWeight: selected ? FontWeight.bold : null,
    );
    return Text.rich(
      TextSpan(
        style: style,
        children: scriptureSearchHighlightSpans(
          text: text,
          query: searchQuery,
          matchStyle: style?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      textAlign: searchQuery.trim().isEmpty ? null : TextAlign.center,
    );
  }
}

class _ParallelPassageView extends StatelessWidget {
  const _ParallelPassageView({required this.passage});
  final ParallelPassage passage;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: passage.groups.length,
      separatorBuilder: (context, index) => const Divider(height: 24),
      itemBuilder: (context, index) {
        final group = passage.groups[index];
        return Semantics(
          label: '${group.relation.name}; ${group.provenance}',
          child: LayoutBuilder(
            builder: (context, constraints) {
              final source = _UnitColumn(units: group.sourceUnits);
              final target = _UnitColumn(units: group.targetUnits);
              if (constraints.maxWidth < 720) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [source, const SizedBox(height: 12), target],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: source),
                  const VerticalDivider(),
                  Expanded(child: target),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _UnitColumn extends StatelessWidget {
  const _UnitColumn({required this.units});
  final List<VerseUnit> units;

  @override
  Widget build(BuildContext context) {
    if (units.isEmpty) {
      return const Text('No counterpart in this translation');
    }
    return Column(children: [for (final unit in units) _VerseRow(unit: unit)]);
  }
}

final class _PassageData {
  const _PassageData({
    required this.translations,
    required this.units,
    required this.parallel,
    required this.chapterCount,
  });

  final List<TranslationInfo> translations;
  final List<VerseUnit> units;
  final ParallelPassage? parallel;
  final int chapterCount;
}
