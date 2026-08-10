import '../../scripture/domain/scripture_models.dart';
import '../../scripture/domain/scripture_repository.dart';
import '../domain/quiz_models.dart';

/// Validates portable question metadata against the scripture installed on
/// this device. Imported text is never used as a source of scripture.
final class QuizBankLocalValidator {
  QuizBankLocalValidator(this._scripture);

  final ScriptureRepository _scripture;

  Future<QuizBankLocalValidation> validate(
    Iterable<QuizBankQuestion> questions,
  ) async {
    final accepted = <ValidatedQuizQuestion>[];
    var rejected = 0;
    final byChapter =
        <
          (String translation, String book, int chapter),
          List<QuizBankQuestion>
        >{};
    for (final question in questions) {
      byChapter
          .putIfAbsent((
            question.translationId,
            question.bookId,
            question.chapter,
          ), () => <QuizBankQuestion>[])
          .add(question);
    }
    for (final entry in byChapter.entries) {
      final (translation, book, chapter) = entry.key;
      List<VerseUnit> units;
      try {
        units = await _scripture.getChapter(translation, book, chapter);
      } catch (_) {
        rejected += entry.value.length;
        continue;
      }
      final byVerse = {
        for (final unit in units)
          if (unit.status == SourceTextStatus.present &&
              unit.start.chapter == chapter &&
              unit.start.verse == unit.end.verse)
            unit.start.verse: unit,
      };
      for (final question in entry.value) {
        final unit = byVerse[question.verse];
        if (unit == null ||
            question.end > unit.text.length ||
            unit.text.substring(question.start, question.end) !=
                question.word) {
          rejected++;
          continue;
        }
        accepted.add(
          ValidatedQuizQuestion(
            reference: question.reference,
            translationId: question.translationId,
            bookId: question.bookId,
            chapter: question.chapter,
            verse: question.verse,
            start: question.start,
            end: question.end,
            word: question.word,
            partOfSpeech: question.partOfSpeech,
            meaning: compactQuizMeaning(question.word, question.meaning),
            verseText: unit.text,
          ),
        );
      }
    }
    return QuizBankLocalValidation(accepted: accepted, rejected: rejected);
  }
}

final class QuizBankLocalValidation {
  const QuizBankLocalValidation({
    required this.accepted,
    required this.rejected,
  });

  final List<ValidatedQuizQuestion> accepted;
  final int rejected;
}
