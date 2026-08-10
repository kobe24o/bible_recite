import 'quiz_models.dart';

/// Deterministically combines banks. The first file wins when identical
/// scripture positions have different metadata, keeping the operation safe
/// and repeatable for shared collections.
final class QuizBankMerge {
  static List<QuizBankQuestion> merge(
    Iterable<Iterable<QuizBankQuestion>> banks,
  ) {
    final unique = <String, QuizBankQuestion>{};
    for (final bank in banks) {
      for (final question in bank) {
        unique.putIfAbsent(_key(question), () => question);
      }
    }
    final merged = unique.values.toList(growable: false);
    merged.sort(_compare);
    return merged;
  }

  static String _key(QuizBankQuestion question) =>
      '${question.translationId}\u0000${question.bookId}\u0000'
      '${question.chapter}\u0000${question.verse}\u0000'
      '${question.start}\u0000${question.end}';

  static int _compare(QuizBankQuestion left, QuizBankQuestion right) {
    final translation = left.translationId.compareTo(right.translationId);
    if (translation != 0) return translation;
    final book = left.bookId.compareTo(right.bookId);
    if (book != 0) return book;
    final chapter = left.chapter.compareTo(right.chapter);
    if (chapter != 0) return chapter;
    final verse = left.verse.compareTo(right.verse);
    if (verse != 0) return verse;
    return left.start.compareTo(right.start);
  }
}
