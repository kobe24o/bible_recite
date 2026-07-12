import 'dart:convert';

import 'package:archive/archive.dart';

import 'scripture_source_adapter.dart';
import 'verse_unit_assembler.dart';
import 'vpl_parser.dart';
import 'vpl_sql_metadata_parser.dart';

final class EbibleVplSourceAdapter implements ScriptureSourceAdapter {
  @override
  String get formatId => 'ebible-vpl-v1';

  @override
  Future<NormalizedScriptureSource> parse(SourceBundle source) async {
    final id = source.translation.id;
    final archive = ZipDecoder().decodeBytes(
      await source.archive.readAsBytes(),
      verify: true,
    );
    final text = _readUtf8File(archive, '${id}_vpl.txt');
    final sql = _readUtf8File(archive, '${id}_vpl.sql');
    _readUtf8File(archive, '${id}_about.htm');

    final textLines = await VplParser()
        .parse(Stream.fromIterable(const LineSplitter().convert(text)))
        .toList();
    final tableName = '${id.replaceAll('-', '_')}_vpl';
    final insertLines = EbibleSqlEnvelope.extractInsertLines(
      expectedTableName: tableName,
      lines: const LineSplitter().convert(sql),
    );
    final metadata = await VplSqlMetadataParser(
      expectedTableName: tableName,
    ).parse(Stream.fromIterable(insertLines)).toList();
    final result = VerseUnitAssembler().assemble(
      textLines: textLines,
      metadata: metadata,
    );
    return NormalizedScriptureSource(
      translation: source.translation,
      units: result.units,
      slots: result.slots,
      provenance: source.provenance,
    );
  }

  String _readUtf8File(Archive archive, String name) {
    final file = archive.find(name);
    if (file == null || !file.isFile) {
      throw FormatException('Required eBible archive file is missing: $name');
    }
    return utf8.decode(file.content, allowMalformed: false);
  }
}

final class EbibleSqlEnvelope {
  const EbibleSqlEnvelope._();

  static List<String> extractInsertLines({
    required String expectedTableName,
    required List<String> lines,
  }) {
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(expectedTableName)) {
      throw ArgumentError.value(expectedTableName, 'expectedTableName');
    }
    final allowed = <String>{
      'USE sofia;',
      'DROP TABLE IF EXISTS sofia.$expectedTableName;',
      'CREATE TABLE $expectedTableName (',
      'verseID VARCHAR(16) NOT NULL PRIMARY KEY,',
      'canon_order VARCHAR(12) NOT NULL,',
      'book VARCHAR(3) NOT NULL,',
      'chapter VARCHAR(3) NOT NULL,',
      'startVerse VARCHAR(3) NOT NULL,',
      'endVerse VARCHAR(3) NOT NULL,',
      'verseText TEXT CHARACTER SET UTF8 NOT NULL) ENGINE=MyISAM;',
      'LOCK TABLES $expectedTableName WRITE;',
      'ALTER TABLE $expectedTableName ADD FULLTEXT(verseText);',
      'UNLOCK TABLES;',
    };
    final inserts = <String>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trim();
      if (line.isEmpty) {
        continue;
      }
      if (line.startsWith('INSERT INTO ')) {
        inserts.add(line);
        continue;
      }
      if (!allowed.contains(line)) {
        throw FormatException(
          'Unexpected SQL envelope line ${index + 1}: $line',
        );
      }
    }
    if (inserts.isEmpty) {
      throw const FormatException('eBible SQL contains no INSERT rows');
    }
    return List.unmodifiable(inserts);
  }
}
