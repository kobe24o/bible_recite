import 'scripture_models.dart';

abstract interface class ScriptureRepository {
  Future<List<TranslationInfo>> listTranslations();

  Future<TranslationInfo> getTranslation(String id);

  Future<List<BibleBook>> listBooks(String translationId, CanonId canonId);

  Future<List<VerseUnit>> getChapter(
    String translationId,
    String osisBookId,
    int chapter,
  );

  Future<Passage> getPassage(String translationId, PassageRange range);

  Future<SelectedPassage> getSelection(
    String translationId,
    PassageSelection selection,
  );

  Future<ParallelPassage> resolveParallelPassage(
    LocatedPassageRange sourceRange,
    String targetTranslationId,
  );
}
