import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:sqlite3/sqlite3.dart';

import 'scripture_pack_manifest.dart';

final class ScripturePackIntegrityException implements Exception {
  const ScripturePackIntegrityException(this.message);

  final String message;

  @override
  String toString() => 'ScripturePackIntegrityException: $message';
}

final class ScripturePackValidator {
  Future<ScripturePackManifest> validate(
    Directory directory, {
    Map<String, String>? installedSemanticHashes,
  }) async {
    try {
      final manifest = await ScripturePackManifest.load(
        File('${directory.path}${Platform.pathSeparator}manifest.json'),
      );
      final databaseFile = File(
        '${directory.path}${Platform.pathSeparator}scripture.sqlite',
      );
      if (!await databaseFile.exists() ||
          await _sha256(databaseFile) != manifest.sqliteSha256) {
        throw const ScripturePackIntegrityException(
          'SQLite digest does not match manifest',
        );
      }
      if (installedSemanticHashes != null) {
        for (final entry in manifest.mappingTargets.entries) {
          if (installedSemanticHashes[entry.key] != entry.value) {
            throw ScripturePackIntegrityException(
              'Mapping target revision is unavailable or stale: ${entry.key}',
            );
          }
        }
      }
      final database = sqlite3.open(databaseFile.path, mode: OpenMode.readOnly);
      try {
        final integrity = database.select('PRAGMA integrity_check');
        final semantic = database.select(
          "SELECT value FROM metadata WHERE key = 'semantic_sha256'",
        );
        if (integrity.length != 1 ||
            integrity.single.values.single != 'ok' ||
            semantic.length != 1 ||
            semantic.single['value'] != manifest.semanticSha256) {
          throw const ScripturePackIntegrityException(
            'SQLite content metadata is invalid',
          );
        }
        for (final row in database.select(
          'SELECT DISTINCT target_translation_id, target_semantic_sha256 '
          'FROM parallel_group',
        )) {
          final id = row['target_translation_id'] as String;
          final hash = row['target_semantic_sha256'] as String;
          if (manifest.mappingTargets[id] != hash) {
            throw ScripturePackIntegrityException(
              'Embedded mapping revision is stale: $id',
            );
          }
        }
      } finally {
        database.close();
      }
      return manifest;
    } on ScripturePackIntegrityException {
      rethrow;
    } catch (error) {
      throw ScripturePackIntegrityException('Invalid scripture pack: $error');
    }
  }
}

Future<String> _sha256(File file) async {
  final sink = Sha256().newHashSink();
  await for (final chunk in file.openRead()) {
    sink.add(chunk);
  }
  sink.close();
  return (await sink.hash()).bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}
