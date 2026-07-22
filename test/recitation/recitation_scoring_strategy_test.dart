import 'package:bible_recite/src/features/recitation/domain/bible_pronunciation_lexicon.dart';
import 'package:bible_recite/src/features/recitation/domain/exact_text_comparator.dart';
import 'package:bible_recite/src/features/recitation/domain/mandarin_phonetic_comparator.dart';
import 'package:bible_recite/src/features/recitation/domain/recitation_comparator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final mandarin = MandarinPhoneticComparator(
    lexicon: BiblePronunciationLexicon.fromJson('{}'),
  );

  test(
    'uses phonetic correction only after Chinese recitation is finished',
    () {
      final live = comparatorForTranslation(
        'cmn-cu89s',
        finished: false,
        mandarin: mandarin,
      ).compare('喜乐', '洗了', finished: false);
      final completed = comparatorForTranslation(
        'cmn-cu89s',
        finished: true,
        mandarin: mandarin,
      ).compare('喜乐', '洗了', finished: true);

      expect(live.phoneticCorrectCount, 0);
      expect(completed.phoneticCorrectCount, 2);
    },
  );

  test('keeps non-Chinese translations exact after completion', () {
    final comparator = comparatorForTranslation(
      'eng-kjv',
      finished: true,
      mandarin: mandarin,
    );

    expect(comparator, isA<ExactTextComparator>());
  });
}
