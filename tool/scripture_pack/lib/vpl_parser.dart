import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';

final class ParsedVplLine {
  const ParsedVplLine({
    required this.bookCode,
    required this.chapter,
    required this.verse,
    required this.text,
    required this.status,
  });

  final String bookCode;
  final int chapter;
  final int verse;
  final String text;
  final SourceTextStatus status;

  @override
  bool operator ==(Object other) {
    return other is ParsedVplLine &&
        other.bookCode == bookCode &&
        other.chapter == chapter &&
        other.verse == verse &&
        other.text == text &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(bookCode, chapter, verse, text, status);
}

final class VplFormatException implements FormatException {
  const VplFormatException(this.lineNumber, this.source);

  final int lineNumber;

  @override
  final String source;

  @override
  String get message => 'Malformed VPL line $lineNumber';

  @override
  int? get offset => null;

  @override
  String toString() => 'VplFormatException($lineNumber, $source)';
}

final class VplParser {
  static final _line = RegExp(
    r'^([1-4A-Z][A-Z0-9]{2})[ \t]+(\d+):(\d+)(?:[ \t](.*))?$',
  );

  Stream<ParsedVplLine> parse(Stream<String> lines) async* {
    var lineNumber = 0;
    await for (final raw in lines) {
      lineNumber += 1;
      var value = raw;
      if (lineNumber == 1 && value.startsWith('\uFEFF')) {
        value = value.substring(1);
      }
      if (value.trim().isEmpty) {
        continue;
      }
      final match = _line.firstMatch(value);
      if (match == null) {
        throw VplFormatException(lineNumber, value);
      }
      final chapter = int.parse(match.group(2)!);
      final verse = int.parse(match.group(3)!);
      if (chapter <= 0 || verse <= 0) {
        throw VplFormatException(lineNumber, value);
      }
      final text = match.group(4) ?? '';
      yield ParsedVplLine(
        bookCode: match.group(1)!,
        chapter: chapter,
        verse: verse,
        text: text,
        status: text.isEmpty
            ? SourceTextStatus.omitted
            : SourceTextStatus.present,
      );
    }
  }
}
