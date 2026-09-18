import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../plans/application/plan_providers.dart';
import '../../scripture/application/scripture_providers.dart';
import '../../scripture/presentation/passage_screen.dart';
import '../application/devotion_providers.dart';
import '../domain/devotion_models.dart';
import 'devotion_schedule_screen.dart';

class DevotionDetailScreen extends ConsumerStatefulWidget {
  const DevotionDetailScreen({required this.date, super.key});

  final DateTime date;

  @override
  ConsumerState<DevotionDetailScreen> createState() =>
      _DevotionDetailScreenState();
}

class _DevotionDetailScreenState extends ConsumerState<DevotionDetailScreen> {
  final _noteController = TextEditingController();
  Timer? _saveTimer;
  Future<bool>? _saveOperation;
  DevotionDay? _day;
  String _savedText = '';
  String _saveStatus = '';
  bool _loading = true;
  bool _loadFailed = false;
  bool _openingPassage = false;

  bool get _dirty => _noteController.text != _savedText;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repository = await ref.read(planRepositoryProvider.future);
      final manifest = await ref.read(cachedDevotionManifestProvider.future);
      final note = await repository.devotionNoteFor(widget.date);
      if (!mounted) {
        return;
      }
      setState(() {
        _day = manifest?.dayFor(widget.date);
        _savedText = note?.content ?? '';
        _noteController.text = _savedText;
        _loading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  void _noteChanged(String _) {
    _saveTimer?.cancel();
    setState(() => _saveStatus = _dirty ? '尚未保存' : '已保存');
    _saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<bool> _save() async {
    _saveTimer?.cancel();
    if (_saveOperation != null) return _saveOperation!;
    if (!_dirty) return true;
    final operation = _persistNote();
    _saveOperation = operation;
    try {
      return await operation;
    } finally {
      _saveOperation = null;
    }
  }

  Future<bool> _persistNote() async {
    setState(() => _saveStatus = '正在保存…');
    try {
      final repository = await ref.read(planRepositoryProvider.future);
      // Serialize writes and include edits made while an earlier write was pending.
      while (mounted && _dirty) {
        final text = _noteController.text;
        await repository.saveDevotionNote(widget.date, text);
        if (!mounted) return true;
        setState(() => _savedText = text);
      }
      if (mounted) setState(() => _saveStatus = '已保存');
      return true;
    } catch (_) {
      if (mounted) setState(() => _saveStatus = '保存失败，文字已保留，请重试保存');
      return false;
    }
  }

  Future<void> _openPassage() async {
    if (_openingPassage) return;
    setState(() => _openingPassage = true);
    try {
      if (!await _save() || !mounted) return;
      final scripture = await ref.read(scriptureRepositoryProvider.future);
      final translations = await scripture.listTranslations();
      if (!mounted) return;
      if (translations.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先安装圣经译本')));
        return;
      }
      final groups = _day!.chapterGroups();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PassageScreen(
            translationId: translations.first.id,
            bookId: groups.first.bookId,
            chapter: groups.first.chapter,
            planTaskGroups: groups,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开经文，请重试')));
      }
    } finally {
      if (mounted) setState(() => _openingPassage = false);
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final names = ref.watch(bookNameCatalogProvider);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _save() && context.mounted) Navigator.of(context).pop(result);
      },
      child: Scaffold(
        appBar: AppBar(title: Text('${devotionDateLabel(widget.date)} 灵修')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadFailed
            ? Center(
                child: TextButton(
                  onPressed: _load,
                  child: const Text('读取失败，重试'),
                ),
              )
            : _day == null
            ? const Center(child: Text('该日期尚无缓存日程，请返回年度灵修同步'))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final passage in _day!.passages)
                    Card(
                      child: ListTile(
                        title: Text(
                          devotionPassageLabel(
                            passage,
                            names.nameFor(
                              passage.bookId,
                              Localizations.localeOf(context),
                            ),
                          ),
                        ),
                        trailing: const Icon(Icons.menu_book_outlined),
                        onTap: _openingPassage ? null : _openPassage,
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('devotion-note-input'),
                    controller: _noteController,
                    minLines: 5,
                    maxLines: null,
                    decoration: const InputDecoration(
                      labelText: '灵修笔记',
                      hintText: '记录今天的领受…',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: _noteChanged,
                  ),
                  const SizedBox(height: 12),
                  Text(_saveStatus, key: const Key('devotion-note-status')),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      key: const Key('save-devotion-note'),
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('保存笔记'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
