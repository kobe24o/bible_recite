import 'package:bible_recite/src/features/quiz/domain/quiz_bank_merge.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_models.dart';
import 'package:flutter_test/flutter_test.dart';

ValidatedQuizQuestion _question({int start = 2, String meaning = '世上的人'}) =>
    ValidatedQuizQuestion(
      reference: '3:16',
      translationId: 'cmn-cu89s',
      bookId: 'JHN',
      chapter: 3,
      verse: 16,
      start: start,
      end: start + 2,
      word: start == 2 ? '世人' : '神爱',
      partOfSpeech: '名词',
      meaning: meaning,
      verseText: '神爱世人',
    );

void main() {
  test('deduplicates exported banks by scripture position and keeps first', () {
    final merged = QuizBankMerge.merge([
      [_question(meaning: 'first'), _question(start: 0)],
      [_question(meaning: 'second')],
    ]);

    expect(merged, hasLength(2));
    expect(merged.firstWhere((item) => item.start == 2).meaning, 'first');
  });
}
