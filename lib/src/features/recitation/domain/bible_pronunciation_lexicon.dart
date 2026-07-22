import 'dart:convert';

import 'package:flutter/services.dart';

/// Phrase-specific, toneless Mandarin pronunciations for biblical text.
final class BiblePronunciationLexicon {
  const BiblePronunciationLexicon._(
    this.entries,
    this._matchesByFirstCharacter,
  );

  static const assetPath = 'assets/pronunciation/bible_pinyin_overrides.json';

  /// Maps an exact phrase to one toneless syllable for each Han character.
  final Map<String, List<String>> entries;
  final Map<String, List<LexiconMatch>> _matchesByFirstCharacter;

  static Future<BiblePronunciationLexicon> load(AssetBundle assetBundle) async {
    final source = await assetBundle.loadString(assetPath);
    return fromJson(source);
  }

  /// Parses and validates the asset source. Exposed for deterministic tests.
  static BiblePronunciationLexicon fromJson(String source) {
    final decoded = _decodeObject(source);
    _rejectDuplicatePhraseKeys(source);

    final validatedEntries = <String, List<String>>{};
    for (final entry in decoded.entries) {
      final phrase = entry.key;
      if (phrase.isEmpty) {
        throw const FormatException('Pronunciation phrase must not be empty.');
      }

      final hanCount = _characters(phrase).where(_isComparableHan).length;
      if (hanCount == 0) {
        throw FormatException(
          'Pronunciation phrase "$phrase" must contain a Han character.',
        );
      }

      final rawSyllables = entry.value;
      if (rawSyllables is! List) {
        throw FormatException('Pronunciation for "$phrase" must be an array.');
      }
      if (rawSyllables.length != hanCount) {
        throw FormatException(
          'Pronunciation for "$phrase" must have $hanCount syllables.',
        );
      }

      final syllables = <String>[];
      for (final rawSyllable in rawSyllables) {
        if (rawSyllable is! String ||
            !_isTonelessLowercaseSyllable(rawSyllable)) {
          throw FormatException(
            'Pronunciation for "$phrase" must use lowercase ASCII pinyin.',
          );
        }
        syllables.add(rawSyllable);
      }
      validatedEntries[phrase] = List.unmodifiable(syllables);
    }

    final entries = Map<String, List<String>>.unmodifiable(validatedEntries);
    final matchesByFirstCharacter = <String, List<LexiconMatch>>{};
    for (final entry in entries.entries) {
      final match = LexiconMatch._(
        entry.key,
        entry.value,
        _characters(entry.key),
      );
      matchesByFirstCharacter
          .putIfAbsent(match._characters.first, () => <LexiconMatch>[])
          .add(match);
    }

    for (final matches in matchesByFirstCharacter.values) {
      matches.sort((left, right) {
        final byLength = right._characters.length.compareTo(
          left._characters.length,
        );
        return byLength != 0 ? byLength : left.phrase.compareTo(right.phrase);
      });
    }

    return BiblePronunciationLexicon._(
      entries,
      Map<String, List<LexiconMatch>>.unmodifiable({
        for (final entry in matchesByFirstCharacter.entries)
          entry.key: List<LexiconMatch>.unmodifiable(entry.value),
      }),
    );
  }

  /// Returns the longest phrase that exactly begins at [start], if any.
  LexiconMatch? longestMatchAt(List<String> characters, int start) {
    if (start < 0 || start >= characters.length) {
      return null;
    }

    for (final match
        in _matchesByFirstCharacter[characters[start]] ?? const []) {
      if (start + match._characters.length > characters.length) {
        continue;
      }
      var matches = true;
      for (var index = 0; index < match._characters.length; index++) {
        if (characters[start + index] != match._characters[index]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        return match;
      }
    }
    return null;
  }
}

/// An immutable phrase pronunciation returned by [BiblePronunciationLexicon].
final class LexiconMatch {
  const LexiconMatch._(this.phrase, this.syllables, this._characters);

  final String phrase;
  final List<String> syllables;
  final List<String> _characters;
}

Map<String, dynamic> _decodeObject(String source) {
  try {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Pronunciation asset must be a JSON object.');
    }
    final entries = <String, dynamic>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String) {
        throw const FormatException(
          'Pronunciation asset keys must be strings.',
        );
      }
      entries[entry.key as String] = entry.value;
    }
    return entries;
  } on FormatException {
    rethrow;
  } on Object catch (error) {
    throw FormatException('Invalid pronunciation JSON: $error');
  }
}

void _rejectDuplicatePhraseKeys(String source) {
  var index = _skipWhitespace(source, 0);
  if (index >= source.length || source[index] != '{') {
    return;
  }
  index++;
  final phrases = <String>{};

  while (true) {
    index = _skipWhitespace(source, index);
    if (index < source.length && source[index] == '}') {
      return;
    }

    final keyStart = index;
    index = _skipJsonString(source, index);
    final phrase = jsonDecode(source.substring(keyStart, index));
    if (phrase is! String || !phrases.add(phrase)) {
      throw FormatException('Duplicate pronunciation phrase "$phrase".');
    }

    index = _skipWhitespace(source, index);
    if (index >= source.length || source[index] != ':') {
      return;
    }
    index = _skipJsonValue(source, _skipWhitespace(source, index + 1));
    index = _skipWhitespace(source, index);
    if (index < source.length && source[index] == ',') {
      index++;
      continue;
    }
    return;
  }
}

int _skipWhitespace(String source, int index) {
  while (index < source.length && _isWhitespace(source.codeUnitAt(index))) {
    index++;
  }
  return index;
}

bool _isWhitespace(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x09 ||
    codeUnit == 0x0a ||
    codeUnit == 0x0d;

int _skipJsonString(String source, int index) {
  if (index >= source.length || source[index] != '"') {
    return index;
  }
  index++;
  var escaped = false;
  while (index < source.length) {
    final character = source[index++];
    if (escaped) {
      escaped = false;
    } else if (character == r'\') {
      escaped = true;
    } else if (character == '"') {
      return index;
    }
  }
  return index;
}

int _skipJsonValue(String source, int index) {
  if (index >= source.length) {
    return index;
  }
  if (source[index] == '"') {
    return _skipJsonString(source, index);
  }
  if (source[index] != '{' && source[index] != '[') {
    while (index < source.length &&
        source[index] != ',' &&
        source[index] != '}') {
      index++;
    }
    return index;
  }

  var nesting = 0;
  while (index < source.length) {
    final character = source[index];
    if (character == '"') {
      index = _skipJsonString(source, index);
      continue;
    }
    if (character == '{' || character == '[') {
      nesting++;
    } else if (character == '}' || character == ']') {
      nesting--;
      if (nesting == 0) {
        return index + 1;
      }
    }
    index++;
  }
  return index;
}

List<String> _characters(String value) =>
    value.runes.map(String.fromCharCode).toList(growable: false);

bool _isComparableHan(String character) {
  final rune = character.runes.single;
  return (rune >= 0x3400 && rune <= 0x4dbf) ||
      (rune >= 0x4e00 && rune <= 0x9fff) ||
      (rune >= 0xf900 && rune <= 0xfaff) ||
      (rune >= 0x20000 && rune <= 0x2ffff);
}

bool _isTonelessLowercaseSyllable(String value) =>
    RegExp(r'^[a-z]+$').hasMatch(value);
