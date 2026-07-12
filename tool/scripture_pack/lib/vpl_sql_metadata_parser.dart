import 'book_code_map.dart';

final class VplSqlVerseMetadata {
  const VplSqlVerseMetadata({
    required this.sourceVerseId,
    required this.bookCode,
    required this.chapter,
    required this.startVerse,
    required this.endVerse,
  });

  final String sourceVerseId;
  final String bookCode;
  final int chapter;
  final int startVerse;
  final int endVerse;

  @override
  bool operator ==(Object other) {
    return other is VplSqlVerseMetadata &&
        other.sourceVerseId == sourceVerseId &&
        other.bookCode == bookCode &&
        other.chapter == chapter &&
        other.startVerse == startVerse &&
        other.endVerse == endVerse;
  }

  @override
  int get hashCode {
    return Object.hash(sourceVerseId, bookCode, chapter, startVerse, endVerse);
  }
}

final class VplSqlFormatException implements FormatException {
  const VplSqlFormatException(this.lineNumber, this.source, [this.reason = '']);

  final int lineNumber;
  final String reason;

  @override
  final String source;

  @override
  String get message {
    return reason.isEmpty
        ? 'Malformed VPL SQL line $lineNumber'
        : 'Malformed VPL SQL line $lineNumber: $reason';
  }

  @override
  int? get offset => null;

  @override
  String toString() => 'VplSqlFormatException($lineNumber, $reason)';
}

final class VplSqlMetadataParser {
  VplSqlMetadataParser({required this.expectedTableName}) {
    if (!_tableName.hasMatch(expectedTableName)) {
      throw ArgumentError.value(expectedTableName, 'expectedTableName');
    }
  }

  final String expectedTableName;

  static final _tableName = RegExp(r'^[a-z0-9_]+$');
  static final _insert = RegExp(
    r'^INSERT INTO ([a-z0-9_]+) VALUES '
    r'\("([^"\\]+)","(\d{3}_\d+_\d+)","([A-Z0-9]{3})",'
    r'"(\d+)","(\d+)","(\d+)","(?:[^"\\]|\\.)*"\);$',
  );

  Stream<VplSqlVerseMetadata> parse(Stream<String> lines) async* {
    final sourceIds = <String>{};
    var lineNumber = 0;
    await for (final line in lines) {
      lineNumber += 1;
      if (line.trim().isEmpty) {
        continue;
      }
      final match = _insert.firstMatch(line);
      if (match == null || match.group(1) != expectedTableName) {
        throw VplSqlFormatException(lineNumber, line);
      }
      final sourceVerseId = match.group(2)!;
      if (!sourceIds.add(sourceVerseId)) {
        throw VplSqlFormatException(lineNumber, line, 'Duplicate verse ID');
      }
      final chapter = int.parse(match.group(5)!);
      final startVerse = int.parse(match.group(6)!);
      final endVerse = int.parse(match.group(7)!);
      if (chapter <= 0 || startVerse <= 0 || endVerse < startVerse) {
        throw VplSqlFormatException(lineNumber, line, 'Invalid verse range');
      }
      String bookCode;
      try {
        bookCode = BookCodeMap.normalizeSql(match.group(4)!);
      } on FormatException catch (error) {
        throw VplSqlFormatException(lineNumber, line, error.message);
      }
      yield VplSqlVerseMetadata(
        sourceVerseId: sourceVerseId,
        bookCode: bookCode,
        chapter: chapter,
        startVerse: startVerse,
        endVerse: endVerse,
      );
    }
  }
}
