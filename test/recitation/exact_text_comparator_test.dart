import 'package:bible_recite/src/features/recitation/domain/exact_text_comparator.dart';
import 'package:bible_recite/src/features/recitation/domain/recitation_alignment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const comparator = ExactTextComparator();

  List<(String, RecitationTokenKind)> tokens(
    String target,
    String transcript, {
    bool finished = false,
  }) => comparator
      .compare(target, transcript, finished: finished)
      .tokens
      .map((token) => (token.text, token.kind))
      .toList(growable: false);

  test('restores target punctuation as formatting tokens', () {
    expect(tokens('神爱，世人。', '神爱世人', finished: true), [
      ('神', RecitationTokenKind.correct),
      ('爱', RecitationTokenKind.correct),
      ('，', RecitationTokenKind.formatting),
      ('世', RecitationTokenKind.correct),
      ('人', RecitationTokenKind.correct),
      ('。', RecitationTokenKind.formatting),
    ]);
  });

  test('marks a wrong character as incorrect', () {
    expect(tokens('神爱世人', '神恨世人', finished: true), [
      ('神', RecitationTokenKind.correct),
      ('恨', RecitationTokenKind.incorrect),
      ('世', RecitationTokenKind.correct),
      ('人', RecitationTokenKind.correct),
    ]);
  });

  test('renders a middle omission as an underscore', () {
    expect(tokens('神爱世人', '神爱人', finished: true), [
      ('神', RecitationTokenKind.correct),
      ('爱', RecitationTokenKind.correct),
      ('_', RecitationTokenKind.omitted),
      ('人', RecitationTokenKind.correct),
    ]);
  });

  test('marks an adjacent transposition as reordered', () {
    expect(tokens('神爱世人', '神世爱人', finished: true), [
      ('神', RecitationTokenKind.correct),
      ('世', RecitationTokenKind.reordered),
      ('爱', RecitationTokenKind.reordered),
      ('人', RecitationTokenKind.correct),
    ]);
  });

  test('keeps trailing target text pending until the recognition finishes', () {
    expect(tokens('神爱世人', '神爱'), [
      ('神', RecitationTokenKind.correct),
      ('爱', RecitationTokenKind.correct),
      ('世', RecitationTokenKind.pending),
      ('人', RecitationTokenKind.pending),
    ]);
    expect(tokens('神爱世人', '神爱', finished: true), [
      ('神', RecitationTokenKind.correct),
      ('爱', RecitationTokenKind.correct),
      ('世', RecitationTokenKind.incorrect),
      ('人', RecitationTokenKind.incorrect),
    ]);
  });

  test('retains extra leading and trailing characters as incorrect tokens', () {
    expect(tokens('神爱', '主神爱人', finished: true), [
      ('主', RecitationTokenKind.incorrect),
      ('神', RecitationTokenKind.correct),
      ('爱', RecitationTokenKind.correct),
      ('人', RecitationTokenKind.incorrect),
    ]);
  });

  test(
    'aligns repeated characters with the existing deterministic tie break',
    () {
      expect(tokens('天天', '天', finished: true), [
        ('_', RecitationTokenKind.omitted),
        ('天', RecitationTokenKind.correct),
      ]);
    },
  );

  test('folds English case while projecting the original target text', () {
    expect(tokens('For God', 'for god', finished: true), [
      ('F', RecitationTokenKind.correct),
      ('o', RecitationTokenKind.correct),
      ('r', RecitationTokenKind.correct),
      (' ', RecitationTokenKind.formatting),
      ('G', RecitationTokenKind.correct),
      ('o', RecitationTokenKind.correct),
      ('d', RecitationTokenKind.correct),
    ]);
  });
}
