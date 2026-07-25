import 'package:flutter/material.dart';

import '../../scripture/domain/scripture_models.dart';

final class PlanEditorDraft {
  const PlanEditorDraft({
    required this.title,
    required this.translationId,
    required this.bookId,
    required this.startChapter,
    required this.endChapter,
    required this.startDate,
    required this.endDate,
    this.passages = const [],
  });

  final String title;
  final String translationId;
  final String bookId;
  final int startChapter;
  final int endChapter;
  final DateTime startDate;
  final DateTime endDate;
  final List<PlanPassageSelection> passages;

  int get days => endDate.difference(startDate).inDays + 1;
}

final class PlanPassageSelection {
  const PlanPassageSelection({
    required this.bookId,
    required this.startChapter,
    required this.startVerse,
    required this.endChapter,
    required this.endVerse,
  });

  final String bookId;
  final int startChapter;
  final int startVerse;
  final int endChapter;
  final int endVerse;
}

final class PlanEditorResult {
  const PlanEditorResult.saved(this.draft) : delete = false;
  const PlanEditorResult.deleted() : draft = null, delete = true;

  final PlanEditorDraft? draft;
  final bool delete;
}

class PlanEditorDialog extends StatefulWidget {
  const PlanEditorDialog({
    required this.books,
    required this.initial,
    this.allowDelete = false,
    this.contentLocked = false,
    this.minimumDays = 1,
    this.onAddPassage,
    super.key,
  });

  final List<BibleBook> books;
  final PlanEditorDraft initial;
  final bool allowDelete;
  final bool contentLocked;
  final int minimumDays;
  final Future<PlanPassageSelection?> Function()? onAddPassage;

  @override
  State<PlanEditorDialog> createState() => _PlanEditorDialogState();
}

class _PlanEditorDialogState extends State<PlanEditorDialog> {
  late final TextEditingController _title;
  late List<PlanPassageSelection> _passages;
  late String _translationId;
  late DateTime _startDate;
  late DateTime _endDate;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initial.title);
    _passages = List.of(widget.initial.passages);
    _translationId = widget.initial.translationId;
    _startDate = widget.initial.startDate;
    _endDate = widget.initial.endDate;
  }

  @override
  Widget build(BuildContext context) {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    return AlertDialog(
      title: Text(chinese ? '编辑背诵计划' : 'Edit memorization plan'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('plan-title'),
              controller: _title,
              readOnly: widget.contentLocked,
              decoration: InputDecoration(
                labelText: chinese ? '计划名称' : 'Plan name',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('plan-translation'),
              initialValue: _translationId,
              decoration: InputDecoration(
                labelText: chinese ? '背诵版本' : 'Translation',
                border: const OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'cmn-cu89s', child: Text('简体中文')),
                DropdownMenuItem(value: 'cmn-cu89t', child: Text('繁體中文')),
                DropdownMenuItem(value: 'eng-web', child: Text('English')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _translationId = value);
              },
            ),
            const SizedBox(height: 12),
            if (widget.contentLocked)
              Container(
                key: const Key('locked-plan-content-note'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  chinese
                      ? '经卷、章节和节数由发布方提供，不能在本机修改。'
                      : 'Books and passage ranges are locked by the publisher.',
                ),
              )
            else ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(chinese ? '背诵经文' : 'Passages'),
              ),
              const SizedBox(height: 6),
              for (final passage in _passages)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${_bookName(passage.bookId)} ${passage.startChapter}:${passage.startVerse}–${passage.endChapter}:${passage.endVerse}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => _passages.remove(passage)),
                  ),
                ),
              OutlinedButton.icon(
                key: const Key('add-plan-passage'),
                onPressed: widget.onAddPassage == null ? null : _addPassage,
                icon: const Icon(Icons.add_rounded),
                label: Text(chinese ? '添加经文' : 'Add passage'),
              ),
            ],
            const SizedBox(height: 8),
            ListTile(
              key: const Key('plan-start-date'),
              contentPadding: EdgeInsets.zero,
              title: Text(chinese ? '开始日期' : 'Start date'),
              subtitle: Text(_format(_startDate)),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: () => _pickDate(start: true),
            ),
            ListTile(
              key: const Key('plan-end-date'),
              contentPadding: EdgeInsets.zero,
              title: Text(chinese ? '结束日期' : 'End date'),
              subtitle: Text(_format(_endDate)),
              trailing: const Icon(Icons.event_available_outlined),
              onTap: () => _pickDate(start: false),
            ),
            Text(
              chinese
                  ? '共 ${_days.clamp(0, 365)} 天'
                  : '${_days.clamp(0, 365)} days',
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (widget.allowDelete)
          TextButton.icon(
            key: const Key('delete-plan-button'),
            onPressed: () =>
                Navigator.pop(context, const PlanEditorResult.deleted()),
            icon: const Icon(Icons.delete_outline),
            label: Text(chinese ? '删除' : 'Delete'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(chinese ? '取消' : 'Cancel'),
        ),
        FilledButton(
          key: const Key('save-plan-button'),
          onPressed: _save,
          child: Text(chinese ? '保存' : 'Save'),
        ),
      ],
    );
  }

  int get _days => _endDate.difference(_startDate).inDays + 1;

  Future<void> _pickDate({required bool start}) async {
    final initial = start ? _startDate : _endDate;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected == null) return;
    setState(() {
      if (start) {
        _startDate = selected;
        if (_endDate.isBefore(selected)) _endDate = selected;
      } else {
        _endDate = selected;
      }
    });
  }

  void _save() {
    if (_title.text.trim().isEmpty ||
        (!widget.contentLocked && _passages.isEmpty) ||
        _days < 1 ||
        _days < widget.minimumDays ||
        _days > 365) {
      setState(() => _error = '请检查名称和日期（${widget.minimumDays}–365 天）');
      return;
    }
    Navigator.pop(
      context,
      PlanEditorResult.saved(
        PlanEditorDraft(
          title: _title.text.trim(),
          translationId: _translationId,
          bookId: _passages.isEmpty
              ? widget.initial.bookId
              : _passages.first.bookId,
          startChapter: _passages.isEmpty
              ? widget.initial.startChapter
              : _passages.first.startChapter,
          endChapter: _passages.isEmpty
              ? widget.initial.endChapter
              : _passages.last.endChapter,
          startDate: _startDate,
          endDate: _endDate,
          passages: _passages,
        ),
      ),
    );
  }

  String _format(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _addPassage() async {
    final passage = await widget.onAddPassage?.call();
    if (passage != null && mounted) {
      setState(() {
        _passages.add(passage);
        if (_days < _passages.length) {
          _endDate = _startDate.add(Duration(days: _passages.length - 1));
        }
      });
    }
  }

  String _bookName(String id) =>
      widget.books.where((book) => book.osisId == id).firstOrNull?.name ?? id;
}
