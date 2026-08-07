import '../../scripture/domain/scripture_models.dart';

/// Identifies which verses a quiz generation request covers.  Each
/// generation scope keeps its exact verse boundaries; it is never expanded
/// to a whole chapter automatically.
final class QuizScope {
  const QuizScope({
    required this.translationId,
    required this.bookId,
    required this.startChapter,
    required this.startVerse,
    required this.endChapter,
    required this.endVerse,
  });

  final String translationId;
  final String bookId;
  final int startChapter;
  final int startVerse;
  final int endChapter;
  final int endVerse;

  factory QuizScope.fromPassageRange(
    String translationId,
    PassageRange range,
  ) => QuizScope(
    translationId: translationId,
    bookId: range.start.osisBookId,
    startChapter: range.start.chapter,
    startVerse: range.start.verse,
    endChapter: range.end.chapter,
    endVerse: range.end.verse,
  );

  /// The same scope after expanding to a full chapter.  Used only where the
  /// product explicitly asks for the whole currently open chapter.
  factory QuizScope.forChapter({
    required String translationId,
    required String bookId,
    required int chapter,
    required int verseCount,
  }) => QuizScope(
    translationId: translationId,
    bookId: bookId,
    startChapter: chapter,
    startVerse: 1,
    endChapter: chapter,
    endVerse: verseCount,
  );

  bool get isSingleChapter => startChapter == endChapter;

  @override
  bool operator ==(Object other) =>
      other is QuizScope &&
      other.translationId == translationId &&
      other.bookId == bookId &&
      other.startChapter == startChapter &&
      other.startVerse == startVerse &&
      other.endChapter == endChapter &&
      other.endVerse == endVerse;

  @override
  int get hashCode => Object.hash(
    translationId,
    bookId,
    startChapter,
    startVerse,
    endChapter,
    endVerse,
  );
}

/// What the caller (entry flow) needs from the generation service.
final class QuizGenerationOutcome {
  const QuizGenerationOutcome({
    this.generated = 0,
    this.skippedCachedVerses = 0,
    this.error,
  });

  final int generated;
  final int skippedCachedVerses;
  final String? error;

  bool get success => error == null;
}
