enum CanonId { protestant66 }

typedef VerseKey = ({
  CanonId canonId,
  String osisBookId,
  int chapter,
  int verse,
});

const protestant66BookOrder = <String, int>{
  'GEN': 1,
  'EXO': 2,
  'LEV': 3,
  'NUM': 4,
  'DEU': 5,
  'JOS': 6,
  'JDG': 7,
  'RUT': 8,
  '1SA': 9,
  '2SA': 10,
  '1KI': 11,
  '2KI': 12,
  '1CH': 13,
  '2CH': 14,
  'EZR': 15,
  'NEH': 16,
  'EST': 17,
  'JOB': 18,
  'PSA': 19,
  'PRO': 20,
  'ECC': 21,
  'SNG': 22,
  'ISA': 23,
  'JER': 24,
  'LAM': 25,
  'EZK': 26,
  'DAN': 27,
  'HOS': 28,
  'JOL': 29,
  'AMO': 30,
  'OBA': 31,
  'JON': 32,
  'MIC': 33,
  'NAM': 34,
  'HAB': 35,
  'ZEP': 36,
  'HAG': 37,
  'ZEC': 38,
  'MAL': 39,
  'MAT': 40,
  'MRK': 41,
  'LUK': 42,
  'JHN': 43,
  'ACT': 44,
  'ROM': 45,
  '1CO': 46,
  '2CO': 47,
  'GAL': 48,
  'EPH': 49,
  'PHP': 50,
  'COL': 51,
  '1TH': 52,
  '2TH': 53,
  '1TI': 54,
  '2TI': 55,
  'TIT': 56,
  'PHM': 57,
  'HEB': 58,
  'JAS': 59,
  '1PE': 60,
  '2PE': 61,
  '1JN': 62,
  '2JN': 63,
  '3JN': 64,
  'JUD': 65,
  'REV': 66,
};

final class PassageRange {
  PassageRange({required this.start, required this.end}) {
    if (start.chapter <= 0 ||
        start.verse <= 0 ||
        end.chapter <= 0 ||
        end.verse <= 0) {
      throw ArgumentError('Passage references must be positive');
    }
    if (start.canonId != end.canonId || start.osisBookId != end.osisBookId) {
      throw ArgumentError('A passage range must stay in one book and canon');
    }
    if (_compareWithinBook(start, end) > 0) {
      throw ArgumentError('Passage start must precede end');
    }
  }

  final VerseKey start;
  final VerseKey end;

  @override
  bool operator ==(Object other) {
    return other is PassageRange && other.start == start && other.end == end;
  }

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'PassageRange($start, $end)';
}

final class PassageSelection {
  PassageSelection(List<PassageRange> ranges)
    : ranges = List.unmodifiable(_validateRanges(ranges));

  final List<PassageRange> ranges;

  static List<PassageRange> _validateRanges(List<PassageRange> ranges) {
    if (ranges.isEmpty) {
      throw ArgumentError('A passage selection must not be empty');
    }

    for (var index = 1; index < ranges.length; index++) {
      final previous = ranges[index - 1];
      final current = ranges[index];
      if (_compareCanonical(previous.end, current.start) >= 0) {
        throw ArgumentError(
          'Passage selection ranges must be canonical and nonoverlapping',
        );
      }
    }
    return ranges;
  }
}

final class TranslationInfo {
  TranslationInfo({
    required this.id,
    required this.languageTag,
    required this.name,
    required this.canonId,
    required this.packId,
    required this.versificationId,
    required this.semanticSha256,
  }) {
    if (id.isEmpty ||
        languageTag.isEmpty ||
        name.isEmpty ||
        packId.isEmpty ||
        versificationId.isEmpty ||
        !_sha256Pattern.hasMatch(semanticSha256)) {
      throw ArgumentError('Translation revision metadata is invalid');
    }
  }

  final String id;
  final String languageTag;
  final String name;
  final CanonId canonId;
  final String packId;
  final String versificationId;
  final String semanticSha256;
}

final class BibleBook {
  BibleBook({
    required this.osisId,
    required this.ordinal,
    required this.name,
    required this.chapterCount,
  }) {
    if (!protestant66BookOrder.containsKey(osisId) ||
        ordinal <= 0 ||
        name.isEmpty ||
        chapterCount <= 0) {
      throw ArgumentError('Bible book metadata is invalid');
    }
  }

  final String osisId;
  final int ordinal;
  final String name;
  final int chapterCount;
}

enum SourceTextStatus { present, omitted }

final class VerseUnit {
  VerseUnit({
    required this.translationId,
    required this.start,
    required this.end,
    required this.text,
    required this.status,
  }) {
    PassageRange(start: start, end: end);
  }

  final String translationId;
  final VerseKey start;
  final VerseKey end;
  final String text;
  final SourceTextStatus status;
}

final class Passage {
  Passage({
    required this.range,
    required this.translationId,
    required List<VerseUnit> units,
  }) : units = List.unmodifiable(units);

  final PassageRange range;
  final String translationId;
  final List<VerseUnit> units;
}

final class SelectedPassage {
  SelectedPassage({
    required this.selection,
    required this.translationId,
    required List<Passage> passages,
  }) : passages = List.unmodifiable(passages) {
    if (this.passages.length != selection.ranges.length) {
      throw ArgumentError('Every selected range must have one passage');
    }
    for (var index = 0; index < this.passages.length; index++) {
      final passage = this.passages[index];
      if (passage.translationId != translationId ||
          passage.range != selection.ranges[index]) {
        throw ArgumentError(
          'Selected passages must match the translation and range order',
        );
      }
    }
  }

  final PassageSelection selection;
  final String translationId;
  final List<Passage> passages;

  List<VerseUnit> get units {
    return passages.expand((passage) => passage.units).toList(growable: false);
  }
}

final class LocatedPassageRange {
  const LocatedPassageRange({required this.translationId, required this.range});

  final String translationId;
  final PassageRange range;
}

enum ParallelRelation {
  oneToOne,
  sourceBridge,
  targetBridge,
  crossChapterTargetBridge,
  relocated,
  sourceAbsent,
  targetAbsent,
}

final class ParallelGroup {
  ParallelGroup({
    required this.id,
    required List<VerseUnit> sourceUnits,
    required List<VerseUnit> targetUnits,
    required this.relation,
    required this.provenance,
  }) : sourceUnits = List.unmodifiable(sourceUnits),
       targetUnits = List.unmodifiable(targetUnits) {
    if (id.isEmpty ||
        provenance.isEmpty ||
        (sourceUnits.isEmpty && targetUnits.isEmpty)) {
      throw ArgumentError('Parallel group metadata is invalid');
    }
  }

  final String id;
  final List<VerseUnit> sourceUnits;
  final List<VerseUnit> targetUnits;
  final ParallelRelation relation;
  final String provenance;
}

final class ParallelPassage {
  ParallelPassage({
    required this.sourceRange,
    required this.targetTranslationId,
    required List<ParallelGroup> groups,
    required List<String> warnings,
  }) : groups = List.unmodifiable(groups),
       warnings = List.unmodifiable(warnings);

  final LocatedPassageRange sourceRange;
  final String targetTranslationId;
  final List<ParallelGroup> groups;
  final List<String> warnings;
}

int _compareWithinBook(VerseKey left, VerseKey right) {
  final chapterComparison = left.chapter.compareTo(right.chapter);
  return chapterComparison != 0
      ? chapterComparison
      : left.verse.compareTo(right.verse);
}

final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

int _compareCanonical(VerseKey left, VerseKey right) {
  if (left.canonId != right.canonId) {
    return left.canonId.index.compareTo(right.canonId.index);
  }
  final leftBook = protestant66BookOrder[left.osisBookId];
  final rightBook = protestant66BookOrder[right.osisBookId];
  if (leftBook == null || rightBook == null) {
    throw ArgumentError('Unknown Protestant canon book ID');
  }
  final bookComparison = leftBook.compareTo(rightBook);
  return bookComparison != 0 ? bookComparison : _compareWithinBook(left, right);
}
