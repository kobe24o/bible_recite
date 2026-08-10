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

  QuizBankQuestion get portable => QuizBankQuestion(
    reference: reference,
    translationId: translationId,
    bookId: bookId,
    chapter: chapter,
    verse: verse,
    start: start,
    end: end,
    word: word,
    partOfSpeech: partOfSpeech,
    meaning: meaning,
  );
}

/// Question data that can be stored and shared without duplicating scripture
/// text. The local scripture database remains the only source of the verse.
final class QuizBankQuestion {
  const QuizBankQuestion({
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

  int get length => end - start;
}

/// Explanations must not repeat the answer itself. Apart from reducing the
/// portable-bank size, this ensures the final hint never leaks the word.
String compactQuizMeaning(String word, String meaning) {
  var compact = meaning.trim();
  for (final prefix in ['$word：', '$word:', '【$word】：', '【$word】:']) {
    if (compact.startsWith(prefix)) {
      compact = compact.substring(prefix.length).trim();
      break;
    }
  }
  return compact;
}

/// Result of importing portable question-only data. Existing questions are
/// deliberately left untouched, including their local answer history.
final class QuizBankImportResult {
  const QuizBankImportResult({this.imported = 0, this.duplicates = 0});

  final int imported;
  final int duplicates;
}
