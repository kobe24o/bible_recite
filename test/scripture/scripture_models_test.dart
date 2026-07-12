import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:flutter_test/flutter_test.dart';

const protestant = CanonId.protestant66;

VerseKey verse(String book, int chapter, int number) {
  return (
    canonId: protestant,
    osisBookId: book,
    chapter: chapter,
    verse: number,
  );
}

void main() {
  test('verse keys and passage ranges have stable value equality', () {
    final first = PassageRange(
      start: verse('JHN', 3, 16),
      end: verse('JHN', 3, 18),
    );
    final second = PassageRange(
      start: verse('JHN', 3, 16),
      end: verse('JHN', 3, 18),
    );

    expect(first.start, second.start);
    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });

  test('passage range rejects reversed or cross-book references', () {
    expect(
      () => PassageRange(start: verse('JHN', 3, 18), end: verse('JHN', 3, 16)),
      throwsArgumentError,
    );
    expect(
      () => PassageRange(start: verse('JHN', 3, 16), end: verse('ACT', 1, 1)),
      throwsArgumentError,
    );
  });

  test('passage selection accepts ordered discrete ranges', () {
    final selection = PassageSelection([
      PassageRange(start: verse('JHN', 3, 16), end: verse('JHN', 3, 18)),
      PassageRange(start: verse('JHN', 4, 1), end: verse('JHN', 4, 2)),
      PassageRange(start: verse('ACT', 1, 1), end: verse('ACT', 1, 1)),
    ]);

    expect(selection.ranges, hasLength(3));
    expect(
      () => selection.ranges.add(
        PassageRange(start: verse('ROM', 1, 1), end: verse('ROM', 1, 1)),
      ),
      throwsUnsupportedError,
    );
  });

  test('passage selection rejects empty, overlap, and noncanonical order', () {
    expect(() => PassageSelection(const []), throwsArgumentError);
    expect(
      () => PassageSelection([
        PassageRange(start: verse('JHN', 3, 16), end: verse('JHN', 3, 18)),
        PassageRange(start: verse('JHN', 3, 18), end: verse('JHN', 3, 20)),
      ]),
      throwsArgumentError,
    );
    expect(
      () => PassageSelection([
        PassageRange(start: verse('ACT', 1, 1), end: verse('ACT', 1, 1)),
        PassageRange(start: verse('JHN', 3, 16), end: verse('JHN', 3, 16)),
      ]),
      throwsArgumentError,
    );
  });

  test('selected passage flattens immutable source units in range order', () {
    final firstRange = PassageRange(
      start: verse('GEN', 24, 29),
      end: verse('GEN', 24, 30),
    );
    final secondRange = PassageRange(
      start: verse('JHN', 3, 16),
      end: verse('JHN', 3, 16),
    );
    final bridge = VerseUnit(
      translationId: 'cmn-cu89s',
      start: firstRange.start,
      end: firstRange.end,
      text: '利百加的哥哥拉班听见了。',
      status: SourceTextStatus.present,
    );
    final john = VerseUnit(
      translationId: 'cmn-cu89s',
      start: secondRange.start,
      end: secondRange.end,
      text: '神爱世人',
      status: SourceTextStatus.present,
    );
    final selected = SelectedPassage(
      selection: PassageSelection([firstRange, secondRange]),
      translationId: 'cmn-cu89s',
      passages: [
        Passage(range: firstRange, translationId: 'cmn-cu89s', units: [bridge]),
        Passage(range: secondRange, translationId: 'cmn-cu89s', units: [john]),
      ],
    );

    expect(selected.units, [bridge, john]);
    expect(
      () => selected.passages.add(selected.passages.first),
      throwsUnsupportedError,
    );
  });

  test('translation revision rejects an invalid semantic digest', () {
    expect(
      () => TranslationInfo(
        id: 'cmn-cu89s',
        languageTag: 'zh-Hans',
        name: '新标点和合本（简体）',
        canonId: protestant,
        packId: 'cmn-cu89s-v1',
        versificationId: 'ebible-cmn-cu89s',
        semanticSha256: 'not-a-sha256',
      ),
      throwsArgumentError,
    );
  });

  test('Bible book rejects invalid ordinal or chapter count', () {
    expect(
      () =>
          BibleBook(osisId: 'JHN', ordinal: 0, name: 'John', chapterCount: 21),
      throwsArgumentError,
    );
    expect(
      () =>
          BibleBook(osisId: 'JHN', ordinal: 43, name: 'John', chapterCount: 0),
      throwsArgumentError,
    );
  });

  test('parallel group rejects an empty source and target', () {
    expect(
      () => ParallelGroup(
        id: 'empty',
        sourceUnits: const [],
        targetUnits: const [],
        relation: ParallelRelation.oneToOne,
        provenance: 'fixture',
      ),
      throwsArgumentError,
    );
  });
}
