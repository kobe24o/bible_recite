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
    DateTime selectedDate,
    Set<DateTime> writtenDates,
  ) async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => _NotesDatePickerDialog(
        month: month,
        selectedDate: selectedDate,
        today: _calendarDay(ref.read(devotionTodayProvider)),
        writtenDates: writtenDates,
      ),
    );
    if (picked == null || !mounted) return;
    final date = _calendarDay(picked);
    setState(() {
      _displayedMonth = DateTime(date.year, date.month);
      _selectedDate = date;
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
          final notesByDate = {
            for (final note in data.notes) _calendarDay(note.date): note,
          };
          final fallback = ref.watch(devotionTodayProvider);
          final month =
              _displayedMonth ?? DateTime(fallback.year, fallback.month);
          final selectedDate = _selectedDate ?? _calendarDay(fallback);
          final selected = notesByDate[selectedDate];
          final passages = selected != null && selected.note.passages.isNotEmpty
              ? selected.note.passages
              : data.manifest?.dayFor(selectedDate)?.passages ??
                    const <DevotionPassage>[];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _NotesMonthCalendar(
                month: month,
                today: _calendarDay(fallback),
                writtenDates: notesByDate.keys.toSet(),
                selectedDate: selectedDate,
                onPrevious: () =>
                    _changeMonth(DateTime(month.year, month.month - 1)),
                onNext: () =>
                    _changeMonth(DateTime(month.year, month.month + 1)),
                onChooseMonth: () =>
                    _chooseMonth(month, selectedDate, notesByDate.keys.toSet()),
                onSelect: (date) => setState(() => _selectedDate = date),
              ),
              const SizedBox(height: 20),
              Text(
                devotionDateLabel(selectedDate),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(selected?.content ?? '当天还没有灵修笔记'),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                key: const Key('open-selected-devotion'),
                onPressed: () async {
                  await context.push(
                    '/devotion/${devotionDateLabel(selectedDate)}',
                  );
                  if (mounted) setState(() => _notes = _loadNotes());
                },
                icon: const Icon(Icons.edit_note),
                label: const Text('阅读经文与写笔记'),
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

class _NotesDatePickerDialog extends StatefulWidget {
  const _NotesDatePickerDialog({
    required this.month,
    required this.selectedDate,
    required this.today,
    required this.writtenDates,
  });

  final DateTime month;
  final DateTime selectedDate;
  final DateTime today;
  final Set<DateTime> writtenDates;

  @override
  State<_NotesDatePickerDialog> createState() => _NotesDatePickerDialogState();
}

class _NotesDatePickerDialogState extends State<_NotesDatePickerDialog> {
  late DateTime _month = widget.month;
  late DateTime _selectedDate = widget.selectedDate;
  bool _choosingYear = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('选择年月日', style: Theme.of(context).textTheme.titleLarge),
                if (_choosingYear)
                  SizedBox(
                    height: 300,
                    child: YearPicker(
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100, 12, 31),
                      currentDate: widget.today,
                      selectedDate: _month,
                      onChanged: (date) => setState(() {
                        _month = DateTime(date.year, _month.month);
                        _choosingYear = false;
                      }),
                    ),
                  )
                else
                  _NotesMonthCalendar(
                    month: _month,
                    today: widget.today,
                    writtenDates: widget.writtenDates,
                    selectedDate: _selectedDate,
                    onPrevious: _month.year == 2000 && _month.month == 1
                        ? null
                        : () => setState(() {
                            _month = DateTime(_month.year, _month.month - 1);
                          }),
                    onNext: _month.year == 2100 && _month.month == 12
                        ? null
                        : () => setState(() {
                            _month = DateTime(_month.year, _month.month + 1);
                          }),
                    onChooseMonth: () => setState(() => _choosingYear = true),
                    onSelect: (date) => setState(() => _selectedDate = date),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, _selectedDate),
                      child: const Text('确定'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotesMonthCalendar extends StatefulWidget {
  const _NotesMonthCalendar({
    required this.month,
    required this.today,
    required this.writtenDates,
    required this.selectedDate,
    required this.onPrevious,
    required this.onNext,
    required this.onChooseMonth,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime today;
  final Set<DateTime> writtenDates;
  final DateTime selectedDate;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onChooseMonth;
  final ValueChanged<DateTime> onSelect;

  @override
  State<_NotesMonthCalendar> createState() => _NotesMonthCalendarState();
}

class _NotesMonthCalendarState extends State<_NotesMonthCalendar> {
  double _swipeDistance = 0;

  DateTime get month => widget.month;
  Set<DateTime> get writtenDates => widget.writtenDates;
  DateTime get selectedDate => widget.selectedDate;
  VoidCallback? get onPrevious => widget.onPrevious;
  VoidCallback? get onNext => widget.onNext;
  VoidCallback get onChooseMonth => widget.onChooseMonth;
  ValueChanged<DateTime> get onSelect => widget.onSelect;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final dayCount = DateTime(month.year, month.month + 1, 0).day;
    final leadingEmptyCells = first.weekday % DateTime.daysPerWeek;
    return GestureDetector(
      key: const Key('devotion-calendar-swipe'),
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => _swipeDistance = 0,
      onHorizontalDragUpdate: (details) => _swipeDistance += details.delta.dx,
      onHorizontalDragEnd: (_) {
        if (_swipeDistance <= -48) onNext?.call();
        if (_swipeDistance >= 48) onPrevious?.call();
      },
      child: Card(
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
                  mainAxisExtent: 48,
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
                        key: Key(
                          'devotion-note-day-${devotionDateLabel(date)}',
                        ),
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => onSelect(date),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              key: date == widget.today
                                  ? Key(
                                      'devotion-note-today-${devotionDateLabel(date)}',
                                    )
                                  : null,
                              width: 30,
                              height: 30,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: date == widget.today
                                    ? Border.all(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      )
                                    : null,
                              ),
                              child: Text('${date.day}'),
                            ),
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
                                        color: Colors.green,
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
      ),
    );
  }
}
