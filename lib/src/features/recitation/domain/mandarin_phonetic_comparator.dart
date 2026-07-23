import 'package:lpinyin/lpinyin.dart';

import 'bible_pronunciation_lexicon.dart';
import 'recitation_alignment.dart';
import 'recitation_comparator.dart';

/// Aligns Mandarin recitations by exact text first, then toneless pinyin.
///
/// Pinyin is derived independently from the target and ASR transcript. A
/// phrase-specific Bible lexicon takes precedence over lpinyin's dictionaries,
/// so an arbitrary pronunciation of a polyphonic character is never accepted.
final class MandarinPhoneticComparator implements RecitationComparator {
  MandarinPhoneticComparator({
    required this.lexicon,
    this.ignoreFinalNasal = false,
  });

  final BiblePronunciationLexicon lexicon;
  final bool ignoreFinalNasal;

  @override
  RecitationAlignment compare(
    String target,
    String transcript, {
    required bool finished,
  }) {
    final expected = _comparableCharacters(target);
    final spoken = _comparableCharacters(transcript);
    final expectedPinyin = finished
        ? _encodePinyin(expected)
        : List<String?>.filled(expected.length, null);
    final spokenPinyin = finished
        ? _encodePinyin(spoken)
        : List<String?>.filled(spoken.length, null);
    final scores = _buildScores(expected, spoken, expectedPinyin, spokenPinyin);

    final reversed = <_AlignmentStep>[];
    var i = expected.length;
    var j = spoken.length;
    while (i > 0 || j > 0) {
      if (_isExactTransposition(expected, spoken, i, j) &&
          scores[i][j] == scores[i - 2][j - 2].add(_Score.transposition)) {
        reversed
          ..add(
            _AlignmentStep(
              spoken[j - 1].text,
              RecitationTokenKind.reordered,
              consumesTarget: true,
            ),
          )
          ..add(
            _AlignmentStep(
              spoken[j - 2].text,
              RecitationTokenKind.reordered,
              consumesTarget: true,
            ),
          );
        i -= 2;
        j -= 2;
        continue;
      }

      if (i > 0 && j > 0) {
        final kind = _substitutionKind(
          expected[i - 1],
          spoken[j - 1],
          expectedPinyin[i - 1],
          spokenPinyin[j - 1],
          ignoreFinalNasal,
        );
        if (scores[i][j] == scores[i - 1][j - 1].add(_costFor(kind))) {
          reversed.add(
            _AlignmentStep(
              spoken[j - 1].text,
              kind,
              consumesTarget: true,
              showOriginalTarget:
                  kind == RecitationTokenKind.correct ||
                  kind == RecitationTokenKind.phoneticCorrect,
            ),
          );
          i--;
          j--;
          continue;
        }
      }

      if (i > 0 && scores[i][j] == scores[i - 1][j].add(_Score.deletion)) {
        final trailing = j == spoken.length;
        reversed.add(
          trailing
              ? _AlignmentStep(
                  expected[i - 1].text,
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
        continue;
      }

      reversed.add(
        _AlignmentStep(
          spoken[j - 1].text,
          RecitationTokenKind.incorrect,
          consumesTarget: false,
        ),
      );
      j--;
    }

    return RecitationAlignment.fromTokens(
      tokens: _projectOntoOriginal(target, reversed.reversed),
      targetLength: expected.length,
    );
  }

  List<List<_Score>> _buildScores(
    List<_ComparableCharacter> expected,
    List<_ComparableCharacter> spoken,
    List<String?> expectedPinyin,
    List<String?> spokenPinyin,
  ) {
    final scores = List.generate(
      expected.length + 1,
      (_) => List<_Score>.filled(spoken.length + 1, _Score.zero),
    );
    for (var i = 1; i <= expected.length; i++) {
      scores[i][0] = scores[i - 1][0].add(_Score.deletion);
    }
    for (var j = 1; j <= spoken.length; j++) {
      scores[0][j] = scores[0][j - 1].add(_Score.insertion);
    }

    for (var i = 1; i <= expected.length; i++) {
      for (var j = 1; j <= spoken.length; j++) {
        final kind = _substitutionKind(
          expected[i - 1],
          spoken[j - 1],
          expectedPinyin[i - 1],
          spokenPinyin[j - 1],
          ignoreFinalNasal,
        );
        var best = scores[i - 1][j - 1].add(_costFor(kind));
        final deletion = scores[i - 1][j].add(_Score.deletion);
        if (deletion < best) {
          best = deletion;
        }
        final insertion = scores[i][j - 1].add(_Score.insertion);
        if (insertion < best) {
          best = insertion;
        }
        if (_isExactTransposition(expected, spoken, i, j)) {
          final transposition = scores[i - 2][j - 2].add(_Score.transposition);
          if (transposition < best) {
            best = transposition;
          }
        }
        scores[i][j] = best;
      }
    }
    return scores;
  }

  List<String?> _encodePinyin(List<_ComparableCharacter> characters) {
    final encoded = List<String?>.filled(characters.length, null);
    final text = characters.map((character) => character.text).toList();
    var runStart = 0;
    while (runStart < characters.length) {
      if (!characters[runStart].isHan) {
        runStart++;
        continue;
      }
      var runEnd = runStart + 1;
      while (runEnd < characters.length && characters[runEnd].isHan) {
        runEnd++;
      }
      _encodeHanRun(text, runStart, runEnd, encoded);
      runStart = runEnd;
    }
    return encoded;
  }

  void _encodeHanRun(
    List<String> characters,
    int start,
    int end,
    List<String?> encoded,
  ) {
    var index = start;
    var uncoveredStart = start;
    while (index < end) {
      final match = lexicon.longestMatchAt(characters, index);
      if (match == null || index + match.syllables.length > end) {
        index++;
        continue;
      }

      _encodeUncoveredSpan(characters, uncoveredStart, index, encoded);
      for (var offset = 0; offset < match.syllables.length; offset++) {
        encoded[index + offset] = match.syllables[offset];
      }
      index += match.syllables.length;
      uncoveredStart = index;
    }
    _encodeUncoveredSpan(characters, uncoveredStart, end, encoded);
  }

  void _encodeUncoveredSpan(
    List<String> characters,
    int start,
    int end,
    List<String?> encoded,
  ) {
    if (start == end) {
      return;
    }
    final syllables = _convertPinyin(characters.sublist(start, end).join());
    if (syllables != null && syllables.length == end - start) {
      for (var offset = 0; offset < syllables.length; offset++) {
        encoded[start + offset] = syllables[offset];
      }
      return;
    }

    // A bad unit must not disable phonetic matching for its neighbours.
    for (var index = start; index < end; index++) {
      final single = _convertPinyin(characters[index]);
      if (single != null && single.length == 1) {
        encoded[index] = single.single;
      }
    }
  }

  List<String>? _convertPinyin(String text) {
    try {
      const separator = '\u0001';
      final result = PinyinHelper.getPinyinE(
        text,
        separator: separator,
        format: PinyinFormat.WITHOUT_TONE,
      );
      final syllables = result.split(separator);
      if (syllables.any((syllable) => !_isTonelessSyllable(syllable))) {
        return null;
      }
      return syllables;
    } on Object {
      return null;
    }
  }

  static RecitationTokenKind _substitutionKind(
    _ComparableCharacter expected,
    _ComparableCharacter spoken,
    String? expectedPinyin,
    String? spokenPinyin,
    bool ignoreFinalNasal,
  ) {
    if (expected.normalized == spoken.normalized) {
      return RecitationTokenKind.correct;
    }
    if (expectedPinyin != null &&
        _normalizedPinyin(expectedPinyin, ignoreFinalNasal) ==
            _normalizedPinyin(spokenPinyin, ignoreFinalNasal)) {
      return RecitationTokenKind.phoneticCorrect;
    }
    return RecitationTokenKind.incorrect;
  }

  static String? _normalizedPinyin(String? value, bool ignoreFinalNasal) {
    if (!ignoreFinalNasal || value == null) return value;
    return value.endsWith('ing')
        ? '${value.substring(0, value.length - 3)}in'
        : value.endsWith('eng')
        ? '${value.substring(0, value.length - 3)}en'
        : value.endsWith('ang')
        ? '${value.substring(0, value.length - 3)}an'
        : value.endsWith('ong')
        ? '${value.substring(0, value.length - 3)}on'
        : value;
  }

  static _Score _costFor(RecitationTokenKind kind) => switch (kind) {
    RecitationTokenKind.correct => _Score.exactMatch,
    RecitationTokenKind.phoneticCorrect => _Score.phoneticMatch,
    _ => _Score.substitution,
  };

  static bool _isExactTransposition(
    List<_ComparableCharacter> expected,
    List<_ComparableCharacter> spoken,
    int i,
    int j,
  ) =>
      i > 1 &&
      j > 1 &&
      expected[i - 1].normalized == spoken[j - 2].normalized &&
      expected[i - 2].normalized == spoken[j - 1].normalized;

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
      if (stepIndex >= steps.length) {
        continue;
      }
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
}

final class _ComparableCharacter {
  _ComparableCharacter(this.text)
    : normalized = text.toLowerCase(),
      isHan = _isComparableHan(text);

  final String text;
  final String normalized;
  final bool isHan;
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

/// Lexicographic cost: edit errors, then more exact, then more phonetic
/// matches, then fewer edit operations.
final class _Score implements Comparable<_Score> {
  const _Score(
    this.editErrors,
    this.negativeExactMatches,
    this.negativePhoneticMatches,
    this.editOperations,
  );

  static const zero = _Score(0, 0, 0, 0);
  static const exactMatch = _Score(0, -1, 0, 0);
  static const phoneticMatch = _Score(0, 0, -1, 0);
  static const substitution = _Score(1, 0, 0, 1);
  static const deletion = _Score(1, 0, 0, 1);
  static const insertion = _Score(1, 0, 0, 1);
  static const transposition = _Score(1, 0, 0, 1);

  final int editErrors;
  final int negativeExactMatches;
  final int negativePhoneticMatches;
  final int editOperations;

  _Score add(_Score other) => _Score(
    editErrors + other.editErrors,
    negativeExactMatches + other.negativeExactMatches,
    negativePhoneticMatches + other.negativePhoneticMatches,
    editOperations + other.editOperations,
  );

  @override
  int compareTo(_Score other) {
    var result = editErrors.compareTo(other.editErrors);
    if (result != 0) return result;
    result = negativeExactMatches.compareTo(other.negativeExactMatches);
    if (result != 0) return result;
    result = negativePhoneticMatches.compareTo(other.negativePhoneticMatches);
    if (result != 0) return result;
    return editOperations.compareTo(other.editOperations);
  }

  bool operator <(_Score other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is _Score &&
      editErrors == other.editErrors &&
      negativeExactMatches == other.negativeExactMatches &&
      negativePhoneticMatches == other.negativePhoneticMatches &&
      editOperations == other.editOperations;

  @override
  int get hashCode => Object.hash(
    editErrors,
    negativeExactMatches,
    negativePhoneticMatches,
    editOperations,
  );
}

List<_ComparableCharacter> _comparableCharacters(String value) => _characters(
  value,
).where(_isComparable).map(_ComparableCharacter.new).toList(growable: false);

List<String> _characters(String value) =>
    value.runes.map(String.fromCharCode).toList(growable: false);

bool _isComparable(String value) =>
    RegExp(r'^[\p{L}\p{N}]$', unicode: true).hasMatch(value);

bool _isComparableHan(String character) {
  final rune = character.runes.single;
  return (rune >= 0x3400 && rune <= 0x4dbf) ||
      (rune >= 0x4e00 && rune <= 0x9fff) ||
      (rune >= 0xf900 && rune <= 0xfaff) ||
      (rune >= 0x20000 && rune <= 0x2ffff);
}

bool _isTonelessSyllable(String value) => RegExp(r'^[a-z]+$').hasMatch(value);
