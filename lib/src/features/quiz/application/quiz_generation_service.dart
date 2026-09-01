import 'dart:math';

import '../../plans/data/sqlite_plan_repository.dart';
import '../../scripture/domain/scripture_models.dart';
import '../../scripture/domain/scripture_repository.dart';
import '../data/quiz_model_client.dart';
import '../domain/quiz_model_settings.dart';
import '../domain/quiz_models.dart';
import '../domain/quiz_question_source.dart';
import '../domain/quiz_question_validator.dart';
import '../domain/quiz_scope.dart';

/// Optional hook for tests to intercept settings loads.
typedef QuizSettingsLoader = Future<QuizModelSettings> Function();

final class QuizGenerationService {
  QuizGenerationService({
    required this.repository,
    required this.scripture,
    required this.client,
    this.settingsLoader,
    this.validator = const QuizQuestionValidator(),
  });

  final SqlitePlanRepository repository;
  final ScriptureRepository scripture;
  final QuizModelClient client;
  final QuizSettingsLoader? settingsLoader;
  final QuizQuestionValidator validator;

  /// Loads cached-pending questions, generates new ones only for missing
  /// verses, and saves them.  Retries the model once if no valid question
  /// survives validation.  Never throws for model/network failures; it
  /// reports them through [QuizGenerationOutcome.error].
  Future<QuizGenerationOutcome> prepare(QuizScope scope) =>
      prepareScopes([scope]);

  /// Whether new model questions should be preferred over local/cloud
  /// questions for the current settings.
  Future<bool> get modelAnsweringAvailable async {
    final settings = await _loadSettings();
    return settings.modelAnsweringEnabled && settings.isConfigured;
  }

  /// Prepares several exact, possibly disjoint plan-task ranges. Each book is
  /// sent to the model separately so chapter:verse references stay unique,
  /// while cache lookup and returned questions remain restricted to the task
  /// ranges rather than their enclosing chapter interval.
  Future<QuizGenerationOutcome> prepareScopes(
    Iterable<QuizScope> requestedScopes, {
    int? maxModelCandidateCount,
  }) async {
    final scopes = {...requestedScopes}.toList(growable: false);
    if (scopes.isEmpty ||
        scopes.any(
          (scope) =>
              scope.translationId.isEmpty ||
              scope.bookId.isEmpty ||
              _invalidRange(scope),
        )) {
      return const QuizGenerationOutcome(error: '经文范围无效');
    }
    try {
      final presentUnits = <VerseUnit>[];
      final seenVerseKeys = <(String book, int chapter, int verse)>{};
      for (final scope in scopes) {
        final passage = await scripture.getPassage(
          scope.translationId,
          _passageRange(scope),
        );
        for (final unit in passage.units) {
          // Re-check locally even though the scripture repository is asked
          // for this range. This is important for bridged source units and
          // protects against a repository/cache returning a wider passage.
          if (unit.status != SourceTextStatus.present ||
              !scope.containsUnit(unit)) {
            continue;
          }
          final key = (
            unit.start.osisBookId,
            unit.start.chapter,
            unit.start.verse,
          );
          if (seenVerseKeys.add(key)) presentUnits.add(unit);
        }
      }
      if (presentUnits.isEmpty) {
        return const QuizGenerationOutcome(error: '该范围没有可用的经文');
      }
      final settings = await _loadSettings();
      final modelAvailable =
          settings.modelAnsweringEnabled && settings.isConfigured;
      final cachedVerseKeys = <(String book, int chapter, int verse)>{};
      for (final unit in presentUnits) {
        final verse = unit.start.verse;
        if (modelAvailable &&
            await repository.requeueRandomQuizQuestion(
              translationId: unit.translationId,
              bookId: unit.start.osisBookId,
              chapter: unit.start.chapter,
              verse: verse,
              source: QuizQuestionSource.model,
            )) {
          cachedVerseKeys.add((
            unit.start.osisBookId,
            unit.start.chapter,
            verse,
          ));
          continue;
        }
        if (modelAvailable) continue;
        if (await repository.hasPendingQuizQuestion(
          translationId: unit.translationId,
          bookId: unit.start.osisBookId,
          chapter: unit.start.chapter,
          verse: verse,
        )) {
          cachedVerseKeys.add((
            unit.start.osisBookId,
            unit.start.chapter,
            verse,
          ));
          continue;
        }
        if (await repository.hasQuizQuestionBankCapacity(
          translationId: unit.translationId,
          bookId: unit.start.osisBookId,
          chapter: unit.start.chapter,
          verse: verse,
        )) {
          await repository.requeueRandomQuizQuestion(
            translationId: unit.translationId,
            bookId: unit.start.osisBookId,
            chapter: unit.start.chapter,
            verse: verse,
          );
          cachedVerseKeys.add((
            unit.start.osisBookId,
            unit.start.chapter,
            verse,
          ));
          continue;
        }
      }
      if (cachedVerseKeys.length == presentUnits.length) {
        return const QuizGenerationOutcome(skippedCachedVerses: 1);
      }
      final generationVerses = <QuizGenerationVerse>[
        for (final unit in presentUnits)
          if (!cachedVerseKeys.contains((
            unit.start.osisBookId,
            unit.start.chapter,
            unit.start.verse,
          )))
            QuizGenerationVerse(
              reference: _referenceFor(unit),
              text: unit.text,
              translationId: unit.translationId,
              bookId: unit.start.osisBookId,
              chapter: unit.start.chapter,
              verse: unit.start.verse,
            ),
      ];
      // A fully cached range remains usable without any model credentials.
      // Only require configuration when one or more verses actually need a
      // new question from the remote model.
      final questions = <ValidatedQuizQuestion>[];
      final modelVerseKeys = <(String book, int chapter, int verse)>{};
      Object? modelFailure;
      if (modelAvailable) {
        final modelCandidates = _selectModelCandidates(
          generationVerses,
          maxModelCandidateCount,
        );
        for (final bookVerses in _groupByBook(modelCandidates).values) {
          try {
            var valid = _validate(
              await client.generate(settings, bookVerses),
              bookVerses,
              source: QuizQuestionSource.model,
            );
            if (valid.isEmpty) {
              valid = _validate(
                await client.generate(settings, bookVerses),
                bookVerses,
                source: QuizQuestionSource.model,
              );
            }
            if (valid.isEmpty) {
              modelFailure ??= const QuizModelException('模型返回的题目为空或未通过题目校验');
            }
            questions.addAll(valid);
          } on Object catch (error) {
            modelFailure ??= error;
          }
        }
      }
      if (questions.isNotEmpty) {
        await repository.saveQuizQuestions(questions, replaceExisting: true);
        for (final question in questions) {
          if (await repository.requeueRandomQuizQuestion(
            translationId: question.translationId,
            bookId: question.bookId,
            chapter: question.chapter,
            verse: question.verse,
            source: QuizQuestionSource.model,
          )) {
            modelVerseKeys.add((
              question.bookId,
              question.chapter,
              question.verse,
            ));
          }
        }
      }
      var fallbackCount = 0;
      var missingCount = 0;
      for (final verse in generationVerses) {
        final key = (verse.bookId, verse.chapter, verse.verse);
        if (modelVerseKeys.contains(key)) continue;
        if (await repository.requeueRandomQuizQuestion(
          translationId: verse.translationId,
          bookId: verse.bookId,
          chapter: verse.chapter,
          verse: verse.verse,
        )) {
          fallbackCount++;
        } else {
          missingCount++;
        }
      }
      if (missingCount == 0) {
        return QuizGenerationOutcome(
          generated: questions.length,
          skippedCachedVerses: fallbackCount,
          modelError: modelFailure == null
              ? null
              : _modelFailureMessage(modelFailure),
        );
      }
      if (!modelAvailable && settings.modelAnsweringEnabled) {
        return QuizGenerationOutcome(
          error: settings.missingConfigurationMessage,
        );
      }
      if (!modelAvailable && !settings.modelAnsweringEnabled) {
        return const QuizGenerationOutcome(error: '本地题库没有该范围可用题目');
      }
      final failure = modelFailure;
      if (questions.isEmpty && failure is QuizModelException) {
        return QuizGenerationOutcome(error: failure.message);
      }
      if (questions.isEmpty && modelFailure != null) {
        return QuizGenerationOutcome(error: '生成答题题目失败：$modelFailure');
      }
      if (questions.isEmpty) {
        return const QuizGenerationOutcome(error: '模型没有返回有效的答题题目，请稍后重试');
      }
      return QuizGenerationOutcome(
        generated: questions.length,
        error: '该范围仍有 $missingCount 节经文没有可用题目',
      );
    } on Object catch (error) {
      if (error is QuizModelException) {
        return QuizGenerationOutcome(error: error.message);
      }
      return QuizGenerationOutcome(error: '生成答题题目失败：$error');
    }
  }

  String _modelFailureMessage(Object error) => switch (error) {
    QuizModelException(:final message) => message,
    _ => '生成答题题目失败：$error',
  };

  List<QuizGenerationVerse> _selectModelCandidates(
    List<QuizGenerationVerse> generationVerses,
    int? maxModelCandidateCount,
  ) {
    if (maxModelCandidateCount == null ||
        maxModelCandidateCount >= generationVerses.length) {
      return generationVerses;
    }
    if (maxModelCandidateCount <= 0) return const [];
    final candidates = List<QuizGenerationVerse>.of(generationVerses)
      ..shuffle(Random());
    return candidates.take(maxModelCandidateCount).toList(growable: false);
  }

  Map<String, List<QuizGenerationVerse>> _groupByBook(
    List<QuizGenerationVerse> verses,
  ) {
    final groups = <String, List<QuizGenerationVerse>>{};
    for (final verse in verses) {
      groups.putIfAbsent(verse.bookId, () => []).add(verse);
    }
    return groups;
  }

  Future<QuizModelSettings> _loadSettings() {
    final loader = settingsLoader;
    if (loader != null) return loader();
    return repository.getQuizModelSettings();
  }

  List<ValidatedQuizQuestion> _validate(
    Object decoded,
    List<QuizGenerationVerse> verses, {
    QuizQuestionSource source = QuizQuestionSource.local,
  }) {
    try {
      return validator.validate(
        verses: verses,
        decodedJson: decoded,
        source: source,
      );
    } on FormatException {
      return const [];
    }
  }

  PassageRange _passageRange(QuizScope scope) => PassageRange(
    start: (
      canonId: CanonId.protestant66,
      osisBookId: scope.bookId,
      chapter: scope.startChapter,
      verse: scope.startVerse,
    ),
    end: (
      canonId: CanonId.protestant66,
      osisBookId: scope.bookId,
      chapter: scope.endChapter,
      verse: scope.endVerse,
    ),
  );

  bool _invalidRange(QuizScope scope) =>
      scope.startChapter <= 0 ||
      scope.startVerse <= 0 ||
      scope.endChapter <= 0 ||
      scope.endVerse <= 0 ||
      scope.startChapter > scope.endChapter ||
      (scope.startChapter == scope.endChapter &&
          scope.startVerse > scope.endVerse);

  static String _referenceFor(VerseUnit unit) {
    final start = unit.start;
    final end = unit.end;
    final range = start.chapter == end.chapter && start.verse != end.verse
        ? '${start.chapter}:${start.verse}-${end.verse}'
        : start.chapter == end.chapter
        ? '${start.chapter}:${start.verse}'
        : '${start.chapter}:${start.verse}-${end.chapter}:${end.verse}';
    return range;
  }
}
