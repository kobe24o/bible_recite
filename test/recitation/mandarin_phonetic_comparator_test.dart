import 'package:bible_recite/src/features/recitation/domain/bible_pronunciation_lexicon.dart';
import 'package:bible_recite/src/features/recitation/domain/mandarin_phonetic_comparator.dart';
import 'package:bible_recite/src/features/recitation/domain/recitation_alignment.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MandarinPhoneticComparator comparator;

  setUpAll(() async {
    final lexicon = await BiblePronunciationLexicon.load(rootBundle);
    comparator = MandarinPhoneticComparator(lexicon: lexicon);
  });

  test('corrects toneless homophones to target text', () {
    final result = comparator.compare('神爱世人', '神矮是人', finished: true);

    expect(result.tokens.map((token) => token.text).join(), '神爱世人');
    expect(result.exactCorrectCount, 2);
    expect(result.phoneticCorrectCount, 2);
    expect(result.correctCount, 4);
    expect(result.accuracy, 1);
    expect(
      () => result.tokens.add(
        const RecitationToken('x', RecitationTokenKind.incorrect),
      ),
      throwsUnsupportedError,
    );
  });

  test('ignores tone differences', () {
    final result = comparator.compare('日期', '日骑', finished: true);

    expect(result.exactCorrectCount, 1);
    expect(result.phoneticCorrectCount, 1);
    expect(result.accuracy, 1);
  });

  test('does not correct homophones before the recitation finishes', () {
    final result = comparator.compare('神爱', '神矮', finished: false);

    expect(result.tokens.map((token) => token.text).join(), '神矮');
    expect(result.tokens.last.kind, RecitationTokenKind.incorrect);
    expect(result.phoneticCorrectCount, 0);
  });

  test('keeps genuine pronunciation errors as ASR text', () {
    final result = comparator.compare('神爱', '声爱', finished: true);

    expect(result.tokens.first.text, '声');
    expect(result.tokens.first.kind, RecitationTokenKind.incorrect);
    expect(result.exactCorrectCount, 1);
    expect(result.phoneticCorrectCount, 0);
  });

  test('does not match an arbitrary polyphonic candidate', () {
    final result = comparator.compare('银行', '隐形', finished: true);

    expect(result.phoneticCorrectCount, 1);
    expect(result.incorrectCount, 1);
    expect(result.tokens.last.text, '形');
    expect(result.tokens.last.kind, RecitationTokenKind.incorrect);
  });

  test('uses lexicon pronunciations for traditional Bible phrases', () {
    final result = comparator.compare('耶和華', '爷和花', finished: true);

    expect(result.tokens.map((token) => token.text).join(), '耶和華');
    expect(result.exactCorrectCount, 1);
    expect(result.phoneticCorrectCount, 2);
  });

  test(
    'prefers an exact alignment over an equally cheap phonetic alignment',
    () {
      final exactFirstComparator = MandarinPhoneticComparator(
        lexicon: BiblePronunciationLexicon.fromJson(
          '{"长张": ["zhang", "zhang"]}',
        ),
      );

      final result = exactFirstComparator.compare('长张', '张', finished: true);

      expect(result.tokens.map((token) => token.text), ['_', '张']);
      expect(result.tokens.map((token) => token.kind), [
        RecitationTokenKind.omitted,
        RecitationTokenKind.correct,
      ]);
      expect(result.exactCorrectCount, 1);
      expect(result.phoneticCorrectCount, 0);
    },
  );

  test('restores punctuation while correcting phonetic matches', () {
    final result = comparator.compare('神爱，世人。', '神矮是人', finished: true);

    expect(result.tokens.map((token) => token.text).join(), '神爱，世人。');
    expect(
      result.tokens.where(
        (token) => token.kind == RecitationTokenKind.formatting,
      ),
      hasLength(2),
    );
  });

  test(
    'preserves omissions, extra words, repeated syllables, and transposition',
    () {
      final omitted = comparator.compare('神爱世人', '神爱人', finished: true);
      expect(omitted.omittedCount, 1);
      expect(omitted.tokens[2].text, '_');

      final extra = comparator.compare('神爱', '主神爱', finished: true);
      expect(extra.tokens.first.text, '主');
      expect(extra.tokens.first.kind, RecitationTokenKind.incorrect);

      final repeated = comparator.compare('诗诗', '师时', finished: true);
      expect(repeated.phoneticCorrectCount, 2);

      final transposed = comparator.compare('神爱世人', '神世爱人', finished: true);
      expect(transposed.reorderedCount, 2);
      expect(transposed.exactCorrectCount, 2);
    },
  );

  test('falls back to exact-only comparison when pinyin conversion fails', () {
    final result = comparator.compare('𠀀', '𠀁', finished: true);

    expect(result.tokens.single.text, '𠀁');
    expect(result.tokens.single.kind, RecitationTokenKind.incorrect);
    expect(result.phoneticCorrectCount, 0);
  });

  test('keeps an empty target at zero accuracy', () {
    final result = comparator.compare('', '神', finished: true);

    expect(result.targetLength, 0);
    expect(result.correctCount, 0);
    expect(result.incorrectCount, 1);
    expect(result.accuracy, 0);
  });
}
