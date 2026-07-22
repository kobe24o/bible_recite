import 'package:bible_recite/src/features/recitation/domain/exact_text_comparator.dart';
import 'package:bible_recite/src/features/recitation/domain/recitation_alignment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const comparator = ExactTextComparator();

  test('marks a matching normalized transcript green', () {
    final result = comparator.compare('神爱世人。', '神 爱 世 人', finished: false);
    expect(result.tokens.last.text, '。');
    expect(result.tokens.last.kind, RecitationTokenKind.formatting);
    expect(
      result.tokens
          .where((token) => token.kind != RecitationTokenKind.formatting)
          .map((token) => token.kind),
      everyElement(RecitationTokenKind.correct),
    );
    expect(result.accuracy, 1);
  });

  test('restores original English case spaces and punctuation', () {
    final result = comparator.compare(
      'For God, so loved.',
      'for god so loved',
      finished: false,
    );

    expect(
      result.tokens.map((token) => token.text).join(),
      'For God, so loved.',
    );
    expect(
      result.tokens
          .where((token) => token.kind == RecitationTokenKind.formatting)
          .map((token) => token.text)
          .join(),
      ' ,  .',
    );
    expect(result.accuracy, 1);
    expect(result.incorrectCount, 0);
  });

  test('marks a wrong character red', () {
    final result = comparator.compare('神爱世人', '神碍世人', finished: false);
    expect(result.tokens[1].text, '碍');
    expect(result.tokens[1].kind, RecitationTokenKind.incorrect);
    expect(result.incorrectCount, 1);
  });

  test('renders an omitted middle character as a red underscore', () {
    final result = comparator.compare('神爱世人', '神爱人', finished: false);
    final omitted = result.tokens.singleWhere(
      (token) => token.kind == RecitationTokenKind.omitted,
    );
    expect(omitted.text, '_');
    expect(result.omittedCount, 1);
  });

  test('marks adjacent out-of-order characters orange', () {
    final result = comparator.compare('神爱世人', '神世爱人', finished: false);
    expect(result.tokens[1].kind, RecitationTokenKind.reordered);
    expect(result.tokens[2].kind, RecitationTokenKind.reordered);
    expect(result.reorderedCount, 2);
  });

  test('keeps unspoken trailing text pending live and red when finished', () {
    final live = comparator.compare('神爱世人', '神爱', finished: false);
    expect(live.tokens[2].kind, RecitationTokenKind.pending);
    expect(live.tokens[3].kind, RecitationTokenKind.pending);

    final finished = comparator.compare('神爱世人', '神爱', finished: true);
    expect(finished.tokens[2].kind, RecitationTokenKind.incorrect);
    expect(finished.tokens[3].kind, RecitationTokenKind.incorrect);
    expect(finished.incorrectCount, 2);
  });
}
