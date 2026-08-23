import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../plans/application/plan_providers.dart';
import '../../plans/data/sqlite_plan_repository.dart';
import '../../quiz/application/quiz_preparation_controller.dart';
import '../../quiz/application/quiz_providers.dart';
import '../../quiz/domain/quiz_scope.dart';
import '../../quiz/domain/quiz_result.dart';
import '../../quiz/presentation/quiz_practice_request.dart';
import '../../quiz/presentation/quiz_practice_screen.dart';
import '../../reminder/reminder_providers.dart';
import '../../scripture/application/scripture_providers.dart';
import '../../scripture/domain/book_name_catalog.dart';
import '../../scripture/domain/scripture_models.dart';
import '../../statistics/domain/recitation_result.dart';
import '../../statistics/domain/achievement.dart';
import '../../statistics/presentation/achievement_unlock_dialog.dart';
import '../../../widgets/completion_confetti.dart';
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
    this.planTaskId,
    this.planId,
    this.next,
    this.quizScope,
    this.quizScopes = const [],
    this.todayQuizEntry = false,
  });

  final String translationId;
  final String bookId;
  final int chapter;
  final RecitationMode mode;
  final List<VerseUnit> units;
  final int? reviewId;
  final int? planTaskId;
  final int? planId;
  final RecitationRequest? next;
  final QuizScope? quizScope;
  final List<QuizScope> quizScopes;
  final bool todayQuizEntry;
}

final class _QuizPreparation {
  const _QuizPreparation({this.request, this.error})
    : assert(request != null || error != null);

  final QuizPracticeRequest? request;
  final String? error;
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
  bool _revealed = true;
  bool _showScriptureByDefault = true;
  bool _finished = false;
  bool _celebrating = false;
  RecitationAlignment? _finishedAlignment;
  int _currentVerse = 0;
  DateTime? _startedAt;
  Future<_QuizPreparation>? _preparedQuiz;
  QuizPreparationController? _todayQuizPreparation;
  late final Future<void> _scriptureVisibilityLoading;

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

  List<RecitationToken> get _displayedAlignmentTokens {
    if (_finished) return _alignment.tokens;
    return _alignment.tokens
        .where(
          (token) =>
              token.kind == RecitationTokenKind.correct ||
              token.kind == RecitationTokenKind.phoneticCorrect,
        )
        .toList(growable: false);
  }

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
    _scriptureVisibilityLoading = _loadScriptureVisibility();
    final quizScopes = _quizScopes;
    if (widget.request.todayQuizEntry && quizScopes.isNotEmpty) {
      _armTodayQuiz(quizScopes);
    } else if (quizScopes.isNotEmpty && widget.request.next == null) {
      _preparedQuiz = _prepareQuiz(quizScopes);
    }
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

  List<QuizScope> get _quizScopes {
    final explicit = widget.request.quizScopes;
    if (explicit.isNotEmpty) return explicit;
    final legacy = widget.request.quizScope;
    return legacy == null ? const [] : [legacy];
  }

  void _armTodayQuiz(List<QuizScope> scopes) {
    final preparation = QuizPreparationController(
      scope: scopes.first,
      scopes: scopes,
      serviceLoader: () => ref.read(quizGenerationServiceProvider.future),
    );
    preparation.addListener(_onTodayQuizPreparationChanged);
    _todayQuizPreparation = preparation;
    preparation.arm();
  }

  void _onTodayQuizPreparationChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openTodayQuiz() async {
    final preparation = _todayQuizPreparation;
    if (preparation == null ||
        preparation.phase != QuizPreparationPhase.ready ||
        preparation.questions.isEmpty) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuizPracticeScreen(
          request: QuizPracticeRequest(
            scope: preparation.scope,
            questions: preparation.questions,
          ),
        ),
      ),
    );
  }

  Future<void> _loadScriptureVisibility() async {
    var showScripture = true;
    try {
      final repository = await ref.read(planRepositoryProvider.future);
      showScripture =
          await repository.getSetting('show_recitation_scripture', 'true') ==
          'true';
    } catch (_) {
      // Keep the default available if local settings cannot be read.
    }
    if (!mounted) return;
    setState(() => _showScriptureByDefault = showScripture);
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
    setState(() => _preparing = true);
    try {
      await _scriptureVisibilityLoading;
      if (!mounted) return;
      setState(() {
        _error = null;
        _transcript = '';
        _finished = false;
        _finishedAlignment = null;
        _startedAt = DateTime.now();
        _revealed = _showScriptureByDefault;
      });
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
    final startedAt = _startedAt ?? DateTime.now();
    final elapsed = DateTime.now().difference(startedAt);
    final scoredUnits = verseMode ? [units[_currentVerse]] : units;
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
          planId: widget.request.planId,
          startedAt: startedAt,
          verseMetrics: _verseMetrics(scoredUnits, alignment.accuracy, elapsed),
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
      var allTodayCompleted = false;
      Future<void>? completionCelebration;
      final unlocked = <AchievementUnlock>[];
      if (widget.request.planTaskId != null) {
        unlocked.addAll(
          await repository.setTaskCompleted(widget.request.planTaskId!, true),
        );
        allTodayCompleted =
            (await repository.dueTasks(DateTime.now())).isEmpty &&
            (await repository.dueEbbinghausReviews(DateTime.now())).isEmpty;
        if (allTodayCompleted) {
          completionCelebration = _celebrateCompletion();
        }
        await ref
            .read(dailyTaskReminderSchedulerProvider)
            .reschedule(repository);
      }
      unlocked.addAll(
        await repository.evaluateAndUnlockAchievements(source: 'recitation'),
      );
      ref.read(recitationDataRevisionProvider.notifier).refresh();
      await completionCelebration;
      for (final achievement in unlocked) {
        if (!mounted) break;
        unawaited(HapticFeedback.lightImpact().catchError((_) {}));
        await showAchievementUnlockDialog(
          context,
          AchievementProgress(
            definition: achievement.definition,
            current: achievement.definition.target * achievement.awardCount,
            satisfied: true,
            unlockedAt: achievement.unlockedAt,
            awardCount: achievement.awardCount,
          ),
          newlyUnlocked: true,
        );
        break;
      }
      await _openPreparedQuiz();
    } catch (error) {
      if (mounted) setState(() => _error = '保存背诵统计失败：$error');
    }
  }

  Future<_QuizPreparation> _prepareQuiz(List<QuizScope> scopes) async {
    try {
      final service = await ref.read(quizGenerationServiceProvider.future);
      final outcome = await service.prepareScopes(scopes);
      final questions = await _questionsForScopes(service.repository, scopes);
      if (questions.isNotEmpty) {
        return _QuizPreparation(
          request: QuizPracticeRequest(
            scope: scopes.first,
            questions: questions,
          ),
        );
      }
      if (!outcome.success) {
        return _QuizPreparation(error: outcome.error);
      }
      return const _QuizPreparation(error: '没有可开始的答题题目');
    } catch (error) {
      return _QuizPreparation(error: '答题准备失败：$error');
    }
  }

  Future<List<PendingQuizQuestion>> _questionsForScopes(
    SqlitePlanRepository repository,
    List<QuizScope> scopes,
  ) async {
    final questions = <PendingQuizQuestion>[];
    final ids = <int>{};
    for (final scope in scopes) {
      for (final question in await repository.listQuizQuestionsForPractice(
        scope,
      )) {
        if (!scope.containsVerse(
          translationId: question.translationId,
          bookId: question.bookId,
          chapter: question.chapter,
          verse: question.verse,
        )) {
          continue;
        }
        if (ids.add(question.id)) questions.add(question);
      }
    }
    return questions;
  }

  Future<void> _openPreparedQuiz() async {
    if (widget.request.todayQuizEntry) return;
    if (widget.request.next != null) return;
    final scopes = _quizScopes;
    if (scopes.isEmpty) return;
    final preparation = _preparedQuiz ??= _prepareQuiz(scopes);
    final prepared = await preparation;
    if (!mounted) return;
    final request = prepared.request;
    if (request == null) {
      setState(() => _error = prepared.error ?? '答题暂未就绪');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuizPracticeScreen(request: request),
      ),
    );
  }

  List<NewRecitationVerseMetric> _verseMetrics(
    List<VerseUnit> units,
    double accuracy,
    Duration elapsed,
  ) {
    final totalWeight = units.fold<int>(
      0,
      (total, unit) => total + unit.text.runes.length,
    );
    var assignedSeconds = 0;
    return [
      for (var index = 0; index < units.length; index++)
        NewRecitationVerseMetric(
          bookId: units[index].start.osisBookId,
          chapter: units[index].start.chapter,
          verse: units[index].start.verse,
          accuracy: accuracy,
          durationSeconds: index == units.length - 1
              ? elapsed.inSeconds - assignedSeconds
              : (() {
                  final seconds = totalWeight == 0
                      ? 0
                      : (elapsed.inSeconds *
                            units[index].text.runes.length ~/
                            totalWeight);
                  assignedSeconds += seconds;
                  return seconds;
                })(),
          characterCount: units[index].text.runes.length,
        ),
    ];
  }

  Future<void> _celebrateCompletion() async {
    if (!mounted) return;
    setState(() => _celebrating = true);
    await Future<void>.delayed(const Duration(seconds: 8));
    if (mounted) setState(() => _celebrating = false);
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
      _revealed = true;
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
    final displayedUnits = verseMode ? [units[_currentVerse]] : units;
    final currentReference = verseMode
        ? _referenceFor(units[_currentVerse], bookNames, locale)
        : '${_referenceFor(units.first, bookNames, locale)} – '
              '${_referenceFor(units.last, bookNames, locale)}';
    return Scaffold(
      appBar: AppBar(title: Text(chinese ? '离线背诵' : 'Offline recitation')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_todayQuizPreparation case final preparation?) ...[
              OutlinedButton.icon(
                key: const Key('today-quiz-entry-button'),
                onPressed:
                    preparation.phase == QuizPreparationPhase.ready &&
                        preparation.questions.isNotEmpty
                    ? _openTodayQuiz
                    : null,
                icon: const Icon(Icons.quiz_outlined),
                label: Text(
                  _todayQuizButtonLabel(preparation, chinese),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 10),
            ],
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
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                Text(
                  chapterLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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
                        ? displayedUnits.length == 1
                              ? Text(
                                  _target,
                                  style: Theme.of(context).textTheme.bodyLarge,
                                )
                              : Column(
                                  children: [
                                    for (final unit in displayedUnits) ...[
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Theme.of(
                                              context,
                                            ).dividerColor,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
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
                                      if (unit != displayedUnits.last)
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
                  icon: Icon(
                    _revealed ? Icons.visibility_off : Icons.visibility,
                  ),
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
                      ? Text(
                          chinese ? '点击麦克风开始背诵' : 'Tap the microphone to start',
                        )
                      : RichText(
                          key: const Key('alignment-output'),
                          text: TextSpan(
                            style: Theme.of(context).textTheme.bodyLarge,
                            children: [
                              for (final token in _displayedAlignmentTokens)
                                TextSpan(
                                  text: token.text,
                                  style: TextStyle(
                                    color: _colorFor(context, token.kind),
                                    fontWeight:
                                        token.kind ==
                                                RecitationTokenKind.correct ||
                                            token.kind ==
                                                RecitationTokenKind
                                                    .phoneticCorrect
                                        ? FontWeight.w600
                                        : FontWeight.w700,
                                    decoration:
                                        token.kind ==
                                            RecitationTokenKind.omitted
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
                      _Legend(
                        color: Colors.green,
                        label: chinese ? '正确' : 'Correct',
                      ),
                      if (_finished && alignment.phoneticCorrectCount > 0)
                        _Legend(
                          color: Colors.teal,
                          label: chinese ? '同音修正' : 'Phonetic correction',
                        ),
                      if (_finished) ...[
                        _Legend(
                          color: Colors.red,
                          label: chinese ? '错误／漏字' : 'Wrong / missing',
                        ),
                        _Legend(
                          color: Colors.orange,
                          label: chinese ? '顺序错误' : 'Out of order',
                        ),
                      ],
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
                          chinese
                              ? '录音输入：$_inputLabel'
                              : 'Audio input: $_inputLabel',
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
                ],
                if (widget.request.next != null ||
                    (verseMode && _currentVerse + 1 < units.length))
                  OutlinedButton.icon(
                    key: const Key('next-verse-button'),
                    onPressed: _finished ? _nextVerse : null,
                    icon: const Icon(Icons.navigate_next_rounded),
                    label: Text(
                      widget.request.next != null
                          ? (chinese ? '下一项计划' : 'Next planned passage')
                          : (chinese ? '下一节' : 'Next verse'),
                    ),
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ),
          if (_celebrating)
            const Positioned.fill(
              child: CompletionConfetti(
                key: Key('recitation-completion-confetti'),
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

  String _todayQuizButtonLabel(
    QuizPreparationController preparation,
    bool chinese,
  ) => switch (preparation.phase) {
    QuizPreparationPhase.waiting =>
      chinese ? '答题（5 秒后准备）' : 'Quiz (starts in 5s)',
    QuizPreparationPhase.preparing => chinese ? '正在生成题目…' : 'Preparing quiz…',
    QuizPreparationPhase.ready => chinese ? '开始答题' : 'Start quiz',
    QuizPreparationPhase.failed =>
      chinese
          ? '答题失败：${preparation.error ?? '题目未生成'}'
          : 'Quiz failed: ${preparation.error ?? 'No questions'}',
    QuizPreparationPhase.idle => chinese ? '答题准备中' : 'Quiz pending',
  };

  @override
  void dispose() {
    final preparation = _todayQuizPreparation;
    preparation?.removeListener(_onTodayQuizPreparationChanged);
    preparation?.dispose();
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
