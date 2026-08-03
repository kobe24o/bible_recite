import 'scripture_models.dart';
import 'scripture_repository.dart';

extension ExactScriptureSearch on ScriptureRepository {
  static final Map<String, Future<List<VerseUnit>>> _indexByTranslation = {};

  /// Offline, translation-scoped exact substring search. Results are capped so
  /// a short query cannot overwhelm the reading experience.
  Future<List<VerseUnit>> searchExactVerses(
    String translationId,
    String query, {
    int limit = 100,
  }) async {
    final needle = query.trim();
    if (needle.isEmpty) return const [];
    final index = await _indexByTranslation.putIfAbsent(
      translationId,
      () => _buildExactIndex(translationId),
    );
    return [for (final unit in index) if (unit.text.contains(needle)) unit]
        .take(limit)
        .toList(growable: false);
  }

  Future<List<VerseUnit>> _buildExactIndex(String translationId) async {
    final units = <VerseUnit>[];
    final books = await listBooks(translationId, CanonId.protestant66);
    for (final book in books) {
      for (var chapter = 1; chapter <= book.chapterCount; chapter++) {
        units.addAll(await getChapter(translationId, book.osisId, chapter));
      }
    }
    return List.unmodifiable(units);
  }
}
