final class NewRecitationResult {
  const NewRecitationResult({
    required this.translationId,
    required this.bookId,
    required this.chapter,
    required this.startVerse,
    required this.endVerse,
    this.chapterVerseCount = 0,
    required this.mode,
    required this.durationSeconds,
    required this.correctCount,
    this.phoneticCorrectCount = 0,
    required this.incorrectCount,
    required this.omittedCount,
    required this.reorderedCount,
    required this.accuracy,
    required this.completedAt,
  });

  final String translationId;
  final String bookId;
  final int chapter;
  final int startVerse;
  final int endVerse;
  final int chapterVerseCount;
  final String mode;
  final int durationSeconds;
  final int correctCount;
  final int phoneticCorrectCount;
  final int incorrectCount;
  final int omittedCount;
  final int reorderedCount;
  final double accuracy;
  final DateTime completedAt;
}

final class RecitationResult extends NewRecitationResult {
  const RecitationResult({
    required this.id,
    required super.translationId,
    required super.bookId,
    required super.chapter,
    required super.startVerse,
    required super.endVerse,
    super.chapterVerseCount,
    required super.mode,
    required super.durationSeconds,
    required super.correctCount,
    super.phoneticCorrectCount,
    required super.incorrectCount,
    required super.omittedCount,
    required super.reorderedCount,
    required super.accuracy,
    required super.completedAt,
  });
  final int id;
}

final class RecitationSummary {
  const RecitationSummary({
    required this.totalSessions,
    required this.totalVerses,
    required this.totalSeconds,
    required this.averageAccuracy,
  });
  final int totalSessions;
  final int totalVerses;
  final int totalSeconds;
  final double averageAccuracy;
}
