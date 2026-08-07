import 'quiz_models.dart';

/// Validates untrusted model JSON output against the original verses.
///
/// Only verified questions survive: every `start`/`end` must slice a
/// non-empty, non-punctuation, non-function-word span whose length agrees
/// with the reported `length`, and duplicate offsets inside the same verse
/// are rejected.  All comparison uses Dart's UTF-16 code-unit indexing so
/// that `end - start == length` holds for every index the model returns.
final class QuizQuestionValidator {
  const QuizQuestionValidator();

  /// Casts already-decoded JSON (`jsonDecode` result) into validated
  /// questions.  Throws [FormatException] for a top-level shape that can
  /// never be a valid model response; silently drops invalid items.
  List<ValidatedQuizQuestion> validate({
    required List<QuizGenerationVerse> verses,
    required Object decodedJson,
  }) {
    final items = switch (decodedJson) {
      List<Object?> list => list,
      _ => throw const FormatException('模型输出必须是 JSON 数组'),
    };
    final byReference = <String, QuizGenerationVerse>{
      for (final verse in verses) verse.reference: verse,
    };
    final seenOffsets = <String, Set<int>>{};
    final results = <ValidatedQuizQuestion>[];
    for (final item in items) {
      if (item is! Map<String, Object?>) continue;
      final reference = item['reference'];
      final start = item['start'];
      final end = item['end'];
      final length = item['length'];
      final partOfSpeech = item['partOfSpeech'];
      final meaning = item['meaning'];
      if (reference is! String ||
          start is! int ||
          end is! int ||
          length is! int ||
          partOfSpeech is! String ||
          meaning is! String) {
        continue;
      }
      final verse = byReference[reference];
      if (verse == null ||
          start < 0 ||
          end <= start ||
          end > verse.text.length ||
          end - start != length) {
        continue;
      }
      final word = verse.text.substring(start, end);
      if (_isFunctionWord(word) ||
          partOfSpeech.trim().isEmpty ||
          meaning.trim().isEmpty) {
        continue;
      }
      final offsets = seenOffsets.putIfAbsent(reference, () => <int>{});
      final key = start << 16 | (end & 0xffff);
      if (!offsets.add(key)) continue;
      results.add(
        ValidatedQuizQuestion(
          reference: reference,
          translationId: verse.translationId,
          bookId: verse.bookId,
          chapter: verse.chapter,
          verse: verse.verse,
          start: start,
          end: end,
          word: word,
          partOfSpeech: partOfSpeech.trim(),
          meaning: meaning.trim(),
        ),
      );
    }
    return results;
  }

  static const _functionWords = <String>{
    '的',
    '了',
    '着',
    '过',
    '吗',
    '呢',
    '啊',
    '呀',
    '和',
    '与',
    '及',
    '而',
    '但',
    '且',
    '或',
    '在',
    '把',
    '被',
    '给',
    '从',
    '向',
    '对',
    '以',
    '于',
    '是',
    '有',
    '就',
    '都',
    '也',
    '又',
    '很',
    '更',
    '还',
    '不',
    '没',
    '要',
    '会',
    '能',
    '之',
    '其',
    '这',
    '那',
    '等',
    '并',
    '则',
    '却',
    '才',
    '再',
    '便',
    '因',
    '为',
    '由',
    '到',
    '上',
    '下',
    '里',
    '中',
    '乃',
  };

  static bool _isFunctionWord(String word) {
    final trimmed = word.trim();
    if (trimmed.isEmpty) return true;
    if (RegExp(r'^[\p{P}\p{S}\s]+$', unicode: true).hasMatch(trimmed)) {
      return true;
    }
    return _functionWords.contains(trimmed);
  }
}
