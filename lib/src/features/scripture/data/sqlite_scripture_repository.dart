import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../domain/scripture_models.dart';
import '../domain/scripture_repository.dart';
import 'scripture_pack_manifest.dart';
import 'scripture_pack_validator.dart';

final class TranslationNotFound implements Exception {
  const TranslationNotFound(this.translationId);
  final String translationId;
}

final class PassageNotFound implements Exception {
  const PassageNotFound(this.reference);
  final String reference;
}

final class ParallelMappingUnavailable implements Exception {
  const ParallelMappingUnavailable(this.message);
  final String message;
}

final class ScripturePackRegistry {
  ScripturePackRegistry._(this._entries);

  final Map<String, ScripturePackRegistryEntry> _entries;

  static Future<ScripturePackRegistry> fromDirectories(
    Map<String, Directory> directories,
  ) async {
    final manifests = <String, ScripturePackManifest>{};
    for (final entry in directories.entries) {
      final manifest = await ScripturePackManifest.load(
        File('${entry.value.path}${Platform.pathSeparator}manifest.json'),
      );
      if (manifest.translation.id != entry.key) {
        throw const ScripturePackIntegrityException(
          'Registry translation ID does not match manifest',
        );
      }
      manifests[entry.key] = manifest;
    }
    final semanticHashes = {
      for (final entry in manifests.entries)
        entry.key: entry.value.semanticSha256,
    };
    final entries = <String, ScripturePackRegistryEntry>{};
    for (final entry in directories.entries) {
      final manifest = await ScripturePackValidator().validate(
        entry.value,
        installedSemanticHashes: semanticHashes,
      );
      entries[entry.key] = ScripturePackRegistryEntry(
        directory: entry.value,
        manifest: manifest,
      );
    }
    return ScripturePackRegistry._(Map.unmodifiable(entries));
  }

  Iterable<ScripturePackRegistryEntry> get entries => _entries.values;

  ScripturePackRegistryEntry require(String translationId) {
    final entry = _entries[translationId];
    if (entry == null) {
      throw TranslationNotFound(translationId);
    }
    return entry;
  }

  String databasePath(String translationId) {
    final directory = require(translationId).directory;
    return '${directory.path}${Platform.pathSeparator}scripture.sqlite';
  }
}

final class ScripturePackRegistryEntry {
  const ScripturePackRegistryEntry({
    required this.directory,
    required this.manifest,
  });

  final Directory directory;
  final ScripturePackManifest manifest;
}

final class SqliteScriptureRepository implements ScriptureRepository {
  const SqliteScriptureRepository({required this.registry});

  final ScripturePackRegistry registry;

  Database _open(String translationId) => sqlite3.open(
    registry.databasePath(translationId),
    mode: OpenMode.readOnly,
  );

  @override
  Future<List<TranslationInfo>> listTranslations() async {
    final translations = registry.entries
        .map((entry) => entry.manifest.translation)
        .toList(growable: false);
    translations.sort((left, right) => left.id.compareTo(right.id));
    return translations;
  }

  @override
  Future<TranslationInfo> getTranslation(String id) async {
    return registry.require(id).manifest.translation;
  }

  @override
  Future<List<BibleBook>> listBooks(
    String translationId,
    CanonId canonId,
  ) async {
    final entry = registry.require(translationId);
    if (entry.manifest.canonId != canonId) {
      return const [];
    }
    final database = _open(translationId);
    try {
      return database
          .select(
            'SELECT osis_id, ordinal, chapter_count FROM books ORDER BY ordinal',
          )
          .map(
            (row) => BibleBook(
              osisId: row['osis_id'] as String,
              ordinal: row['ordinal'] as int,
              name: row['osis_id'] as String,
              chapterCount: row['chapter_count'] as int,
            ),
          )
          .toList(growable: false);
    } finally {
      database.close();
    }
  }

  @override
  Future<List<VerseUnit>> getChapter(
    String translationId,
    String osisBookId,
    int chapter,
  ) async {
    final database = _open(translationId);
    try {
      final rows = database.select(
        'SELECT start_verse, end_verse, text, status FROM verse_unit '
        'WHERE osis_book_id = ? AND chapter = ? ORDER BY source_order',
        [osisBookId, chapter],
      );
      if (rows.isEmpty) {
        throw PassageNotFound('$osisBookId $chapter');
      }
      return rows
          .map((row) => _unitFromRow(translationId, osisBookId, chapter, row))
          .toList(growable: false);
    } finally {
      database.close();
    }
  }

  @override
  Future<Passage> getPassage(String translationId, PassageRange range) async {
    registry.require(translationId);
    final database = _open(translationId);
    try {
      final units = _queryRange(database, translationId, range);
      if (units.isEmpty) {
        throw PassageNotFound(range.toString());
      }
      return Passage(range: range, translationId: translationId, units: units);
    } finally {
      database.close();
    }
  }

  @override
  Future<SelectedPassage> getSelection(
    String translationId,
    PassageSelection selection,
  ) async {
    final passages = <Passage>[];
    for (final range in selection.ranges) {
      passages.add(await getPassage(translationId, range));
    }
    return SelectedPassage(
      selection: selection,
      translationId: translationId,
      passages: passages,
    );
  }

  @override
  Future<ParallelPassage> resolveParallelPassage(
    LocatedPassageRange sourceRange,
    String targetTranslationId,
  ) async {
    final sourceEntry = registry.require(sourceRange.translationId);
    final targetEntry = registry.require(targetTranslationId);
    if (sourceEntry.manifest.mappingTargets[targetTranslationId] !=
        targetEntry.manifest.semanticSha256) {
      throw ParallelMappingUnavailable(
        'No current mapping from ${sourceRange.translationId} to '
        '$targetTranslationId',
      );
    }
    final sourceDatabase = _open(sourceRange.translationId);
    final targetDatabase = _open(targetTranslationId);
    try {
      final selectedUnits = _queryRange(
        sourceDatabase,
        sourceRange.translationId,
        sourceRange.range,
      );
      if (selectedUnits.isEmpty) {
        throw PassageNotFound(sourceRange.range.toString());
      }
      final groupIds = <String>{};
      for (final unit in selectedUnits) {
        final rows = sourceDatabase.select(
          'SELECT g.group_id FROM parallel_group g '
          'JOIN parallel_source_member m ON m.group_id = g.group_id '
          'WHERE g.target_translation_id = ? AND m.osis_book_id = ? '
          'AND m.chapter = ? AND m.verse = ?',
          [
            targetTranslationId,
            unit.start.osisBookId,
            unit.start.chapter,
            unit.start.verse,
          ],
        );
        groupIds.addAll(rows.map((row) => row['group_id'] as String));
      }
      if (groupIds.isEmpty) {
        throw const ParallelMappingUnavailable(
          'Selected passage has no reviewed mapping groups',
        );
      }
      final groups = <ParallelGroup>[];
      final warnings = <String>[];
      for (final groupId in groupIds) {
        final groupRow = sourceDatabase.select(
          'SELECT relation, provenance FROM parallel_group WHERE group_id = ?',
          [groupId],
        ).single;
        final sourceKeys = _memberKeys(
          sourceDatabase,
          'parallel_source_member',
          groupId,
        );
        final targetKeys = _memberKeys(
          sourceDatabase,
          'parallel_target_member',
          groupId,
        );
        final sourceUnits = sourceKeys
            .map(
              (key) => _loadExactUnit(
                sourceDatabase,
                sourceRange.translationId,
                key,
              ),
            )
            .toList(growable: false);
        final targetUnits = targetKeys
            .map(
              (key) => _loadExactUnit(targetDatabase, targetTranslationId, key),
            )
            .toList(growable: false);
        if (sourceUnits.any(
          (unit) => !_rangeContainsUnit(sourceRange.range, unit),
        )) {
          warnings.add('rangeExpanded:$groupId');
        }
        groups.add(
          ParallelGroup(
            id: groupId,
            sourceUnits: sourceUnits,
            targetUnits: targetUnits,
            relation: ParallelRelation.values.byName(
              groupRow['relation'] as String,
            ),
            provenance: groupRow['provenance'] as String,
          ),
        );
      }
      return ParallelPassage(
        sourceRange: sourceRange,
        targetTranslationId: targetTranslationId,
        groups: groups,
        warnings: warnings,
      );
    } finally {
      sourceDatabase.close();
      targetDatabase.close();
    }
  }
}

List<VerseUnit> _queryRange(
  Database database,
  String translationId,
  PassageRange range,
) {
  final rows = database.select(
    'SELECT DISTINCT u.source_order, u.osis_book_id, u.chapter, '
    'u.start_verse, u.end_verse, u.text, u.status FROM verse_slot s '
    'JOIN verse_unit u ON u.unit_id = s.unit_id '
    'WHERE s.osis_book_id = ? '
    'AND (s.chapter > ? OR (s.chapter = ? AND s.verse >= ?)) '
    'AND (s.chapter < ? OR (s.chapter = ? AND s.verse <= ?)) '
    'ORDER BY u.source_order',
    [
      range.start.osisBookId,
      range.start.chapter,
      range.start.chapter,
      range.start.verse,
      range.end.chapter,
      range.end.chapter,
      range.end.verse,
    ],
  );
  return rows
      .map(
        (row) => _unitFromRow(
          translationId,
          row['osis_book_id'] as String,
          row['chapter'] as int,
          row,
        ),
      )
      .toList(growable: false);
}

VerseUnit _unitFromRow(
  String translationId,
  String bookId,
  int chapter,
  Row row,
) {
  return VerseUnit(
    translationId: translationId,
    start: (
      canonId: CanonId.protestant66,
      osisBookId: bookId,
      chapter: chapter,
      verse: row['start_verse'] as int,
    ),
    end: (
      canonId: CanonId.protestant66,
      osisBookId: bookId,
      chapter: chapter,
      verse: row['end_verse'] as int,
    ),
    text: row['text'] as String,
    status: SourceTextStatus.values.byName(row['status'] as String),
  );
}

List<({String book, int chapter, int verse})> _memberKeys(
  Database database,
  String table,
  String groupId,
) {
  if (table != 'parallel_source_member' && table != 'parallel_target_member') {
    throw ArgumentError.value(table, 'table');
  }
  return database
      .select(
        'SELECT osis_book_id, chapter, verse FROM $table '
        'WHERE group_id = ? ORDER BY ordinal',
        [groupId],
      )
      .map(
        (row) => (
          book: row['osis_book_id'] as String,
          chapter: row['chapter'] as int,
          verse: row['verse'] as int,
        ),
      )
      .toList(growable: false);
}

VerseUnit _loadExactUnit(
  Database database,
  String translationId,
  ({String book, int chapter, int verse}) key,
) {
  final rows = database.select(
    'SELECT start_verse, end_verse, text, status FROM verse_unit '
    'WHERE osis_book_id = ? AND chapter = ? AND start_verse = ?',
    [key.book, key.chapter, key.verse],
  );
  if (rows.length != 1) {
    throw PassageNotFound('${key.book} ${key.chapter}:${key.verse}');
  }
  return _unitFromRow(translationId, key.book, key.chapter, rows.single);
}

bool _rangeContainsUnit(PassageRange range, VerseUnit unit) {
  final startsAfterOrAt =
      unit.start.chapter > range.start.chapter ||
      (unit.start.chapter == range.start.chapter &&
          unit.start.verse >= range.start.verse);
  final endsBeforeOrAt =
      unit.end.chapter < range.end.chapter ||
      (unit.end.chapter == range.end.chapter &&
          unit.end.verse <= range.end.verse);
  return startsAfterOrAt && endsBeforeOrAt;
}
