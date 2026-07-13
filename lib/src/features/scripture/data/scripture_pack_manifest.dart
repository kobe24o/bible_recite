import 'dart:convert';
import 'dart:io';

import '../domain/scripture_models.dart';

final class ScripturePackManifest {
  ScripturePackManifest({
    required this.packId,
    required this.translation,
    required this.canonId,
    required this.schemaVersion,
    required this.semanticSha256,
    required this.sqliteSha256,
    required this.mappingSha256,
    required Map<String, String> mappingTargets,
  }) : mappingTargets = Map.unmodifiable(mappingTargets);

  final String packId;
  final TranslationInfo translation;
  final CanonId canonId;
  final int schemaVersion;
  final String semanticSha256;
  final String sqliteSha256;
  final String mappingSha256;
  final Map<String, String> mappingTargets;

  static Future<ScripturePackManifest> load(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Scripture manifest root is invalid');
    }
    final translation = _map(decoded, 'translation');
    final semanticSha256 = _hash(decoded, 'semanticSha256');
    final canonName = _string(decoded, 'canonId');
    final canonId = CanonId.values
        .where((value) => value.name == canonName)
        .firstOrNull;
    final rawTargets = decoded['mappingTargets'];
    if (canonId == null || rawTargets is! List<Object?>) {
      throw const FormatException('Scripture manifest metadata is invalid');
    }
    final targets = <String, String>{};
    for (final rawTarget in rawTargets) {
      if (rawTarget is! Map<String, Object?>) {
        throw const FormatException('Mapping target is invalid');
      }
      final id = _string(rawTarget, 'translationId');
      if (targets.containsKey(id)) {
        throw const FormatException('Duplicate mapping target');
      }
      targets[id] = _hash(rawTarget, 'semanticSha256');
    }
    final schemaVersion = decoded['schemaVersion'];
    if (schemaVersion is! int || schemaVersion != 1) {
      throw const FormatException('Unsupported scripture schema');
    }
    return ScripturePackManifest(
      packId: _string(decoded, 'packId'),
      translation: TranslationInfo(
        id: _string(translation, 'id'),
        languageTag: _string(translation, 'languageTag'),
        name: _string(translation, 'name'),
        canonId: canonId,
        packId: _string(decoded, 'packId'),
        versificationId: _string(translation, 'versificationId'),
        semanticSha256: semanticSha256,
      ),
      canonId: canonId,
      schemaVersion: schemaVersion,
      semanticSha256: semanticSha256,
      sqliteSha256: _hash(decoded, 'sqliteSha256'),
      mappingSha256: _hash(decoded, 'mappingSha256'),
      mappingTargets: targets,
    );
  }
}

Map<String, Object?> _map(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('Manifest field $key is invalid');
  }
  return value;
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Manifest field $key is invalid');
  }
  return value;
}

String _hash(Map<String, Object?> json, String key) {
  final value = _string(json, key);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw FormatException('Manifest hash $key is invalid');
  }
  return value;
}
