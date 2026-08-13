import '../../plans/data/sqlite_plan_repository.dart';
import '../../scripture/domain/scripture_models.dart';
import '../../scripture/domain/scripture_repository.dart';
import '../data/quiz_model_client.dart';
import '../domain/quiz_model_settings.dart';
import '../domain/quiz_models.dart';
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

  /// Prepares several exact, possibly disjoint plan-task ranges. Each book is
  /// sent to the model separately so chapter:verse references stay unique,
  /// while cache lookup and returned questions remain restricted to the task
  /// ranges rather than their enclosing chapter interval.
  Future<QuizGenerationOutcome> prepareScopes(
    Iterable<QuizScope> requestedScopes,
  ) async {
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
      final cachedVerseKeys = <(String book, int chapter, int verse)>{};
      for (final unit in presentUnits) {
        final verse = unit.start.verse;
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
      final settings = await _loadSettings();
      if (!settings.modelAnsweringEnabled) {
        return const QuizGenerationOutcome(error: '本地题库没有该范围可用题目');
      }
      if (!settings.isConfigured) {
        return QuizGenerationOutcome(
          error: settings.missingConfigurationMessage,
        );
      }
      final questions = <ValidatedQuizQuestion>[];
      for (final bookVerses in _groupByBook(generationVerses).values) {
        var valid = _validate(
          await client.generate(settings, bookVerses),
          bookVerses,
        );
        if (valid.isEmpty) {
          valid = _validate(
            await client.generate(settings, bookVerses),
            bookVerses,
          );
        }
        questions.addAll(valid);
      }
      if (questions.isEmpty) {
        return const QuizGenerationOutcome(error: '模型没有返回有效的答题题目，请稍后重试');
      }
      await repository.saveQuizQuestions(questions);
      return QuizGenerationOutcome(generated: questions.length);
    } on QuizModelException catch (error) {
      return QuizGenerationOutcome(error: error.message);
    } on Object catch (error) {
      return QuizGenerationOutcome(error: '生成答题题目失败：$error');
    }
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
    List<QuizGenerationVerse> verses,
  ) {
    try {
      return validator.validate(verses: verses, decodedJson: decoded);
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
