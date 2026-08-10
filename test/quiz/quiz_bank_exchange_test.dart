import 'package:bible_recite/src/features/quiz/domain/quiz_bank_exchange.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const question = ValidatedQuizQuestion(
    reference: '3:16',
    translationId: 'cmn-cu89s',
    bookId: 'JHN',
    chapter: 3,
    verse: 16,
    start: 2,
    end: 4,
    word: '世人',
    partOfSpeech: '名词',
    meaning: '世上的人',
    verseText: '神爱世人',
  );

  test('round-trips shareable questions without answer history', () {
    final decoded = QuizBankExchange.decode(
      QuizBankExchange.encode([question]),
    );

    expect(decoded, hasLength(1));
    expect(decoded.single.word, '世人');
    expect(decoded.single.start, 2);
    expect(decoded.single.end, 4);
  });

  test('rejects malformed shared questions', () {
    expect(
      () => QuizBankExchange.decode('''
        {"format":"bible-recite-quiz-bank","version":1,"questions":[
          {"translationId":"cmn-cu89s","bookId":"JHN","chapter":3,
           "verse":16,"start":2,"end":7,"word":"世人",
           "partOfSpeech":"名词","meaning":"世上的人","reference":"3:16",
           "verseText":"神爱世人"}
        ]}
      '''),
      throwsFormatException,
    );
  });
}
