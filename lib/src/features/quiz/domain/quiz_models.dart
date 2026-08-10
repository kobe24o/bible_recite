/// A verse sent to the model for question generation.  `reference` and
/// `text` are the only fields included in the model prompt.
final class QuizGenerationVerse {
  const QuizGenerationVerse({
    required this.reference,
    required this.text,
    required this.translationId,
    required this.bookId,
    required this.chapter,
    required this.verse,
  });

  final String reference;
  final String text;
  final String translationId;
  final String bookId;
  final int chapter;
  final int verse;
}

/// A model-produced question that passed strict validation.
///
/// `start` is the inclusive and `end` the exclusive UTF-16 code-unit
/// position inside the original verse text.  `word` is always re-sliced
/// from the verse text, never trusted verbatim from the model.
final class ValidatedQuizQuestion {
  const ValidatedQuizQuestion({
    required this.reference,
    required this.translationId,
    required this.bookId,
    required this.chapter,
    required this.verse,
    required this.start,
    required this.end,
    required this.word,
    required this.partOfSpeech,
    required this.meaning,
    required this.verseText,
  });

  final String reference;
  final String translationId;
  final String bookId;
  final int chapter;
  final int verse;
  final int start;
  final int end;
  final String word;
  final String partOfSpeech;
  final String meaning;
  final String verseText;

  int get length => end - start;
}

/// Result of importing portable question-only data. Existing questions are
/// deliberately left untouched, including their local answer history.
final class QuizBankImportResult {
  const QuizBankImportResult({this.imported = 0, this.duplicates = 0});

  final int imported;
  final int duplicates;
}
