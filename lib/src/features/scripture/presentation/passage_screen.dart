import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../plans/application/plan_providers.dart';
import '../../plans/domain/plan_draft_builder.dart';
import '../../plans/domain/plan_models.dart';
import '../../plans/presentation/plan_editor_dialog.dart';
import '../../recitation/presentation/recitation_practice_screen.dart';
import '../application/scripture_providers.dart';
import '../domain/scripture_models.dart';
import '../domain/scripture_repository.dart';

class PassageScreen extends ConsumerStatefulWidget {
  const PassageScreen({
    required this.translationId,
    required this.bookId,
    required this.chapter,
    this.reviewId,
    super.key,
  });

  final String translationId;
  final String bookId;
  final int chapter;
  final int? reviewId;

  @override
  ConsumerState<PassageScreen> createState() => _PassageScreenState();
}

class _PassageScreenState extends ConsumerState<PassageScreen> {
  String? _parallelTranslationId;
  final Set<int> _selectedVerseIndexes = <int>{};
  bool _selectingVerses = false;

  Future<_PassageData> _load(ScriptureRepository repository) async {
    final translations = await repository.listTranslations();
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
    );
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
                Expanded(
                  child: data.parallel == null
                      ? _SinglePassage(
                          units: data.units,
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
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final catalog = ref.read(bookNameCatalogProvider);
    final title =
        '${catalog.chapterLabel(widget.bookId, widget.chapter, Localizations.localeOf(context))} 背诵计划';
    try {
      final repository = await ref.read(planRepositoryProvider.future);
      await repository.createPlan(
        NewMemorizationPlan(
          title: title,
          translationId: widget.translationId,
          bookId: widget.bookId,
          startChapter: widget.chapter,
          endChapter: widget.chapter,
          startDate: start,
          endDate: start.add(Duration(days: selected.length - 1)),
          tasks: _tasksFor(selected),
        ),
      );
      if (!mounted) return;
      setState(() {
        _selectingVerses = false;
        _selectedVerseIndexes.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('计划已创建：每天安排一节，可在计划中查看')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('创建计划失败：$error')));
      }
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

  Future<void> _openNewPlanEditor() async {
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
      if (!mounted) return;
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
            endDate: start.add(const Duration(days: 6)),
          ),
        ),
      );
      if (result?.draft == null || !mounted) return;
      final plan = await buildPlanFromDraft(scripture, result!.draft!);
      final repository = await ref.read(planRepositoryProvider.future);
      await repository.createPlan(plan);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('计划已保存到本机')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('创建计划失败：$error')));
      }
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

class _SinglePassage extends StatelessWidget {
  const _SinglePassage({
    required this.units,
    required this.selecting,
    required this.selectedIndexes,
    required this.onLongPress,
    required this.onTap,
  });
  final List<VerseUnit> units;
  final bool selecting;
  final Set<int> selectedIndexes;
  final ValueChanged<int> onLongPress;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: units.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _VerseRow(
        unit: units[index],
        selected: selectedIndexes.contains(index),
        selectable: selecting,
        onLongPress: () => onLongPress(index),
        onTap: () => onTap(index),
      ),
    );
  }
}

class _VerseRow extends StatelessWidget {
  const _VerseRow({
    required this.unit,
    this.selected = false,
    this.selectable = false,
    this.onLongPress,
    this.onTap,
  });
  final VerseUnit unit;
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
                Expanded(
                  child: Text(
                    unit.status == SourceTextStatus.omitted
                        ? AppLocalizations.of(context)?.omittedVerse ??
                              'This verse is omitted in this translation.'
                        : unit.text,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
  });

  final List<TranslationInfo> translations;
  final List<VerseUnit> units;
  final ParallelPassage? parallel;
}
