import 'scripture_models.dart';
import 'scripture_repository.dart';

extension ExactScriptureSearch on ScriptureRepository {
  /// Offline, translation-scoped exact substring search. Results are capped so
  /// a short query cannot overwhelm the reading experience.
  Future<List<VerseUnit>> searchExactVerses(
    String translationId,
    String query, {
    int limit = 100,
  }) async {
    final needle = query.trim();
    if (needle.isEmpty) return const [];
    final matches = <VerseUnit>[];
    final books = await listBooks(translationId, CanonId.protestant66);
    for (final book in books) {
      for (var chapter = 1; chapter <= book.chapterCount; chapter++) {
        final units = await getChapter(translationId, book.osisId, chapter);
        for (final unit in units) {
          if (unit.text.contains(needle)) matches.add(unit);
          if (matches.length >= limit) return matches;
        }
      }
    }
    return matches;
  }
}
