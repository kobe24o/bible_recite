/// A saved, already-answered quiz question.
final class StoredQuizQuestion {
  const StoredQuizQuestion({
    required this.id,
    required this.translationId,
    required this.bookId,
    required this.chapter,
    required this.verse,
    required this.start,
    required this.end,
    required this.word,
    required this.partOfSpeech,
    required this.meaning,
    required this.reference,
    required this.verseText,
    required this.answered,
    required this.correct,
    required this.answeredAt,
  });

  final int id;
  final String translationId;
  final String bookId;
  final int chapter;
  final int verse;
  final int start;
  final int end;
  final String word;
  final String partOfSpeech;
  final String meaning;
  final String reference;
  final String verseText;
  final bool answered;
  final bool? correct;
  final DateTime? answeredAt;

  int get length => end - start;
}

/// A question the user has not answered yet.
final class PendingQuizQuestion extends StoredQuizQuestion {
  const PendingQuizQuestion({
    required super.id,
    required super.translationId,
    required super.bookId,
    required super.chapter,
    required super.verse,
    required super.start,
    required super.end,
    required super.word,
    required super.partOfSpeech,
    required super.meaning,
    required super.reference,
    required super.verseText,
  }) : super(answered: false, correct: null, answeredAt: null);
}

/// Result of a completed attempt.
final class QuizCompletion {
  const QuizCompletion({
    required this.totalAnswered,
    required this.totalCorrect,
    required this.currentCorrectStreak,
    required this.maxCorrectStreak,
  });

  final int totalAnswered;
  final int totalCorrect;
  final int currentCorrectStreak;
  final int maxCorrectStreak;

  double get accuracy => totalAnswered == 0 ? 0 : totalCorrect / totalAnswered;
}

/// Aggregated quiz statistics independent of recitation statistics.
final class QuizSummary {
  const QuizSummary({
    required this.totalAnswered,
    required this.totalCorrect,
    required this.currentCorrectStreak,
    required this.maxCorrectStreak,
  });

  final int totalAnswered;
  final int totalCorrect;
  final int currentCorrectStreak;
  final int maxCorrectStreak;

  double get accuracy => totalAnswered == 0 ? 0 : totalCorrect / totalAnswered;
  bool get isEmpty => totalAnswered == 0;
}

/// Quiz aggregate for one scope (translation, book, chapter, verse).
final class QuizRangeMetric {
  const QuizRangeMetric({required this.answered, required this.correct});

  final int answered;
  final int correct;

  bool get isEmpty => answered == 0;
  double get accuracy => answered == 0 ? 0 : correct / answered;
}

/// Quiz aggregate for one concrete verse, suitable for the recitation map.
final class QuizVerseMetric extends QuizRangeMetric {
  const QuizVerseMetric({
    required this.translationId,
    required this.bookId,
    required this.chapter,
    required this.verse,
    required super.answered,
    required super.correct,
  });

  final String translationId;
  final String bookId;
  final int chapter;
  final int verse;
}
