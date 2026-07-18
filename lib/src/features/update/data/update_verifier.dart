import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../domain/update_manifest.dart';
import '../domain/app_version.dart';
import '../platform/android_update_bridge.dart';

final class UpdateVerificationException implements Exception {
  const UpdateVerificationException(this.reason);

  final String reason;
}

final class UpdateVerifier {
  Future<void> verifyFile(File file, AndroidUpdateAsset asset) async {
    try {
      if (!await file.exists() || await file.length() != asset.size) {
        throw const UpdateVerificationException('size_mismatch');
      }

      final sink = Sha256().newHashSink();
      await for (final chunk in file.openRead()) {
        sink.add(chunk);
      }
      sink.close();
      final digest = await sink.hash();
      if (_hexFromBytes(digest.bytes) != asset.sha256) {
        throw const UpdateVerificationException('sha256_mismatch');
      }
    } on UpdateVerificationException {
      await _deleteFailedDownload(file);
      rethrow;
    }
  }

  Future<void> verifyAndroidPackage({
    required AndroidApkInfo apk,
    required UpdateManifest manifest,
    required AppVersion installedVersion,
  }) async {
    if (apk.packageName != manifest.android.packageName) {
      throw const UpdateVerificationException('package_name_mismatch');
    }
    if (apk.certificateSha256 != manifest.android.signingCertificateSha256) {
      throw const UpdateVerificationException('certificate_mismatch');
    }

    final signedVersionName =
        '${manifest.version.major}.${manifest.version.minor}.${manifest.version.patch}';
    if (apk.versionName != signedVersionName ||
        apk.versionCode != manifest.version.buildNumber) {
      throw const UpdateVerificationException('version_mismatch');
    }
    if (!manifest.version.isNewerThan(installedVersion)) {
      throw const UpdateVerificationException('not_newer');
    }
  }
}

String _hexFromBytes(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Future<void> _deleteFailedDownload(File file) async {
  for (final candidate in [
    file,
    File('${file.path}.part'),
    File('${file.path}.part.json'),
  ]) {
    if (await candidate.exists()) {
      await candidate.delete();
    }
  }
}
