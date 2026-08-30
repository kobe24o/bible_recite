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

  /// Whether one exact verse belongs to this scope.  Keep this check close to
  /// the scope model so generation, cached-question lookup and UI entry flows
  /// all apply exactly the same range semantics.
  bool containsVerse({
    required String translationId,
    required String bookId,
    required int chapter,
    required int verse,
  }) {
    if (translationId != this.translationId || bookId != this.bookId) {
      return false;
    }
    final afterStart =
        chapter > startChapter ||
        (chapter == startChapter && verse >= startVerse);
    final beforeEnd =
        chapter < endChapter || (chapter == endChapter && verse <= endVerse);
    return afterStart && beforeEnd;
  }

  /// A generation unit is usable only when it is completely contained in the
  /// requested passage.  Some source editions have a unit spanning multiple
  /// verses; retaining a boundary-spanning unit would show or generate a
  /// question for text outside the selected plan range.
  bool containsUnit(VerseUnit unit) =>
      containsVerse(
        translationId: unit.translationId,
        bookId: unit.start.osisBookId,
        chapter: unit.start.chapter,
        verse: unit.start.verse,
      ) &&
      containsVerse(
        translationId: unit.translationId,
        bookId: unit.end.osisBookId,
        chapter: unit.end.chapter,
        verse: unit.end.verse,
      );

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
    this.modelError,
  });

  final int generated;
  final int skippedCachedVerses;
  final String? error;

  /// A model request can fail while a local/cloud question still makes the
  /// range usable. Keep that diagnostic separate from [error], which means
  /// the preparation itself cannot continue.
  final String? modelError;

  bool get success => error == null;
}
