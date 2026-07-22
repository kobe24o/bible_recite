import 'recitation_alignment.dart';
import 'exact_text_comparator.dart';

abstract interface class RecitationComparator {
  const RecitationComparator();

  RecitationAlignment compare(
    String target,
    String transcript, {
    required bool finished,
  });
}

/// Chooses phonetic scoring only for a completed Mandarin recitation.
///
/// Live recognition deliberately remains exact-text-only: partial ASR output
/// must not be presented as a confirmed homophone correction.
RecitationComparator comparatorForTranslation(
  String translationId, {
  required bool finished,
  required RecitationComparator mandarin,
}) {
  if (finished && _isMandarinChineseTranslation(translationId)) {
    return mandarin;
  }
  return const ExactTextComparator();
}

bool _isMandarinChineseTranslation(String translationId) =>
    translationId == 'cmn-cu89s' || translationId == 'cmn-cu89t';
