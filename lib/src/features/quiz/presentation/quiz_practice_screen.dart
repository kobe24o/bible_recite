import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../plans/application/plan_providers.dart';
import '../../recitation/application/recitation_recognizer_provider.dart';
import '../../recitation/application/recitation_scoring_provider.dart';
import '../../recitation/domain/exact_text_comparator.dart';
import '../../recitation/domain/mandarin_phonetic_comparator.dart';
import '../../recitation/domain/recognition_models.dart';
import '../../recitation/domain/speech_recognizer.dart';
import '../../scripture/application/scripture_providers.dart';
import '../domain/quiz_result.dart';
import 'quiz_practice_request.dart';

/// One-word voice quiz.  Each question hides exactly one meaningful word in a
/// verse; the user reads only that word.  Mandarin scoring reuses the
/// phonetic comparator and the “ignore final nasal” setting.
class QuizPracticeScreen extends ConsumerStatefulWidget {
  const QuizPracticeScreen({
    required this.request,
    this.recognizer,
    super.key,
  });

  final QuizPracticeRequest request;
  final OfflineSpeechRecognizer? recognizer;

  @override
  ConsumerState<QuizPracticeScreen> createState() =>
      _QuizPracticeScreenState();
}

class _QuizPracticeScreenState extends ConsumerState<QuizPracticeScreen> {
  static const _exact = ExactTextComparator();
  late final PageController _pageController;
  late final OfflineSpeechRecognizer _recognizer;
  late final bool _ownsRecognizer;
  StreamSubscription<RecognitionEvent>? _subscription;
  int _page = 0;
  String _transcript = '';
  bool _recording = false;
  bool _preparing = false;
  String? _error;
  String? _inputLabel;
  bool _bluetoothInput = false;

  final Map<int, int> _hintCounts = {};
  final Map<int, _QuizAnswer> _answers = {};

  PendingQuizQuestion get _question =>
      widget.request.questions[_page.clamp(0, widget.request.questions.length - 1)];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _ownsRecognizer = widget.recognizer != null;
    _recognizer = widget.recognizer ?? ref.read(recitationRecognizerProvider);
    unawaited(_recognizer.initialize().catchError((_) {}));
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
    final question = _question;
    if (_answers.containsKey(question.id)) return;
    if (_recording) {
      await _recognizer.stop();
      final correct = await _score(question);
      if (!mounted) return;
      setState(() {
        _recording = false;
        _transcript = _transcript.trim();
        _answers[question.id] = _QuizAnswer(
          text: _transcript.trim(),
          correct: correct,
        );
      });
      await _persistAnswer(question, correct);
      return;
    }
    setState(() {
      _preparing = true;
      _error = null;
      _transcript = '';
    });
    try {
      await _recognizer.start(
        languageTag: question.translationId.startsWith('eng') ? 'en' : 'zh',
      );
      if (mounted) setState(() => _recording = true);
    } catch (error) {
      if (mounted) setState(() => _error ??= error.toString());
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<bool> _score(PendingQuizQuestion question) async {
    final spoken = _transcript.trim();
    final mandarinTranslation =
        question.translationId == 'cmn-cu89s' ||
        question.translationId == 'cmn-cu89t';
    if (!mandarinTranslation) {
      return _exact.compare(question.word, spoken, finished: true).correctCount ==
          _comparableCount(question.word) &&
          _comparableCount(spoken) == _comparableCount(question.word);
    }
    final scoring = ref.read(mandarinPhoneticComparatorProvider);
    final base = switch (scoring) {
      AsyncData(:final value) => value,
      _ => null,
    };
    if (base == null) {
      return spoken == question.word;
    }
    final repository = await ref.read(planRepositoryProvider.future);
    final ignoreFinalNasal =
        await repository.getSetting('ignore_final_nasal', 'true') == 'true';
    final alignment = MandarinPhoneticComparator(
      lexicon: base.lexicon,
      ignoreFinalNasal: ignoreFinalNasal,
    ).compare(question.word, spoken, finished: true);
    final expected = _comparableCount(question.word);
    return expected > 0 &&
        alignment.correctCount >= expected &&
        alignment.incorrectCount == 0 &&
        alignment.omittedCount == 0;
  }

  int _comparableCount(String value) => value
      .runes
      .map(String.fromCharCode)
      .where((c) => RegExp(r'^[\p{L}\p{N}]$', unicode: true).hasMatch(c))
      .length;

  Future<void> _persistAnswer(
    PendingQuizQuestion question,
    bool correct,
  ) async {
    try {
      final repository = await ref.read(planRepositoryProvider.future);
      await repository.completeQuizQuestion(
        questionId: question.id,
        correct: correct,
        answeredAt: DateTime.now(),
      );
      ref.read(recitationDataRevisionProvider.notifier).refresh();
    } catch (error) {
      if (mounted) {
        setState(() => _error = '保存答题记录失败：$error');
      }
    }
  }

  void _next() {
    if (_page + 1 >= widget.request.questions.length || _recording) return;
    _pageController.animateToPage(
      _page + 1,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  void _previous() {
    if (_page <= 0 || _recording) return;
    _pageController.animateToPage(
      _page - 1,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  void _showNextHint() {
    final question = _question;
    if (_answers.containsKey(question.id)) return;
    setState(() {
      _hintCounts[question.id] = (_hintCounts[question.id] ?? 0) + 1;
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _pageController.dispose();
    if (_ownsRecognizer) unawaited(_recognizer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    return Scaffold(
      appBar: AppBar(title: Text(chinese ? '经文答题' : 'Verse quiz')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('quiz-previous-button'),
                    onPressed: _page <= 0 || _recording ? null : _previous,
                    icon: const Icon(Icons.navigate_before_rounded),
                    label: Text(chinese ? '上一题' : 'Previous'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('quiz-next-button'),
                    onPressed:
                        _page + 1 >= widget.request.questions.length ||
                            _recording
                        ? null
                        : _next,
                    icon: const Icon(Icons.navigate_next_rounded),
                    label: Text(chinese ? '下一题' : 'Next'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const Key('quiz-record-button'),
              onPressed: _preparing || _answers.containsKey(_question.id)
                  ? null
                  : _toggleRecording,
              icon: _preparing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded),
              label: Text(
                _preparing
                    ? (chinese ? '正在准备离线模型…' : 'Preparing…')
                    : _answers.containsKey(_question.id)
                    ? (chinese ? '本题已完成' : 'Done')
                    : _recording
                    ? (chinese ? '结束录音' : 'Stop')
                    : (chinese ? '答题（朗读隐藏词）' : 'Answer'),
              ),
            ),
          ],
        ),
      ),
      body: widget.request.questions.isEmpty
          ? Center(child: Text(chinese ? '暂无题目' : 'No questions'))
          : Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (index) => setState(() => _page = index),
                    itemCount: widget.request.questions.length,
                    itemBuilder: (context, index) => _QuestionPage(
                      question: widget.request.questions[index],
                      answer: _answers[widget.request.questions[index].id],
                      hintCount:
                          _hintCounts[widget.request.questions[index].id] ?? 0,
                      onHint: _showNextHint,
                      recording:
                          _recording && _question.id ==
                              widget.request.questions[index].id,
                      transcript: _transcript,
                      onMicTap: _toggleRecording,
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_inputLabel != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _bluetoothInput
                              ? Icons.bluetooth_audio_rounded
                              : Icons.phone_android_rounded,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          chinese
                              ? '录音输入：$_inputLabel'
                              : 'Audio: $_inputLabel',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _QuestionPage extends ConsumerWidget {
  const _QuestionPage({
    required this.question,
    required this.answer,
    required this.hintCount,
    required this.onHint,
    required this.recording,
    required this.transcript,
    required this.onMicTap,
  });

  final PendingQuizQuestion question;
  final _QuizAnswer? answer;
  final int hintCount;
  final VoidCallback onHint;
  final bool recording;
  final String transcript;
  final VoidCallback onMicTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final bookNames = ref.watch(bookNameCatalogProvider);
    final locale = Localizations.localeOf(context);
    final title = bookNames.nameFor(question.bookId, locale);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '$title ${question.reference}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          chinese ? '请朗读被隐藏的词语' : 'Read aloud the hidden word',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _renderVerse(context),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.center,
          child: _hintWidget(context, chinese),
        ),
        const SizedBox(height: 12),
        if (answer != null)
          _ResultBanner(
            correct: answer!.correct,
            spoken: answer!.text,
            correctWord: question.word,
          ),
        if (recording && transcript.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '识别中：$transcript',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ],
    );
  }

  Widget _hintWidget(BuildContext context, bool chinese) {
    if (answer != null) {
      return Text(
        chinese ? '已完成本题' : 'Answered',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    String label;
    switch (hintCount) {
      case 0:
        label = chinese
            ? '提示（${question.word.length} 个字）'
            : 'Hint (${question.word.length} chars)';
      case 1:
        final count = _hintCharCount(question.word);
        label = '提示：${question.word.substring(0, count)}';
      case 2:
        label = chinese
            ? '词性：${question.partOfSpeech}'
            : 'POS: ${question.partOfSpeech}';
      default:
        label = chinese ? '字面解释：${question.meaning}' : question.meaning;
    }
    return OutlinedButton.icon(
      key: const Key('quiz-hint-button'),
      onPressed: onHint,
      icon: const Icon(Icons.lightbulb_outline_rounded),
      label: Text(label, textAlign: TextAlign.center),
    );
  }

  int _hintCharCount(String word) {
    final chars = word.runes.length;
    return chars <= 1 ? 1 : chars - 1;
  }

  Widget _renderVerse(BuildContext context) {
    final verseText = question.verseText;
    final start = question.start.clamp(0, verseText.length);
    final end = question.end.clamp(start, verseText.length);
    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyLarge,
        children: [
          if (start > 0)
            TextSpan(text: verseText.substring(0, start)),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: answer == null
                ? InkWell(
                    key: const Key('quiz-mic-inline'),
                    onTap: onMicTap,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).primaryColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${'_' * question.word.length}  ',
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  )
                : Container(
                    key: const Key('quiz-correct-word'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD8F0D8),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(answer!.text.isEmpty
                        ? question.word
                        : answer!.text),
                  ),
          ),
          if (end < verseText.length)
            TextSpan(text: verseText.substring(end)),
        ],
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({
    required this.correct,
    required this.spoken,
    required this.correctWord,
  });

  final bool correct;
  final String spoken;
  final String correctWord;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: correct ? const Color(0xFFE6F4E6) : scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: correct ? Colors.green : scheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  correct ? '答对了！' : '没答对',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: correct ? Colors.green : scheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (spoken.isNotEmpty) Text('你读的：$spoken'),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: '正确答案：'),
                  TextSpan(
                    text: correctWord,
                    style: TextStyle(
                      backgroundColor: const Color(0xFFD8F0D8),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _QuizAnswer {
  const _QuizAnswer({required this.text, required this.correct});
  final String text;
  final bool correct;
}
