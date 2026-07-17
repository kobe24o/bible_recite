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
  const RecitationAlignment._(this.tokens, this.targetLength);

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

  static RecitationAlignment compare(
    String target,
    String transcript, {
    bool finished = false,
  }) {
    final expected = _characters(_normalize(target));
    final spoken = _characters(_normalize(transcript));
    final n = expected.length;
    final m = spoken.length;
    final distance = List.generate(n + 1, (i) => List<int>.filled(m + 1, 0));
    for (var i = 0; i <= n; i++) {
      distance[i][0] = i;
    }
    for (var j = 0; j <= m; j++) {
      distance[0][j] = j;
    }
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final substitution =
            distance[i - 1][j - 1] + (expected[i - 1] == spoken[j - 1] ? 0 : 1);
        var best = _min3(
          substitution,
          distance[i - 1][j] + 1,
          distance[i][j - 1] + 1,
        );
        if (i > 1 &&
            j > 1 &&
            expected[i - 1] == spoken[j - 2] &&
            expected[i - 2] == spoken[j - 1]) {
          final transposition = distance[i - 2][j - 2] + 1;
          if (transposition < best) best = transposition;
        }
        distance[i][j] = best;
      }
    }

    final reversed = <_AlignmentStep>[];
    var i = n;
    var j = m;
    while (i > 0 || j > 0) {
      if (i > 1 &&
          j > 1 &&
          expected[i - 1] == spoken[j - 2] &&
          expected[i - 2] == spoken[j - 1] &&
          distance[i][j] == distance[i - 2][j - 2] + 1) {
        reversed
          ..add(
            _AlignmentStep(
              spoken[j - 1],
              RecitationTokenKind.reordered,
              consumesTarget: true,
            ),
          )
          ..add(
            _AlignmentStep(
              spoken[j - 2],
              RecitationTokenKind.reordered,
              consumesTarget: true,
            ),
          );
        i -= 2;
        j -= 2;
      } else if (i > 0 &&
          j > 0 &&
          expected[i - 1] == spoken[j - 1] &&
          distance[i][j] == distance[i - 1][j - 1]) {
        reversed.add(
          _AlignmentStep(
            spoken[j - 1],
            RecitationTokenKind.correct,
            consumesTarget: true,
            showOriginalTarget: true,
          ),
        );
        i--;
        j--;
      } else if (i > 0 &&
          j > 0 &&
          distance[i][j] == distance[i - 1][j - 1] + 1) {
        reversed.add(
          _AlignmentStep(
            spoken[j - 1],
            RecitationTokenKind.incorrect,
            consumesTarget: true,
          ),
        );
        i--;
        j--;
      } else if (i > 0 && distance[i][j] == distance[i - 1][j] + 1) {
        final trailing = j == m;
        reversed.add(
          trailing
              ? _AlignmentStep(
                  expected[i - 1],
                  finished
                      ? RecitationTokenKind.incorrect
                      : RecitationTokenKind.pending,
                  consumesTarget: true,
                  showOriginalTarget: true,
                )
              : const _AlignmentStep(
                  '_',
                  RecitationTokenKind.omitted,
                  consumesTarget: true,
                ),
        );
        i--;
      } else {
        reversed.add(
          _AlignmentStep(
            spoken[j - 1],
            RecitationTokenKind.incorrect,
            consumesTarget: false,
          ),
        );
        j--;
      }
    }
    return RecitationAlignment._(
      List.unmodifiable(_projectOntoOriginal(target, reversed.reversed)),
      expected.length,
    );
  }

  static List<RecitationToken> _projectOntoOriginal(
    String target,
    Iterable<_AlignmentStep> aligned,
  ) {
    final steps = aligned.toList(growable: false);
    final output = <RecitationToken>[];
    var stepIndex = 0;
    for (final character in _characters(target)) {
      if (!_isComparable(character)) {
        output.add(RecitationToken(character, RecitationTokenKind.formatting));
        continue;
      }
      while (stepIndex < steps.length && !steps[stepIndex].consumesTarget) {
        final step = steps[stepIndex++];
        output.add(RecitationToken(step.text, step.kind));
      }
      if (stepIndex >= steps.length) continue;
      final step = steps[stepIndex++];
      output.add(
        RecitationToken(
          step.showOriginalTarget ? character : step.text,
          step.kind,
        ),
      );
    }
    while (stepIndex < steps.length) {
      final step = steps[stepIndex++];
      output.add(RecitationToken(step.text, step.kind));
    }
    return output;
  }

  static int _min3(int a, int b, int c) {
    var result = a;
    if (b < result) result = b;
    if (c < result) result = c;
    return result;
  }

  static String _normalize(String value) =>
      _characters(value).where(_isComparable).join().toLowerCase();

  static bool _isComparable(String value) =>
      RegExp(r'^[\p{L}\p{N}]$', unicode: true).hasMatch(value);

  static List<String> _characters(String value) =>
      value.runes.map(String.fromCharCode).toList(growable: false);
}

final class _AlignmentStep {
  const _AlignmentStep(
    this.text,
    this.kind, {
    required this.consumesTarget,
    this.showOriginalTarget = false,
  });

  final String text;
  final RecitationTokenKind kind;
  final bool consumesTarget;
  final bool showOriginalTarget;
}
