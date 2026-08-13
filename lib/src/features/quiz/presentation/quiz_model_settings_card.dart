import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../plans/data/sqlite_plan_repository.dart';
import '../application/quiz_providers.dart';
import '../data/quiz_model_client.dart';
import '../domain/quiz_model_settings.dart';

/// Edits the OpenAI-compatible quiz model settings.  The API key is masked
/// when saved and can be cleared; the connection test sends no scripture.
class QuizModelSettingsCard extends ConsumerStatefulWidget {
  const QuizModelSettingsCard({required this.repository, super.key});

  final SqlitePlanRepository repository;

  @override
  ConsumerState<QuizModelSettingsCard> createState() =>
      _QuizModelSettingsCardState();
}

class _QuizModelSettingsCardState extends ConsumerState<QuizModelSettingsCard> {
  late Future<QuizModelSettings> _future;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.getQuizModelSettings();
  }

  Future<void> _openEditor(QuizModelSettings current) async {
    final urlController = TextEditingController(text: current.baseUrl);
    final modelController = TextEditingController(text: current.model);
    final keyController = TextEditingController(text: current.apiKey);
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final result = await showDialog<_SettingsResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(chinese ? '答题模型设置' : 'Quiz model settings'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: urlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '服务地址',
                  hintText: 'https://open.bigmodel.cn/api/paas/v4',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: modelController,
                decoration: const InputDecoration(
                  labelText: '模型名称',
                  hintText: 'glm-4.7-flash',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: keyController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  hintText: '',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  chinese
                      ? '密钥仅保存在本机，不会同步或上传。'
                      : 'The key stays on this device only.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(chinese ? '取消' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _SettingsResult(
                QuizModelSettings(
                  baseUrl: urlController.text.trim().isEmpty
                      ? QuizModelSettings.defaultBaseUrl
                      : urlController.text.trim(),
                  model: modelController.text.trim().isEmpty
                      ? QuizModelSettings.defaultModel
                      : modelController.text.trim(),
                  apiKey: keyController.text,
                  modelAnsweringEnabled: current.modelAnsweringEnabled,
                ),
              ),
            ),
            child: Text(chinese ? '保存' : 'Save'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    await widget.repository.saveQuizModelSettings(result.settings);
    if (mounted) {
      final saved = result.settings;
      setState(() {
        _future = Future.value(saved);
      });
    }
  }

  Future<void> _testConnection(QuizModelSettings settings) async {
    setState(() => _testing = true);
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final messenger = ScaffoldMessenger.of(context);
    try {
      final client = ref.read(quizModelClientProvider);
      await client.testConnection(settings);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            chinese ? '连接成功：${settings.model}' : 'Connected: ${settings.model}',
          ),
        ),
      );
    } on QuizModelException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('${chinese ? '连接失败：' : 'Failed: '}${error.message}'),
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(chinese ? '连接失败：$error' : 'Failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _setModelAnsweringEnabled(
    QuizModelSettings settings,
    bool enabled,
  ) async {
    final updated = settings.copyWith(modelAnsweringEnabled: enabled);
    await widget.repository.saveQuizModelSettings(updated);
    if (mounted) {
      setState(() {
        _future = Future.value(updated);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    return FutureBuilder<QuizModelSettings>(
      future: _future,
      builder: (context, snapshot) {
        final settings = snapshot.data;
        if (settings == null) {
          return const Card(child: LinearProgressIndicator());
        }
        final configured = settings.apiKey.isNotEmpty;
        return Card(
          child: Column(
            children: [
              SwitchListTile(
                key: const Key('quiz-model-answering-toggle'),
                title: Text(
                  chinese ? '使用大模型出题' : 'Use model-generated quizzes',
                ),
                subtitle: Text(
                  chinese
                      ? '默认关闭；关闭或模型不可用时，优先使用对应范围的本机题库。'
                      : 'Off by default. The local bank is used when unavailable.',
                ),
                value: settings.modelAnsweringEnabled,
                onChanged: (enabled) =>
                    unawaited(_setModelAnsweringEnabled(settings, enabled)),
              ),
              ListTile(
                key: const Key('quiz-model-settings-open'),
                leading: const Icon(Icons.smart_toy_outlined),
                title: Text(chinese ? '答题模型' : 'Quiz model'),
                subtitle: Text(
                  configured
                      ? '${settings.model} · 已配置密钥${settings.modelAnsweringEnabled ? '' : ' · 已关闭'}'
                      : '${settings.model} · 未配置密钥${settings.modelAnsweringEnabled ? '' : ' · 已关闭'}',
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _openEditor(settings),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('quiz-model-test-connection'),
                        onPressed: _testing
                            ? null
                            : () => _testConnection(settings),
                        icon: _testing
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.wifi_tethering_rounded),
                        label: Text(chinese ? '测试连接' : 'Test'),
                      ),
                    ),
                    if (configured) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('quiz-model-clear-key'),
                          onPressed: () async {
                            await widget.repository.clearQuizModelApiKey();
                            if (mounted) {
                              setState(() {
                                _future = widget.repository
                                    .getQuizModelSettings();
                              });
                            }
                          },
                          child: Text(chinese ? '清除密钥' : 'Clear key'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

final class _SettingsResult {
  const _SettingsResult(this.settings);
  final QuizModelSettings settings;
}
