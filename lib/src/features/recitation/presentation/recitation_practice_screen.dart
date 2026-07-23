import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../plans/application/plan_providers.dart';
import '../../scripture/application/scripture_providers.dart';
import '../../scripture/domain/book_name_catalog.dart';
import '../../scripture/domain/scripture_models.dart';
import '../../statistics/domain/recitation_result.dart';
import '../application/recitation_scoring_provider.dart';
import '../application/recitation_recognizer_provider.dart';
import '../domain/exact_text_comparator.dart';
import '../domain/mandarin_phonetic_comparator.dart';
import '../domain/recognition_models.dart';
import '../domain/recitation_alignment.dart';
import '../domain/recitation_comparator.dart';
import '../domain/speech_recognizer.dart';

enum RecitationMode { verse, continuous }

final class RecitationRequest {
  const RecitationRequest({
    required this.translationId,
    required this.bookId,
    required this.chapter,
    required this.mode,
    required this.units,
    this.reviewId,
    this.next,
  });

  final String translationId;
  final String bookId;
  final int chapter;
  final RecitationMode mode;
  final List<VerseUnit> units;
  final int? reviewId;
  final RecitationRequest? next;
}

class RecitationPracticeScreen extends ConsumerStatefulWidget {
  const RecitationPracticeScreen({
    required this.request,
    this.recognizer,
    this.mandarinComparator,
    super.key,
  });

  final RecitationRequest request;
  final OfflineSpeechRecognizer? recognizer;
  final MandarinPhoneticComparator? mandarinComparator;

  @override
  ConsumerState<RecitationPracticeScreen> createState() =>
      _RecitationPracticeScreenState();
}

class _RecitationPracticeScreenState
    extends ConsumerState<RecitationPracticeScreen> {
  static const _exactComparator = ExactTextComparator();
  late final OfflineSpeechRecognizer _recognizer;
  late final bool _ownsRecognizer;
  StreamSubscription<RecognitionEvent>? _subscription;
  String _transcript = '';
  String? _error;
  String? _inputLabel;
  bool _bluetoothInput = false;
  bool _recording = false;
  bool _preparing = false;
  bool _revealed = false;
  bool _finished = false;
  RecitationAlignment? _finishedAlignment;
  int _currentVerse = 0;
  DateTime? _startedAt;

  List<VerseUnit> get _presentUnits => widget.request.units
      .where((unit) => unit.status == SourceTextStatus.present)
      .toList(growable: false);

  String get _target {
    final units = _presentUnits;
    if (units.isEmpty) return '';
    if (widget.request.mode == RecitationMode.verse) {
      return units[_currentVerse.clamp(0, units.length - 1)].text;
    }
    return units.map((unit) => unit.text).join(' ');
  }

  RecitationAlignment get _alignment =>
      _finishedAlignment ??
      _exactComparator.compare(_target, _transcript, finished: _finished);

  @override
  void initState() {
    super.initState();
    _ownsRecognizer = widget.recognizer != null;
    _recognizer = widget.recognizer ?? ref.read(recitationRecognizerProvider);
    unawaited(_recognizer.initialize().catchError((_) {}));
    // Load before recording starts so completion normally has no scoring delay.
    unawaited(
      ref
          .read(mandarinPhoneticComparatorProvider.future)
          .then<void>((_) {}, onError: (_) {}),
    );
    _subscription = _recognizer.events.listen((event) {
      if (!mounted) return;
      setState(() {
        switch (event) {
          case RecognitionPartial(:final text):
            _transcript = text;
          case RecognitionFinal(:final text):
            _transcript = text;
          case RecognitionFailed(:final message):
            _error = message;
          case RecognitionInputChanged(:final label, :final bluetooth):
            _inputLabel = label;
            _bluetoothInput = bluetooth;
        }
      });
    });
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _recognizer.stop();
      final alignment = await _finishedScoring();
      if (mounted) {
        setState(() {
          _recording = false;
          _finished = true;
          _finishedAlignment = alignment;
        });
      }
      await _saveResult(alignment);
      return;
    }
    setState(() {
      _preparing = true;
      _error = null;
      _transcript = '';
      _finished = false;
      _finishedAlignment = null;
      _startedAt = DateTime.now();
    });
    try {
      await _recognizer.start(
        languageTag: widget.request.translationId.startsWith('eng')
            ? 'en'
            : 'zh',
      );
      if (mounted) setState(() => _recording = true);
    } catch (error) {
      if (mounted) setState(() => _error ??= error.toString());
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<RecitationAlignment> _finishedScoring() async {
    final scoring = ref.read(mandarinPhoneticComparatorProvider);
    final mandarin =
        widget.mandarinComparator ??
        switch (scoring) {
          AsyncData(:final value) => value,
          _ => null,
        };
    if (mandarin == null) {
      // Asset loading must never delay or prevent saving a recitation.
      return _exactComparator.compare(_target, _transcript, finished: true);
    }
    final repository = await ref.read(planRepositoryProvider.future);
    final ignoreFinalNasal =
        await repository.getSetting('ignore_final_nasal', 'true') == 'true';
    return comparatorForTranslation(
      widget.request.translationId,
      finished: true,
      mandarin: MandarinPhoneticComparator(
        lexicon: mandarin.lexicon,
        ignoreFinalNasal: ignoreFinalNasal,
      ),
    ).compare(_target, _transcript, finished: true);
  }

  Future<void> _saveResult(RecitationAlignment alignment) async {
    final units = _presentUnits;
    if (units.isEmpty) return;
    final verseMode = widget.request.mode == RecitationMode.verse;
    final startUnit = verseMode ? units[_currentVerse] : units.first;
    final endUnit = verseMode ? units[_currentVerse] : units.last;
    final elapsed = DateTime.now().difference(_startedAt ?? DateTime.now());
    try {
      final repository = await ref.read(planRepositoryProvider.future);
      final resultId = await repository.saveRecitationResult(
        NewRecitationResult(
          translationId: widget.request.translationId,
          bookId: widget.request.bookId,
          chapter: widget.request.chapter,
          startVerse: startUnit.start.verse,
          endVerse: endUnit.end.verse,
          mode: widget.request.mode.name,
          durationSeconds: elapsed.inSeconds,
          correctCount: alignment.correctCount,
          phoneticCorrectCount: alignment.phoneticCorrectCount,
          incorrectCount: alignment.incorrectCount,
          omittedCount: alignment.omittedCount,
          reorderedCount: alignment.reorderedCount,
          accuracy: alignment.accuracy,
          chapterVerseCount: units.length,
          completedAt: DateTime.now(),
        ),
      );
      try {
        await repository.processEbbinghausResult(
          resultId: resultId,
          reviewId: widget.request.reviewId,
        );
      } catch (error) {
        if (mounted) setState(() => _error = '背诵已保存，但复习排期失败：$error');
      }
      final unlocked = await repository.evaluateAndUnlockAchievements(
        source: 'recitation',
      );
      for (final achievement in unlocked) {
        if (!mounted) break;
        unawaited(HapticFeedback.lightImpact().catchError((_) {}));
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(
              Icons.workspace_premium_rounded,
              color: Color(0xFFB88A22),
              size: 42,
            ),
            title: const Text('获得新成就'),
            content: Text(
              '${achievement.definition.title}\n${achievement.definition.description}',
              textAlign: TextAlign.center,
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('太棒了'),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '保存背诵统计失败：$error');
    }
  }

  void _nextVerse() {
    final next = widget.request.next;
    if (next != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => RecitationPracticeScreen(request: next),
        ),
      );
      return;
    }
    if (_currentVerse + 1 >= _presentUnits.length) return;
    setState(() {
      _currentVerse++;
      _transcript = '';
      _finished = false;
      _finishedAlignment = null;
      _revealed = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final locale = Localizations.localeOf(context);
    final bookNames = ref.watch(bookNameCatalogProvider);
    final chapterLabel = bookNames.chapterLabel(
      widget.request.bookId,
      widget.request.chapter,
      locale,
    );
    final units = _presentUnits;
    final alignment = _alignment;
    final verseMode = widget.request.mode == RecitationMode.verse;
    final currentReference = verseMode
        ? _referenceFor(units[_currentVerse], bookNames, locale)
        : '${_referenceFor(units.first, bookNames, locale)} – '
              '${_referenceFor(units.last, bookNames, locale)}';
    return Scaffold(
      appBar: AppBar(title: Text(chinese ? '离线背诵' : 'Offline recitation')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              const Icon(Icons.offline_bolt_rounded, color: Colors.green),
              const SizedBox(width: 8),
              Text(chinese ? '完全离线识别' : 'Fully offline recognition'),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            verseMode
                ? (chinese
                      ? '第 ${_currentVerse + 1} / ${units.length} 节'
                      : 'Verse ${_currentVerse + 1} / ${units.length}')
                : (chinese
                      ? '连续背诵 · ${units.length} 节'
                      : 'Continuous · ${units.length} verses'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(chapterLabel, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            verseMode
                ? (chinese
                      ? '当前背诵：$currentReference'
                      : 'Reciting: $currentReference')
                : (chinese
                      ? '本次经文：$currentReference'
                      : 'Passage: $currentReference'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _revealed
                  ? units.length == 1
                        ? Text(
                            _target,
                            style: Theme.of(context).textTheme.bodyLarge,
                          )
                        : Column(
                            children: [
                              for (final unit in units) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Theme.of(context).dividerColor,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 82,
                                        child: Text(
                                          _referenceFor(
                                            unit,
                                            bookNames,
                                            locale,
                                          ),
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelLarge,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          unit.text,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodyLarge,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (unit != units.last)
                                  const SizedBox(height: 10),
                              ],
                            ],
                          )
                  : Text(
                      chinese ? '经文已隐藏，点击提示可查看。' : 'Scripture hidden.',
                      textAlign: TextAlign.center,
                    ),
            ),
          ),
          TextButton.icon(
            onPressed: () => setState(() => _revealed = !_revealed),
            icon: Icon(_revealed ? Icons.visibility_off : Icons.visibility),
            label: Text(chinese ? '显示／隐藏经文' : 'Show / hide scripture'),
          ),
          const SizedBox(height: 16),
          Text(chinese ? '实时背诵结果' : 'Live recitation result'),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(minHeight: 110),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _transcript.isEmpty && !_finished
                ? Text(chinese ? '点击麦克风开始背诵' : 'Tap the microphone to start')
                : RichText(
                    key: const Key('alignment-output'),
                    text: TextSpan(
                      style: Theme.of(context).textTheme.bodyLarge,
                      children: [
                        for (final token in alignment.tokens)
                          TextSpan(
                            text: token.text,
                            style: TextStyle(
                              color: _colorFor(context, token.kind),
                              fontWeight:
                                  token.kind == RecitationTokenKind.correct ||
                                      token.kind ==
                                          RecitationTokenKind.phoneticCorrect
                                  ? FontWeight.w600
                                  : FontWeight.w700,
                              decoration:
                                  token.kind == RecitationTokenKind.omitted
                                  ? TextDecoration.underline
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          if (_recording || _transcript.isNotEmpty || _finished) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              children: [
                _Legend(color: Colors.green, label: chinese ? '正确' : 'Correct'),
                if (_finished && alignment.phoneticCorrectCount > 0)
                  _Legend(
                    color: Colors.teal,
                    label: chinese ? '同音修正' : 'Phonetic correction',
                  ),
                _Legend(
                  color: Colors.red,
                  label: chinese ? '错误／漏字' : 'Wrong / missing',
                ),
                _Legend(
                  color: Colors.orange,
                  label: chinese ? '顺序错误' : 'Out of order',
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_inputLabel != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _bluetoothInput
                      ? Icons.bluetooth_audio_rounded
                      : Icons.phone_android_rounded,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    chinese ? '录音输入：$_inputLabel' : 'Audio input: $_inputLabel',
                  ),
                ),
              ],
            ),
          ],
          if (_finished) ...[
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.analytics_outlined),
              title: Text(
                chinese
                    ? '本次正确率 ${(alignment.accuracy * 100).round()}%'
                    : 'Accuracy ${(alignment.accuracy * 100).round()}%',
              ),
              subtitle: Text(
                chinese
                    ? '原字正确 ${alignment.exactCorrectCount} · 错误 ${alignment.incorrectCount} · '
                          '${alignment.phoneticCorrectCount > 0 ? '同音修正 ${alignment.phoneticCorrectCount} · ' : ''}'
                          '漏字 ${alignment.omittedCount} · 错序 ${alignment.reorderedCount}'
                    : 'Exact ${alignment.exactCorrectCount} · Wrong ${alignment.incorrectCount} · '
                          '${alignment.phoneticCorrectCount > 0 ? 'Phonetic ${alignment.phoneticCorrectCount} · ' : ''}'
                          'Missing ${alignment.omittedCount} · Reordered ${alignment.reorderedCount}',
              ),
            ),
            if (widget.request.next != null ||
                (verseMode && _currentVerse + 1 < units.length))
              OutlinedButton.icon(
                key: const Key('next-verse-button'),
                onPressed: _nextVerse,
                icon: const Icon(Icons.navigate_next_rounded),
                label: Text(
                  widget.request.next != null
                      ? (chinese ? '下一项计划' : 'Next planned passage')
                      : (chinese ? '下一节' : 'Next verse'),
                ),
              ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('record-button'),
            onPressed: _preparing ? null : _toggleRecording,
            icon: _preparing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded),
            label: Text(
              _preparing
                  ? (chinese ? '正在准备离线模型…' : 'Preparing offline model…')
                  : _recording
                  ? (chinese ? '结束背诵' : 'Finish')
                  : (chinese ? '开始录音' : 'Start recording'),
            ),
          ),
        ],
      ),
    );
  }

  String _referenceFor(
    VerseUnit unit,
    BookNameCatalog bookNames,
    Locale locale,
  ) {
    final start = unit.start;
    final end = unit.end;
    final verseRange = start.chapter == end.chapter && start.verse != end.verse
        ? '${start.chapter}:${start.verse}-${end.verse}'
        : start.chapter == end.chapter
        ? '${start.chapter}:${start.verse}'
        : '${start.chapter}:${start.verse}-${end.chapter}:${end.verse}';
    return '${bookNames.nameFor(start.osisBookId, locale)} $verseRange';
  }

  Color _colorFor(
    BuildContext context,
    RecitationTokenKind kind,
  ) => switch (kind) {
    RecitationTokenKind.correct ||
    RecitationTokenKind.phoneticCorrect => Colors.green,
    RecitationTokenKind.incorrect || RecitationTokenKind.omitted => Colors.red,
    RecitationTokenKind.reordered => Colors.orange,
    RecitationTokenKind.pending => Colors.grey,
    RecitationTokenKind.formatting => Theme.of(context).colorScheme.onSurface,
  };

  @override
  void dispose() {
    _subscription?.cancel();
    if (_ownsRecognizer) unawaited(_recognizer.dispose());
    super.dispose();
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label),
    ],
  );
}
