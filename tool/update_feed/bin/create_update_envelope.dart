import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

const _packageName = 'app.biblerecite';
const _certificateSha256 =
    '4066fe3c0e57ec575e5d37b741d68d347f8af80b7cf9da4799636d7039b5a7e7';

Future<void> main(List<String> arguments) async {
  final options = _parseArguments(arguments);
  final privateKey = Platform.environment['UPDATE_MANIFEST_PRIVATE_KEY'];
  if (privateKey == null || privateKey.isEmpty) {
    throw StateError('UPDATE_MANIFEST_PRIVATE_KEY is required.');
  }

  final apk = File(options.apkPath);
  if (!await apk.exists()) {
    throw FileSystemException('APK does not exist.', apk.path);
  }
  final seed = base64Decode(privateKey);
  if (seed.length != 32) {
    throw const FormatException(
      'Update signing key must contain a 32-byte seed.',
    );
  }
  final checksum = options.sha256.toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum)) {
    throw const FormatException('APK SHA-256 must be lowercase hexadecimal.');
  }

  final payload = <String, Object>{
    'versionName': options.versionName,
    'buildNumber': options.buildNumber,
    'sourceCommit': options.sourceCommit,
    'publishedAt': DateTime.now().toUtc().toIso8601String(),
    'releaseNotes': options.releaseNotes,
    'releasePageUrl': options.releasePageUrl,
    'android': {
      'packageName': _packageName,
      'fileName': apk.uri.pathSegments.last,
      'size': await apk.length(),
      'sha256': checksum,
      'signingCertificateSha256': _certificateSha256,
      'urls': [options.downloadUrl],
    },
  };
  final payloadBytes = utf8.encode(jsonEncode(payload));
  final keyPair = await Ed25519().newKeyPairFromSeed(seed);
  final signature = await Ed25519().sign(payloadBytes, keyPair: keyPair);
  final envelope = jsonEncode({
    'protocol': 1,
    'payload': base64Encode(payloadBytes),
    'signature': base64Encode(signature.bytes),
  });
  final output = File(options.outputPath);
  await output.parent.create(recursive: true);
  await output.writeAsString(envelope, flush: true);
}

_EnvelopeOptions _parseArguments(List<String> arguments) {
  final values = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    if (index + 1 >= arguments.length || !arguments[index].startsWith('--')) {
      throw ArgumentError('Expected --name value pairs.');
    }
    values[arguments[index]] = arguments[index + 1];
  }
  String requireValue(String name) {
    final value = values[name];
    if (value == null || value.isEmpty) {
      throw ArgumentError('Missing $name.');
    }
    return value;
  }

  return _EnvelopeOptions(
    apkPath: requireValue('--apk'),
    sha256: requireValue('--sha256'),
    versionName: requireValue('--version-name'),
    buildNumber: requireValue('--build-number'),
    sourceCommit: requireValue('--source-commit'),
    releasePageUrl: requireValue('--release-page-url'),
    downloadUrl: requireValue('--download-url'),
    releaseNotes: values['--release-notes'] ?? '',
    outputPath: requireValue('--output'),
  );
}

final class _EnvelopeOptions {
  const _EnvelopeOptions({
    required this.apkPath,
    required this.sha256,
    required this.versionName,
    required this.buildNumber,
    required this.sourceCommit,
    required this.releasePageUrl,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.outputPath,
  });

  final String apkPath;
  final String sha256;
  final String versionName;
  final String buildNumber;
  final String sourceCommit;
  final String releasePageUrl;
  final String downloadUrl;
  final String releaseNotes;
  final String outputPath;
}
