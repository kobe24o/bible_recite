import 'dart:convert';

import 'package:bible_recite/src/features/recitation/domain/bible_pronunciation_lexicon.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'loads the bundled simplified and traditional Bible overrides',
    () async {
      final lexicon = await BiblePronunciationLexicon.load(rootBundle);

      expect(lexicon.entries['长子'], ['zhang', 'zi']);
      expect(lexicon.entries['長子'], ['zhang', 'zi']);
      expect(lexicon.entries['行为'], ['xing', 'wei']);
      expect(lexicon.entries['行為'], ['xing', 'wei']);
      expect(() => lexicon.entries['长子']!.add('wrong'), throwsUnsupportedError);
      expect(() => lexicon.entries['new'] = ['new'], throwsUnsupportedError);
    },
  );

  test('rejects malformed or invalid override JSON', () async {
    Future<void> expectInvalid(String source) {
      return expectLater(
        BiblePronunciationLexicon.load(
          _StringAssetBundle({BiblePronunciationLexicon.assetPath: source}),
        ),
        throwsFormatException,
      );
    }

    await expectInvalid('{not json');
    await expectInvalid('{"": ["zhang"]}');
    await expectInvalid('{"长子": ["zhang"]}');
    await expectInvalid('{"长子": ["Zhang", "zi"]}');
    await expectInvalid('{"长子": ["zhang1", "zi"]}');
    await expectInvalid('{"长子": ["zhang", "zi"], "长子": ["chang", "zi"]}');
  });

  test('prefers the longest exact phrase at an overlapping position', () async {
    final lexicon = await BiblePronunciationLexicon.load(
      _StringAssetBundle({
        BiblePronunciationLexicon.assetPath: jsonEncode({
          '长': ['chang'],
          '长子': ['zhang', 'zi'],
          '长子名': ['zhang', 'zi', 'ming'],
          '子名': ['zi', 'ming'],
        }),
      }),
    );

    final match = lexicon.longestMatchAt(['长', '子', '名'], 0);
    expect(match, isNotNull);
    expect(match!.phrase, '长子名');
    expect(match.syllables, ['zhang', 'zi', 'ming']);
    expect(lexicon.longestMatchAt(['长', '子', '名'], 1)!.phrase, '子名');
    expect(lexicon.longestMatchAt(['长', '子', '名'], 3), isNull);
  });
}

final class _StringAssetBundle extends CachingAssetBundle {
  _StringAssetBundle(this.assets);

  final Map<String, String> assets;

  @override
  Future<ByteData> load(String key) async {
    final source = assets[key];
    if (source == null) {
      throw StateError('Missing test asset: $key');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(source)));
  }
}
