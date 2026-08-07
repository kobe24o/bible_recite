import 'package:bible_recite/src/features/quiz/domain/quiz_models.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_question_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const validator = QuizQuestionValidator();

  QuizGenerationVerse verse({
    String reference = '约翰福音 3:16',
    String text = '神爱世人',
    int chapter = 3,
    int verseNumber = 16,
  }) => QuizGenerationVerse(
    reference: reference,
    text: text,
    translationId: 'cmn-cu89s',
    bookId: 'JHN',
    chapter: chapter,
    verse: verseNumber,
  );

  test('keeps an exact meaningful word', () {
    final json = [
      {
        'reference': '约翰福音 3:16',
        'start': 2,
        'end': 4,
        'length': 2,
        'partOfSpeech': '名词',
        'meaning': '世上的人',
      },
    ];
    final result = validator.validate(
      verses: [verse()],
      decodedJson: json,
    );
    expect(result, hasLength(1));
    expect(result.single.word, '世人');
    expect(result.single.start, 2);
    expect(result.single.end, 4);
    expect(result.single.length, 2);
    expect(result.single.translationId, 'cmn-cu89s');
    expect(result.single.verse, 16);
  });

  test('rejects wrong reference, index, length and shape', () {
    final good = verse();
    final json = [
      {'reference': '马太福音 1:1', 'start': 0, 'end': 2, 'length': 2, 'partOfSpeech': '名词', 'meaning': 'x'},
      {'reference': '约翰福音 3:16', 'start': -1, 'end': 2, 'length': 2, 'partOfSpeech': '名词', 'meaning': 'x'},
      {'reference': '约翰福音 3:16', 'start': 3, 'end': 2, 'length': 1, 'partOfSpeech': '名词', 'meaning': 'x'},
      {'reference': '约翰福音 3:16', 'start': 2, 'end': 4, 'length': 3, 'partOfSpeech': '名词', 'meaning': 'x'},
      {'reference': '约翰福音 3:16', 'start': 3, 'end': 5, 'length': 2, 'partOfSpeech': '名词', 'meaning': 'x'},
      {'reference': '约翰福音 3:16', 'start': 2, 'end': 4, 'length': 2, 'partOfSpeech': '', 'meaning': 'x'},
      {'reference': '约翰福音 3:16', 'start': 2, 'end': 4, 'length': 2, 'partOfSpeech': '名词', 'meaning': '  '},
      {'reference': 16, 'start': 2, 'end': 4, 'length': 2, 'partOfSpeech': '名词', 'meaning': 'x'},
    ];
    expect(validator.validate(verses: [good], decodedJson: json), isEmpty);
  });

  test('rejects function words and punctuation-only values', () {
    final verseWithFunctionWord = verse(
      reference: '约翰福音 3:16',
      text: '我的神爱世人，',
    );
    final json = [
      {
        'reference': '约翰福音 3:16',
        'start': 1,
        'end': 2,
        'length': 1,
        'partOfSpeech': '助词',
        'meaning': 'x',
      },
      {
        'reference': '约翰福音 3:16',
        'start': 6,
        'end': 7,
        'length': 1,
        'partOfSpeech': '标点',
        'meaning': 'x',
      },
    ];
    // 我的神爱世人，: 我(0)的(1)神(2)爱(3)世(4)人(5)，(6)
    expect(
      validator.validate(
        verses: [verseWithFunctionWord],
        decodedJson: json,
      ),
      isEmpty,
    );
  });

  test('rejects duplicate offsets inside the same verse', () {
    final json = [
      {'reference': '约翰福音 3:16', 'start': 2, 'end': 4, 'length': 2, 'partOfSpeech': '名词', 'meaning': '世上的人'},
      {'reference': '约翰福音 3:16', 'start': 2, 'end': 4, 'length': 2, 'partOfSpeech': '名词', 'meaning': '另一个解释'},
    ];
    final result = validator.validate(verses: [verse()], decodedJson: json);
    expect(result, hasLength(1));
  });

  test('throws for a top-level shape that is not a list', () {
    expect(
      () => validator.validate(
        verses: [verse()],
        decodedJson: {'items': []},
      ),
      throwsFormatException,
    );
  });

  test('allows the same offset in different verses', () {
    final json = [
      {'reference': '约翰福音 3:16', 'start': 2, 'end': 4, 'length': 2, 'partOfSpeech': '名词', 'meaning': '世上的人'},
      {'reference': '约翰福音 3:17', 'start': 2, 'end': 4, 'length': 2, 'partOfSpeech': '名词', 'meaning': '另一处'},
    ];
    final result = validator.validate(
      verses: [
        verse(),
        verse(
          reference: '约翰福音 3:17',
          text: '神爱世人',
          verseNumber: 17,
        ),
      ],
      decodedJson: json,
    );
    expect(result, hasLength(2));
  });
}
