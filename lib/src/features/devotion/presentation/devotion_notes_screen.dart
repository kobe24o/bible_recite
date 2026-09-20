import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../plans/application/plan_providers.dart';
import '../../plans/data/sqlite_plan_repository.dart';
import '../../scripture/application/scripture_providers.dart';
import '../application/devotion_providers.dart';
import '../domain/devotion_models.dart';
import 'devotion_schedule_screen.dart';

class DevotionNotesScreen extends ConsumerStatefulWidget {
  const DevotionNotesScreen({super.key});

  @override
  ConsumerState<DevotionNotesScreen> createState() =>
      _DevotionNotesScreenState();
}

class _DevotionNotesScreenState extends ConsumerState<DevotionNotesScreen> {
  late Future<_DevotionNotesData> _notes;
  DateTime? _displayedMonth;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _notes = _loadNotes();
  }

  Future<_DevotionNotesData> _loadNotes() async {
    final repository = await ref.read(planRepositoryProvider.future);
    final values = await Future.wait<Object?>([
      repository.listDevotionNotes(),
      ref.read(cachedDevotionManifestProvider.future),
    ]);
    return _DevotionNotesData(
      notes: values[0]! as List<DevotionNoteEntry>,
      manifest: values[1] as DevotionManifest?,
    );
  }

  DateTime _calendarDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  void _changeMonth(DateTime month) {
    setState(() => _displayedMonth = DateTime(month.year, month.month));
  }

  Future<void> _chooseMonth(
    DateTime month,
    Map<DateTime, DevotionNoteEntry> notes,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: month,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: '选择年月日',
    );
    if (picked == null || !mounted) return;
    final date = _calendarDay(picked);
    setState(() {
      _displayedMonth = DateTime(date.year, date.month);
      if (notes.containsKey(date)) _selectedDate = date;
    });
  }

  Future<void> _openReference(DevotionPassage passage) async {
    try {
      final scripture = await ref.read(scriptureRepositoryProvider.future);
      final translations = await scripture.listTranslations();
      if (!mounted) return;
      if (translations.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先安装圣经译本')));
        return;
      }
      final query = <String, String>{
        'verse': '${passage.startVerse}',
        'endVerse': '${passage.endVerse}',
        if (passage.endChapter != passage.startChapter)
          'endChapter': '${passage.endChapter}',
      };
      context.push(
        Uri(
          path:
              '/bible/${translations.first.id}/${passage.bookId}/${passage.startChapter}',
          queryParameters: query,
        ).toString(),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开经文，请重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = ref.watch(bookNameCatalogProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('灵修笔记')),
      body: FutureBuilder<_DevotionNotesData>(
        future: _notes,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          if (data.notes.isEmpty) {
            return const Center(child: Text('还没有写过灵修笔记'));
          }
          final notesByDate = {
            for (final note in data.notes) _calendarDay(note.date): note,
          };
          final fallback = data.notes.last.date;
          final month =
              _displayedMonth ?? DateTime(fallback.year, fallback.month);
          final selectedDate = _selectedDate ?? _calendarDay(fallback);
          final selected = notesByDate[selectedDate] ?? data.notes.last;
          final passages = selected.note.passages.isNotEmpty
              ? selected.note.passages
              : data.manifest?.dayFor(selected.date)?.passages ??
                    const <DevotionPassage>[];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _NotesMonthCalendar(
                month: month,
                writtenDates: notesByDate.keys.toSet(),
                selectedDate: selectedDate,
                onPrevious: () =>
                    _changeMonth(DateTime(month.year, month.month - 1)),
                onNext: () =>
                    _changeMonth(DateTime(month.year, month.month + 1)),
                onChooseMonth: () => _chooseMonth(month, notesByDate),
                onSelect: (date) => setState(() => _selectedDate = date),
              ),
              const SizedBox(height: 20),
              Text(
                devotionDateLabel(selected.date),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(selected.content),
                ),
              ),
              const SizedBox(height: 12),
              Text('参考经文', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (passages.isEmpty)
                const Text('该日期的灵修日程尚未同步')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final passage in passages)
                      ActionChip(
                        avatar: const Icon(Icons.menu_book_outlined, size: 18),
                        label: Text(
                          devotionPassageLabel(
                            passage,
                            names.nameFor(
                              passage.bookId,
                              Localizations.localeOf(context),
                            ),
                          ),
                        ),
                        onPressed: () => _openReference(passage),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DevotionNotesData {
  const _DevotionNotesData({required this.notes, required this.manifest});

  final List<DevotionNoteEntry> notes;
  final DevotionManifest? manifest;
}

class _NotesMonthCalendar extends StatelessWidget {
  const _NotesMonthCalendar({
    required this.month,
    required this.writtenDates,
    required this.selectedDate,
    required this.onPrevious,
    required this.onNext,
    required this.onChooseMonth,
    required this.onSelect,
  });

  final DateTime month;
  final Set<DateTime> writtenDates;
  final DateTime selectedDate;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onChooseMonth;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final dayCount = DateTime(month.year, month.month + 1, 0).day;
    final leadingEmptyCells = first.weekday % DateTime.daysPerWeek;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  key: const Key('previous-devotion-note-month'),
                  tooltip: '上个月',
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: TextButton(
                    key: const Key('choose-devotion-note-month'),
                    onPressed: onChooseMonth,
                    child: Text('${month.year}年${month.month}月'),
                  ),
                ),
                IconButton(
                  key: const Key('next-devotion-note-month'),
                  tooltip: '下个月',
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            Row(
              children: [
                for (final weekday in ['日', '一', '二', '三', '四', '五', '六'])
                  Expanded(child: Center(child: Text(weekday))),
              ],
            ),
            const SizedBox(height: 6),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: leadingEmptyCells + dayCount,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 0.9,
              ),
              itemBuilder: (context, index) {
                if (index < leadingEmptyCells) return const SizedBox.shrink();
                final date = DateTime(
                  month.year,
                  month.month,
                  index - leadingEmptyCells + 1,
                );
                final written = writtenDates.contains(date);
                final selected = selectedDate == date;
                return Padding(
                  padding: const EdgeInsets.all(2),
                  child: Material(
                    color: selected
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      key: Key('devotion-note-day-${devotionDateLabel(date)}'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: written ? () => onSelect(date) : null,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('${date.day}'),
                          SizedBox(
                            height: 7,
                            child: written
                                ? Container(
                                    key: Key(
                                      'devotion-note-dot-${devotionDateLabel(date)}',
                                    ),
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
