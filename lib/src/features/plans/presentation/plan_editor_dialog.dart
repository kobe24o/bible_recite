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
  });

  final String title;
  final String translationId;
  final String bookId;
  final int startChapter;
  final int endChapter;
  final DateTime startDate;
  final DateTime endDate;

  int get days => endDate.difference(startDate).inDays + 1;
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
    super.key,
  });

  final List<BibleBook> books;
  final PlanEditorDraft initial;
  final bool allowDelete;
  final bool contentLocked;
  final int minimumDays;

  @override
  State<PlanEditorDialog> createState() => _PlanEditorDialogState();
}

class _PlanEditorDialogState extends State<PlanEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _startChapter;
  late final TextEditingController _endChapter;
  late String _bookId;
  late String _translationId;
  late DateTime _startDate;
  late DateTime _endDate;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initial.title);
    _startChapter = TextEditingController(
      text: '${widget.initial.startChapter}',
    );
    _endChapter = TextEditingController(text: '${widget.initial.endChapter}');
    _bookId = widget.initial.bookId;
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
              DropdownButtonFormField<String>(
                key: const Key('plan-book'),
                initialValue: _bookId,
                decoration: InputDecoration(
                  labelText: chinese ? '经卷' : 'Book',
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final book in widget.books)
                    DropdownMenuItem(
                      value: book.osisId,
                      child: Text(book.name),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _bookId = value);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('start-chapter'),
                      controller: _startChapter,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: chinese ? '开始章' : 'Start chapter',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      key: const Key('end-chapter'),
                      controller: _endChapter,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: chinese ? '结束章' : 'End chapter',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
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
    final startChapter = int.tryParse(_startChapter.text);
    final endChapter = int.tryParse(_endChapter.text);
    final book = widget.books
        .where((book) => book.osisId == _bookId)
        .firstOrNull;
    if (_title.text.trim().isEmpty ||
        startChapter == null ||
        endChapter == null ||
        startChapter < 1 ||
        endChapter < startChapter ||
        (!widget.contentLocked &&
            (book == null || endChapter > book.chapterCount)) ||
        _days < 1 ||
        _days < widget.minimumDays ||
        _days > 365) {
      setState(() => _error = '请检查名称、章节范围和日期（${widget.minimumDays}–365 天）');
      return;
    }
    Navigator.pop(
      context,
      PlanEditorResult.saved(
        PlanEditorDraft(
          title: _title.text.trim(),
          translationId: _translationId,
          bookId: _bookId,
          startChapter: startChapter,
          endChapter: endChapter,
          startDate: _startDate,
          endDate: _endDate,
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
    _startChapter.dispose();
    _endChapter.dispose();
    super.dispose();
  }
}
