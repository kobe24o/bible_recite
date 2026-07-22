enum RecitationTokenKind {
  correct,
  incorrect,
  omitted,
  reordered,
  pending,
  formatting,
}

final class RecitationToken {
  const RecitationToken(this.text, this.kind);
  final String text;
  final RecitationTokenKind kind;
}

final class RecitationAlignment {
  const RecitationAlignment.fromTokens({
    required this.tokens,
    required this.targetLength,
  });

  final List<RecitationToken> tokens;
  final int targetLength;

  int get correctCount => _count(RecitationTokenKind.correct);
  int get incorrectCount => _count(RecitationTokenKind.incorrect);
  int get omittedCount => _count(RecitationTokenKind.omitted);
  int get reorderedCount => _count(RecitationTokenKind.reordered);
  double get accuracy => targetLength == 0
      ? 0
      : (correctCount / targetLength).clamp(0, 1).toDouble();

  int _count(RecitationTokenKind kind) =>
      tokens.where((token) => token.kind == kind).length;
}
