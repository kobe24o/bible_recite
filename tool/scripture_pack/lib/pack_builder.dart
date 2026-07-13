import 'dart:convert';
import 'dart:io';

import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:cryptography/cryptography.dart';
import 'package:sqlite3/sqlite3.dart';

import 'canon_validator.dart';
import 'pack_manifest.dart';
import 'parallel_mapping_builder.dart';
import 'source_fetcher.dart';
import 'verse_unit_assembler.dart';

final class PackBuildResult {
  const PackBuildResult({
    required this.semanticSha256,
    required this.sqliteSha256,
    required this.unitCount,
    required this.slotCount,
  });

  final String semanticSha256;
  final String sqliteSha256;
  final int unitCount;
  final int slotCount;
}

final class PackSourceEvidence {
  const PackSourceEvidence({
    required this.textSha256,
    required this.aboutSha256,
    required this.retrievalDate,
    this.additionalLicenseNotice = '',
  });

  final String textSha256;
  final String aboutSha256;
  final String retrievalDate;
  final String additionalLicenseNotice;
}

final class PackBuilder {
  Future<PackBuildResult> build({
    required Directory output,
    required SourceDescriptor source,
    required List<ParsedVerseUnit> units,
    required CanonDefinition canon,
    List<ParallelMappingResult> parallelMappings = const [],
    PackSourceEvidence? sourceEvidence,
  }) async {
    _validateInput(source: source, units: units, canon: canon);
    final parent = output.parent;
    await parent.create(recursive: true);
    final temporary = Directory('${output.path}.building');
    final backup = Directory('${output.path}.replaced');
    await _deleteIfPresent(temporary);
    await _deleteIfPresent(backup);
    await temporary.create();

    try {
      final semanticSha256 = await computeSemanticSha256(
        source: source,
        canon: canon,
        units: units,
      );
      for (final mapping in parallelMappings) {
        if (mapping.sourceTranslationId != source.id ||
            mapping.sourceSemanticSha256 != semanticSha256 ||
            mapping.unresolvedSourceKeys.isNotEmpty ||
            mapping.unresolvedTargetKeys.isNotEmpty) {
          throw ArgumentError('Parallel mapping is not valid for this pack');
        }
      }
      final databaseFile = File(
        '${temporary.path}${Platform.pathSeparator}scripture.sqlite',
      );
      _writeDatabase(
        databaseFile,
        source,
        canon,
        units,
        semanticSha256,
        parallelMappings,
      );
      final sqliteSha256 = await _fileHash(databaseFile);
      final evidence =
          sourceEvidence ??
          PackSourceEvidence(
            textSha256: source.sha256,
            aboutSha256: source.sha256,
            retrievalDate: 'not-recorded',
          );
      _validateEvidence(evidence);
      final licenseText = _licenseText(source, evidence);
      final licenseSha256 = await _hashBytes(utf8.encode(licenseText));
      final mappingSha256 = await _mappingHash(parallelMappings);
      final slotCount = units.fold<int>(
        0,
        (sum, unit) => sum + unit.endVerse - unit.startVerse + 1,
      );
      final omittedCount = units
          .where((unit) => unit.status == SourceTextStatus.omitted)
          .fold<int>(
            0,
            (sum, unit) => sum + unit.endVerse - unit.startVerse + 1,
          );
      final bridgeCount = units
          .where((unit) => unit.endVerse > unit.startVerse)
          .length;
      final manifest = PackManifest({
        'canonId': canon.canonId,
        'counts': <String, Object?>{
          'bridgeUnits': bridgeCount,
          'omittedSlots': omittedCount,
          'slots': slotCount,
          'units': units.length,
        },
        'packId': '${source.id}-$semanticSha256',
        'mappingRevision': 'parallel-v1',
        'mappingSha256': mappingSha256,
        'mappingTargets': <Object?>[
          for (final mapping in parallelMappings)
            <String, Object?>{
              'semanticSha256': mapping.targetSemanticSha256,
              'translationId': mapping.targetTranslationId,
            },
        ],
        'schemaVersion': 1,
        'semanticSha256': semanticSha256,
        'source': <String, Object?>{
          'archiveSha256': source.sha256,
          'archiveUrl': source.archiveUrl.toString(),
          'aboutSha256': evidence.aboutSha256,
          'detailsUrl': source.detailsUrl?.toString() ?? '',
          'licenseId': source.licenseId,
          'licenseSha256': licenseSha256,
          'retrievalDate': evidence.retrievalDate,
          'textSha256': evidence.textSha256,
        },
        'sqliteSha256': sqliteSha256,
        'translation': <String, Object?>{
          'id': source.id,
          'languageTag': source.languageTag,
          'name': source.name,
          'versificationId': '${source.id}-v1',
        },
      });
      await File(
        '${temporary.path}${Platform.pathSeparator}manifest.json',
      ).writeAsString(manifest.toCanonicalJson(), flush: true);
      await File(
        '${temporary.path}${Platform.pathSeparator}LICENSE.txt',
      ).writeAsString(licenseText, flush: true);

      if (await output.exists()) {
        await output.rename(backup.path);
      }
      try {
        await temporary.rename(output.path);
      } catch (_) {
        if (await backup.exists() && !await output.exists()) {
          await backup.rename(output.path);
        }
        rethrow;
      }
      await _deleteIfPresent(backup);
      return PackBuildResult(
        semanticSha256: semanticSha256,
        sqliteSha256: sqliteSha256,
        unitCount: units.length,
        slotCount: slotCount,
      );
    } catch (_) {
      await _deleteIfPresent(temporary);
      rethrow;
    }
  }

  void _writeDatabase(
    File file,
    SourceDescriptor source,
    CanonDefinition canon,
    List<ParsedVerseUnit> units,
    String semanticSha256,
    List<ParallelMappingResult> parallelMappings,
  ) {
    final database = sqlite3.open(file.path);
    try {
      database.execute('PRAGMA page_size = 4096');
      database.execute('PRAGMA journal_mode = OFF');
      database.execute('PRAGMA synchronous = OFF');
      database.execute('PRAGMA foreign_keys = ON');
      database.execute('PRAGMA user_version = 1');
      database.execute(_schema);
      database.execute('BEGIN IMMEDIATE');
      try {
        final metadata = <String, String>{
          'canon_id': canon.canonId,
          'schema_version': '1',
          'semantic_sha256': semanticSha256,
          'translation_id': source.id,
          'versification_id': '${source.id}-v1',
        };
        final insertMetadata = database.prepare(
          'INSERT INTO metadata(key, value) VALUES (?, ?)',
        );
        final insertBook = database.prepare(
          'INSERT INTO books(osis_id, ordinal, chapter_count) VALUES (?, ?, ?)',
        );
        final insertUnit = database.prepare(
          'INSERT INTO verse_unit(unit_id, osis_book_id, chapter, start_verse, '
          'end_verse, text, status, source_order) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        );
        final insertSlot = database.prepare(
          'INSERT INTO verse_slot(osis_book_id, chapter, verse, unit_id, '
          'slot_ordinal) VALUES (?, ?, ?, ?, ?)',
        );
        final insertGroup = database.prepare(
          'INSERT INTO parallel_group(group_id, target_translation_id, '
          'target_semantic_sha256, relation, provenance, review_state) '
          'VALUES (?, ?, ?, ?, ?, ?)',
        );
        final insertSourceMember = database.prepare(
          'INSERT INTO parallel_source_member(group_id, osis_book_id, '
          'chapter, verse, ordinal) VALUES (?, ?, ?, ?, ?)',
        );
        final insertTargetMember = database.prepare(
          'INSERT INTO parallel_target_member(group_id, osis_book_id, '
          'chapter, verse, ordinal) VALUES (?, ?, ?, ?, ?)',
        );
        try {
          for (final entry in metadata.entries) {
            insertMetadata.execute([entry.key, entry.value]);
          }
          for (var index = 0; index < canon.books.length; index++) {
            final book = canon.books[index];
            insertBook.execute([book.code, index + 1, book.chapterCount]);
          }
          for (var unitId = 0; unitId < units.length; unitId++) {
            final unit = units[unitId];
            insertUnit.execute([
              unitId + 1,
              unit.bookCode,
              unit.chapter,
              unit.startVerse,
              unit.endVerse,
              unit.text,
              unit.status.name,
              unit.sourceOrder,
            ]);
            for (var verse = unit.startVerse; verse <= unit.endVerse; verse++) {
              insertSlot.execute([
                unit.bookCode,
                unit.chapter,
                verse,
                unitId + 1,
                verse - unit.startVerse,
              ]);
            }
          }
          for (final mapping in parallelMappings) {
            for (final group in mapping.groups) {
              insertGroup.execute([
                group.id,
                mapping.targetTranslationId,
                mapping.targetSemanticSha256,
                group.relation.name,
                group.provenance,
                group.reviewState,
              ]);
              _insertMembers(insertSourceMember, group.id, group.sourceKeys);
              _insertMembers(insertTargetMember, group.id, group.targetKeys);
            }
          }
        } finally {
          insertMetadata.close();
          insertBook.close();
          insertUnit.close();
          insertSlot.close();
          insertGroup.close();
          insertSourceMember.close();
          insertTargetMember.close();
        }
        database.execute('COMMIT');
      } catch (_) {
        database.execute('ROLLBACK');
        rethrow;
      }
      final integrity = database.select('PRAGMA integrity_check');
      if (integrity.length != 1 || integrity.single.values.single != 'ok') {
        throw StateError('SQLite integrity check failed: $integrity');
      }
      database.execute('VACUUM');
    } finally {
      database.close();
    }
  }
}

void _validateInput({
  required SourceDescriptor source,
  required List<ParsedVerseUnit> units,
  required CanonDefinition canon,
}) {
  if (units.isEmpty) {
    throw ArgumentError.value(units, 'units', 'Pack must contain verses');
  }
  final canonBooks = canon.books.map((book) => book.code).toSet();
  var expectedOrder = 0;
  for (final unit in units) {
    if (unit.sourceOrder != expectedOrder ||
        !canonBooks.contains(unit.bookCode) ||
        unit.chapter <= 0 ||
        unit.startVerse <= 0 ||
        unit.endVerse < unit.startVerse ||
        (unit.status == SourceTextStatus.omitted && unit.text.isNotEmpty) ||
        (unit.status == SourceTextStatus.present && unit.text.isEmpty)) {
      throw ArgumentError('Invalid normalized unit at order $expectedOrder');
    }
    expectedOrder++;
  }
  if (source.id.isEmpty) {
    throw ArgumentError.value(source.id, 'source.id');
  }
}

Future<String> computeSemanticSha256({
  required SourceDescriptor source,
  required CanonDefinition canon,
  required List<ParsedVerseUnit> units,
}) async {
  final canonical = PackManifest({
    'canonId': canon.canonId,
    'translationId': source.id,
    'units': units
        .map<Object?>(
          (unit) => <String, Object?>{
            'book': unit.bookCode,
            'chapter': unit.chapter,
            'endVerse': unit.endVerse,
            'sourceOrder': unit.sourceOrder,
            'startVerse': unit.startVerse,
            'status': unit.status.name,
            'text': unit.text,
          },
        )
        .toList(growable: false),
  }).toCanonicalJson();
  return _hashBytes(utf8.encode(canonical));
}

Future<String> _mappingHash(List<ParallelMappingResult> mappings) async {
  final canonical = PackManifest({
    'mappings': mappings
        .map<Object?>(
          (mapping) => <String, Object?>{
            'groups': mapping.groups
                .map<Object?>(
                  (group) => <String, Object?>{
                    'id': group.id,
                    'provenance': group.provenance,
                    'relation': group.relation.name,
                    'reviewState': group.reviewState,
                    'sourceKeys': group.sourceKeys,
                    'targetKeys': group.targetKeys,
                  },
                )
                .toList(growable: false),
            'targetSemanticSha256': mapping.targetSemanticSha256,
            'targetTranslationId': mapping.targetTranslationId,
          },
        )
        .toList(growable: false),
  }).toCanonicalJson();
  return _hashBytes(utf8.encode(canonical));
}

void _validateEvidence(PackSourceEvidence evidence) {
  final hash = RegExp(r'^[0-9a-f]{64}$');
  if (!hash.hasMatch(evidence.textSha256) ||
      !hash.hasMatch(evidence.aboutSha256) ||
      evidence.retrievalDate.isEmpty) {
    throw ArgumentError('Pack source evidence is invalid');
  }
}

void _insertMembers(
  PreparedStatement statement,
  String groupId,
  List<String> keys,
) {
  for (var index = 0; index < keys.length; index++) {
    final parts = keys[index].split('.');
    if (parts.length != 3) {
      throw ArgumentError('Invalid parallel member key: ${keys[index]}');
    }
    statement.execute([
      groupId,
      parts[0],
      int.parse(parts[1]),
      int.parse(parts[2]),
      index,
    ]);
  }
}

Future<String> _fileHash(File file) async {
  final sink = Sha256().newHashSink();
  await for (final chunk in file.openRead()) {
    sink.add(chunk);
  }
  sink.close();
  return _hex((await sink.hash()).bytes);
}

Future<String> _hashBytes(List<int> bytes) async {
  return _hex((await Sha256().hash(bytes)).bytes);
}

String _hex(List<int> bytes) {
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

Future<void> _deleteIfPresent(Directory directory) async {
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }
}

String _licenseText(SourceDescriptor source, PackSourceEvidence evidence) {
  final details = source.detailsUrl?.toString() ?? 'not supplied';
  final additional = evidence.additionalLicenseNotice.isEmpty
      ? ''
      : '${evidence.additionalLicenseNotice}\n';
  return 'Translation: ${source.name}\n'
      'Translation ID: ${source.id}\n'
      'Source page: $details\n'
      'Source archive: ${source.archiveUrl}\n'
      'Archive SHA-256: ${source.sha256}\n'
      'Retrieval date: ${evidence.retrievalDate}\n'
      'License: ${source.licenseId}\n'
      '$additional';
}

const _schema = '''
CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE books (
  osis_id TEXT PRIMARY KEY,
  ordinal INTEGER NOT NULL UNIQUE,
  chapter_count INTEGER NOT NULL CHECK (chapter_count > 0)
);
CREATE TABLE verse_unit (
  unit_id INTEGER PRIMARY KEY,
  osis_book_id TEXT NOT NULL REFERENCES books(osis_id),
  chapter INTEGER NOT NULL CHECK (chapter > 0),
  start_verse INTEGER NOT NULL CHECK (start_verse > 0),
  end_verse INTEGER NOT NULL CHECK (end_verse >= start_verse),
  text TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('present', 'omitted')),
  source_order INTEGER NOT NULL UNIQUE,
  UNIQUE (osis_book_id, chapter, start_verse, end_verse)
);
CREATE TABLE verse_slot (
  osis_book_id TEXT NOT NULL,
  chapter INTEGER NOT NULL,
  verse INTEGER NOT NULL,
  unit_id INTEGER NOT NULL REFERENCES verse_unit(unit_id),
  slot_ordinal INTEGER NOT NULL,
  PRIMARY KEY (osis_book_id, chapter, verse)
);
CREATE TABLE parallel_group (
  group_id TEXT PRIMARY KEY,
  target_translation_id TEXT NOT NULL,
  target_semantic_sha256 TEXT NOT NULL,
  relation TEXT NOT NULL,
  provenance TEXT NOT NULL,
  review_state TEXT NOT NULL CHECK (review_state IN ('automatic', 'approved'))
);
CREATE TABLE parallel_source_member (
  group_id TEXT NOT NULL REFERENCES parallel_group(group_id),
  osis_book_id TEXT NOT NULL,
  chapter INTEGER NOT NULL,
  verse INTEGER NOT NULL,
  ordinal INTEGER NOT NULL,
  PRIMARY KEY (group_id, ordinal)
);
CREATE TABLE parallel_target_member (
  group_id TEXT NOT NULL REFERENCES parallel_group(group_id),
  osis_book_id TEXT NOT NULL,
  chapter INTEGER NOT NULL,
  verse INTEGER NOT NULL,
  ordinal INTEGER NOT NULL,
  PRIMARY KEY (group_id, ordinal)
);
CREATE INDEX verse_unit_chapter_idx
  ON verse_unit(osis_book_id, chapter, start_verse);
''';
