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
    this.ebbinghausEnabled = false,
  });

  final String title;
  final String translationId;
  final String bookId;
  final int startChapter;
  final int endChapter;
  final DateTime startDate;
  final DateTime endDate;
  final List<PlanPassageSelection> passages;
  final bool ebbinghausEnabled;

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
    this.onAddPassages,
    super.key,
  });

  final List<BibleBook> books;
  final PlanEditorDraft initial;
  final bool allowDelete;
  final bool contentLocked;
  final int minimumDays;
  final Future<List<PlanPassageSelection>?> Function()? onAddPassages;

  @override
  State<PlanEditorDialog> createState() => _PlanEditorDialogState();
}

class _PlanEditorDialogState extends State<PlanEditorDialog> {
  late final TextEditingController _title;
  late List<PlanPassageSelection> _passages;
  late String _translationId;
  late DateTime _startDate;
  late DateTime _endDate;
  late bool _ebbinghausEnabled;
  late final ScrollController _passageListController;
  var _showPassageJumpToTop = false;
  var _showPassageJumpToBottom = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initial.title);
    _passages = List.of(widget.initial.passages);
    _translationId = widget.initial.translationId;
    _startDate = widget.initial.startDate;
    _endDate = widget.initial.endDate;
    _ebbinghausEnabled = widget.initial.ebbinghausEnabled;
    _passageListController = ScrollController()
      ..addListener(_updatePassageJumpActions);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _updatePassageJumpActions(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final contentWidth = (MediaQuery.sizeOf(context).width - 96)
        .clamp(280.0, 420.0)
        .toDouble();
    return AlertDialog(
      title: Text(chinese ? '编辑背诵计划' : 'Edit memorization plan'),
      content: SizedBox(
        width: contentWidth,
        child: SingleChildScrollView(
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
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
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
                if (_passages.isNotEmpty) _buildPassageList(chinese),
                if (_passages.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      chinese
                          ? '长按经文并拖动可调整顺序'
                          : 'Long press and drag to reorder',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                OutlinedButton.icon(
                  key: const Key('add-plan-passage'),
                  onPressed: widget.onAddPassages == null ? null : _addPassages,
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
              Text(chinese ? '共 $_days 天' : '$_days days'),
              SwitchListTile(
                key: const Key('plan-ebbinghaus-enabled'),
                contentPadding: EdgeInsets.zero,
                title: Text(chinese ? '开启艾宾浩斯复习' : 'Enable Ebbinghaus reviews'),
                subtitle: Text(
                  chinese
                      ? '仅本计划背诵通过后安排复习'
                      : 'Only passed recitations in this plan are scheduled',
                ),
                value: _ebbinghausEnabled,
                onChanged: (value) =>
                    setState(() => _ebbinghausEnabled = value),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
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
      lastDate: DateTime(9999, 12, 31),
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
    if (!widget.contentLocked && _passages.isEmpty) {
      setState(() => _error = '请添加经文');
      return;
    }
    if (_title.text.trim().isEmpty || _days < 1 || _days < widget.minimumDays) {
      setState(() => _error = '请检查名称和日期（至少 ${widget.minimumDays} 天）');
      return;
    }
    final headerPassages = _passages
        .where((passage) => passage.bookId == _passages.first.bookId)
        .toList(growable: false);
    final startChapter = headerPassages
        .map((passage) => passage.startChapter)
        .reduce((minimum, value) => value < minimum ? value : minimum);
    final endChapter = headerPassages
        .map((passage) => passage.endChapter)
        .reduce((maximum, value) => value > maximum ? value : maximum);
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
              : startChapter,
          endChapter: _passages.isEmpty
              ? widget.initial.endChapter
              : endChapter,
          startDate: _startDate,
          endDate: _endDate,
          passages: _passages,
          ebbinghausEnabled: _ebbinghausEnabled,
        ),
      ),
    );
  }

  String _format(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _passageListController
      ..removeListener(_updatePassageJumpActions)
      ..dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _addPassages() async {
    final passages = await widget.onAddPassages?.call();
    if (passages != null && passages.isNotEmpty && mounted) {
      setState(() {
        _passages.addAll(passages);
        if (_days < _passages.length) {
          _endDate = _startDate.add(Duration(days: _passages.length - 1));
        }
      });
      _refreshPassageJumpActions();
    }
  }

  Widget _buildPassageList(bool chinese) {
    final height = (_passages.length * 56.0).clamp(56.0, 240.0).toDouble();
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          ReorderableListView.builder(
            key: const Key('plan-passage-list'),
            scrollController: _passageListController,
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            itemCount: _passages.length,
            onReorderItem: _reorderPassage,
            itemBuilder: (context, index) {
              final passage = _passages[index];
              return ReorderableDelayedDragStartListener(
                key: ObjectKey(passage),
                index: index,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.drag_indicator_rounded),
                  title: Text(
                    '${_bookName(passage.bookId)} ${passage.startChapter}:${passage.startVerse}–${passage.endChapter}:${passage.endVerse}',
                  ),
                  trailing: IconButton(
                    tooltip: chinese ? '移除经文' : 'Remove passage',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      setState(() => _passages.removeAt(index));
                      _refreshPassageJumpActions();
                    },
                  ),
                ),
              );
            },
          ),
          if (_showPassageJumpToTop)
            Positioned(
              top: 4,
              left: 0,
              right: 0,
              child: Center(
                child: _passageJumpButton(
                  key: const Key('plan-passage-jump-top'),
                  tooltip: chinese ? '返回经文列表顶部' : 'Jump to top',
                  icon: Icons.keyboard_arrow_up_rounded,
                  onPressed: () => _jumpPassageList(toBottom: false),
                ),
              ),
            )
          else if (_showPassageJumpToBottom)
            Positioned(
              bottom: 4,
              left: 0,
              right: 0,
              child: Center(
                child: _passageJumpButton(
                  key: const Key('plan-passage-jump-bottom'),
                  tooltip: chinese ? '跳到经文列表底部' : 'Jump to bottom',
                  icon: Icons.keyboard_arrow_down_rounded,
                  onPressed: () => _jumpPassageList(toBottom: true),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _passageJumpButton({
    required Key key,
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) => Material(
    color: Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.78),
    shape: const CircleBorder(),
    elevation: 2,
    child: IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
    ),
  );

  void _reorderPassage(int oldIndex, int newIndex) {
    setState(() {
      final passage = _passages.removeAt(oldIndex);
      _passages.insert(newIndex, passage);
    });
    _refreshPassageJumpActions();
  }

  void _jumpPassageList({required bool toBottom}) {
    if (!_passageListController.hasClients) return;
    final position = _passageListController.position;
    _passageListController.animateTo(
      toBottom ? position.maxScrollExtent : position.minScrollExtent,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _refreshPassageJumpActions() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _updatePassageJumpActions(),
    );
  }

  void _updatePassageJumpActions() {
    if (!mounted || !_passageListController.hasClients) return;
    final position = _passageListController.position;
    final canMoveUp = position.pixels > position.minScrollExtent + 1;
    final canMoveDown = position.pixels < position.maxScrollExtent - 1;
    final showTop = canMoveUp && !canMoveDown;
    if (showTop == _showPassageJumpToTop &&
        canMoveDown == _showPassageJumpToBottom) {
      return;
    }
    setState(() {
      _showPassageJumpToTop = showTop;
      _showPassageJumpToBottom = canMoveDown;
    });
  }

  String _bookName(String id) =>
      widget.books.where((book) => book.osisId == id).firstOrNull?.name ?? id;
}
