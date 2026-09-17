import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/runtime_platform.dart';
import '../../devotion/application/devotion_providers.dart';
import '../../plans/application/plan_providers.dart';
import '../../plans/data/sqlite_plan_repository.dart';
import '../../quiz/application/quiz_providers.dart';
import '../domain/user_data_backup.dart';

final userDataBackupFilesProvider = Provider<UserDataBackupFiles>(
  (ref) => UserDataBackupFiles(ref.watch(appRuntimePlatformProvider)),
);

/// Keeps platform file access separate from validation and database changes.
class UserDataBackupFiles {
  const UserDataBackupFiles(this.platform);
  final AppRuntimePlatform platform;
  static const _types = [
    XTypeGroup(
      label: 'JSON',
      extensions: ['json'],
      mimeTypes: ['application/json'],
    ),
  ];
  static const _channel = MethodChannel('app.biblerecite/plan_json_store');

  Future<XFile?> choose() => openFile(acceptedTypeGroups: _types);

  Future<String?> save(Uint8List bytes, String name) async {
    if (platform == AppRuntimePlatform.android) {
      await _channel.invokeMethod<String>('saveJson', {
        'bytes': bytes,
        'displayName': name,
      });
      return 'Download/BibleRecite/$name';
    }
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: _types,
    );
    if (location == null) return null;
    await XFile.fromData(
      bytes,
      mimeType: 'application/json',
      name: name,
    ).saveTo(location.path);
    return location.path;
  }
}

class UserDataBackupCard extends ConsumerStatefulWidget {
  const UserDataBackupCard({super.key, required this.repository});
  final SqlitePlanRepository repository;

  @override
  ConsumerState<UserDataBackupCard> createState() => _UserDataBackupCardState();
}

class _UserDataBackupCardState extends ConsumerState<UserDataBackupCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: [
        const ListTile(
          leading: Icon(Icons.backup_outlined),
          title: Text('数据备份与恢复'),
          subtitle: Text('保存计划、学习记录、勋章、灵修笔记和设置。圣经包、模型密钥及同步缓存不包含在备份中。'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('export-user-data'),
                onPressed: _busy ? null : _export,
                icon: const Icon(Icons.ios_share_outlined),
                label: const Text('导出备份'),
              ),
              FilledButton.tonalIcon(
                key: const Key('restore-user-data'),
                onPressed: _busy ? null : _restore,
                icon: const Icon(Icons.restore),
                label: const Text('恢复备份'),
              ),
              if (_busy) const Text('处理中…'),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final files = ref.read(userDataBackupFilesProvider);
      final backup = await widget.repository.exportUserData();
      final now = DateTime.now();
      final date =
          '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final path = await files.save(
        Uint8List.fromList(utf8.encode(backup.encode())),
        'BibleRecite-backup-$date.json',
      );
      if (mounted && path != null) _message('备份已保存：$path');
    } catch (error) {
      if (mounted) _message('导出失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final file = await ref.read(userDataBackupFilesProvider).choose();
      if (file == null) return;
      if (await file.length() > UserDataBackup.maxBytes) {
        throw const FormatException('备份文件超过 20 MB');
      }
      final backup = UserDataBackup.decode(
        utf8.decode(await file.readAsBytes()),
      );
      if (!mounted) return;
      final mode = await showDialog<RestoreMode>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('选择恢复方式'),
          content: Text(
            '已验证备份：${backup.records['memorization_plan']!.length} 个计划，'
            '${backup.records['recitation_result']!.length} 条背诵记录，${backup.devotionNotes.length} 篇灵修笔记。\n\n'
            '合并会保留本机记录，笔记使用较新的版本；更新时间相同则保留本机笔记。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              key: const Key('restore-replace'),
              onPressed: () => Navigator.pop(context, RestoreMode.replace),
              child: const Text('完全覆盖'),
            ),
            FilledButton(
              key: const Key('restore-merge'),
              onPressed: () => Navigator.pop(context, RestoreMode.merge),
              child: const Text('合并'),
            ),
          ],
        ),
      );
      if (!mounted || mode == null) return;
      if (mode == RestoreMode.replace) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认完全覆盖？'),
            content: const Text(
              '本机的计划、学习记录、勋章、灵修笔记和普通设置将替换为此备份；备份中没有的记录会被删除。建议先导出本机备份。',
            ),
            actions: [
              TextButton(
                key: const Key('cancel-restore-replace'),
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const Key('confirm-restore-replace'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('完全覆盖'),
              ),
            ],
          ),
        );
        if (!mounted || confirmed != true) return;
      }
      final report = await widget.repository.restoreUserData(
        backup,
        mode: mode,
      );
      if (!mounted) return;
      ref.read(recitationDataRevisionProvider.notifier).refresh();
      ref.read(profileRevisionProvider.notifier).refresh();
      ref.read(presetPlanRevisionProvider.notifier).refresh();
      ref.read(devotionRevisionProvider.notifier).refresh();
      ref.read(quizBankRevisionProvider.notifier).refresh();
      ref.invalidate(quizGenerationServiceProvider);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('restore-report'),
          title: const Text('恢复完成'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '导入 ${report.imported} 条 · 跳过 ${report.skipped} 条 · 保留本机 ${report.retained} 条',
                ),
                const SizedBox(height: 12),
                for (final entry in report.categories.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${_labels[entry.key]}：导入 ${entry.value.imported}，跳过 ${entry.value.skipped}，保留 ${entry.value.retained}',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) _message('恢复失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

const _labels = {
  'memorization_plan': '计划',
  'plan_schedule_span': '长期日程',
  'plan_task': '计划任务',
  'plan_task_block': '经文分段',
  'recitation_result': '背诵记录',
  'recitation_verse_metric': '逐节指标',
  'quiz_question': '题目',
  'quiz_result': '答题记录',
  'achievement_unlock': '勋章',
  'ebbinghaus_settings': '复习设置',
  'ebbinghaus_cycle': '复习周期',
  'ebbinghaus_review': '复习安排',
  'devotion_note': '灵修笔记',
  'app_setting': '普通设置',
};
