import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

import 'scripture_pack_manifest.dart';
import 'scripture_pack_validator.dart';
import 'sqlite_scripture_repository.dart';

final class ScripturePackInstaller {
  const ScripturePackInstaller({
    required this.applicationSupportDirectory,
    required this.assetBundle,
  });

  final Directory applicationSupportDirectory;
  final AssetBundle assetBundle;

  Future<ScripturePackRegistry> ensureInstalled() async {
    final indexText = await assetBundle.loadString(
      'assets/scripture/index.json',
    );
    final decoded = jsonDecode(indexText);
    if (decoded is! Map<String, Object?> || decoded['schemaVersion'] != 1) {
      throw const ScripturePackIntegrityException('Invalid pack asset index');
    }
    final rawPacks = decoded['packs'];
    if (rawPacks is! List<Object?>) {
      throw const ScripturePackIntegrityException('Invalid pack asset list');
    }
    final root = Directory(
      '${applicationSupportDirectory.path}${Platform.pathSeparator}scripture',
    );
    await root.create(recursive: true);
    final staging = Directory(
      '${root.path}${Platform.pathSeparator}.installing',
    );
    if (await staging.exists()) {
      await staging.delete(recursive: true);
    }
    await staging.create();

    final staged = <String, Directory>{};
    final manifests = <String, ScripturePackManifest>{};
    try {
      for (final rawPack in rawPacks) {
        if (rawPack is! Map<String, Object?>) {
          throw const ScripturePackIntegrityException('Invalid pack index row');
        }
        final id = rawPack['translationId'];
        final expectedManifestHash = rawPack['manifestSha256'];
        if (id is! String ||
            id.isEmpty ||
            expectedManifestHash is! String ||
            !_hashPattern.hasMatch(expectedManifestHash) ||
            staged.containsKey(id)) {
          throw const ScripturePackIntegrityException('Invalid indexed pack');
        }
        final directory = Directory(
          '${staging.path}${Platform.pathSeparator}$id',
        );
        await directory.create();
        for (final name in [
          'manifest.json',
          'scripture.sqlite',
          'LICENSE.txt',
        ]) {
          await _copyAsset(
            'assets/scripture/$id/$name',
            File('${directory.path}${Platform.pathSeparator}$name'),
          );
        }
        final manifestFile = File(
          '${directory.path}${Platform.pathSeparator}manifest.json',
        );
        if (await canonicalManifestSha256(await manifestFile.readAsBytes()) !=
            expectedManifestHash) {
          throw ScripturePackIntegrityException(
            'Manifest digest differs from asset index: $id',
          );
        }
        staged[id] = directory;
        manifests[id] = await ScripturePackManifest.load(manifestFile);
      }
      final semanticHashes = {
        for (final entry in manifests.entries)
          entry.key: entry.value.semanticSha256,
      };
      for (final entry in staged.entries) {
        await ScripturePackValidator().validate(
          entry.value,
          installedSemanticHashes: semanticHashes,
        );
      }

      final installed = <String, Directory>{};
      for (final entry in staged.entries) {
        final manifest = manifests[entry.key]!;
        final target = Directory(
          '${root.path}${Platform.pathSeparator}${manifest.packId}',
        );
        if (!await target.exists()) {
          await entry.value.rename(target.path);
        }
        installed[entry.key] = target;
      }
      await staging.delete(recursive: true);
      return ScripturePackRegistry.fromDirectories(installed);
    } catch (_) {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<void> _copyAsset(String assetPath, File destination) async {
    final data = await assetBundle.load(assetPath);
    await destination.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }
}

Future<String> canonicalManifestSha256(List<int> bytes) async {
  final text = utf8.decode(bytes);
  final canonicalBytes = utf8.encode(
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
  );
  final hash = await Sha256().hash(canonicalBytes);
  return hash.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

final _hashPattern = RegExp(r'^[0-9a-f]{64}$');
