import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../data/resumable_downloader.dart';
import '../data/update_feed_client.dart';
import '../data/update_signing_public_key.dart';
import '../data/update_verifier.dart';
import '../domain/app_version.dart';
import '../domain/update_manifest.dart';
import '../domain/update_status.dart';
import '../platform/android_update_bridge.dart';

enum UpdateRuntimePlatform { android, other }

typedef UpdateManifestLoader = Future<UpdateManifest> Function();
typedef UpdateNetworkTransport = Future<String> Function();
typedef UpdateDownloadOperation =
    Future<DownloadedUpdate> Function(
      AndroidUpdateAsset asset,
      Directory directory, {
      required void Function(DownloadProgress) onProgress,
      required DownloadCancellation cancellation,
    });
typedef UpdateFileVerification =
    Future<void> Function(File file, AndroidUpdateAsset asset);
typedef UpdateApkInspection = Future<AndroidApkInfo> Function(File file);
typedef UpdatePackageVerification =
    Future<void> Function(
      AndroidApkInfo apk,
      UpdateManifest manifest,
      AppVersion installedVersion,
    );
typedef UpdateApkStaging =
    Future<File> Function(
      File file,
      AndroidUpdateAsset asset,
      Directory directory,
    );
typedef UpdateInstallPermission = Future<bool> Function();
typedef UpdateOpenInstallPermission = Future<void> Function();
typedef UpdateApkInstall = Future<void> Function(File file);

final class UpdateConfigurationException implements Exception {
  const UpdateConfigurationException(this.reasonCode);

  final String reasonCode;
}

final class UpdateStagingException implements Exception {
  const UpdateStagingException(this.reasonCode);

  final String reasonCode;
}

const _r2PublicBaseUrl = String.fromEnvironment('R2_PUBLIC_BASE_URL');
const _feedTimeout = Duration(seconds: 15);
const _maximumFeedBytes = 1024 * 1024;

Uri parseR2PublicBaseUrl(String value) {
  if (value.trim().isEmpty) {
    throw const UpdateConfigurationException(
      UpdateFailureReason.r2PublicBaseUrlMissing,
    );
  }
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.hasFragment ||
      uri.hasQuery) {
    throw const UpdateConfigurationException(
      UpdateFailureReason.r2PublicBaseUrlInvalid,
    );
  }
  return uri;
}

final updateRuntimePlatformProvider = Provider<UpdateRuntimePlatform>(
  (ref) => Platform.isAndroid
      ? UpdateRuntimePlatform.android
      : UpdateRuntimePlatform.other,
);

final installedPackageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

final installedAppVersionProvider = FutureProvider<AppVersion>((ref) async {
  final info = await ref.watch(installedPackageInfoProvider.future);
  return AppVersion.parse(info.version, info.buildNumber);
});

final updateR2PublicBaseUrlProvider = Provider<Uri>(
  (ref) => parseR2PublicBaseUrl(_r2PublicBaseUrl),
);

final updateFeedSourcesProvider = Provider<List<Uri>>(
  (ref) => buildUpdateFeedSources(
    r2PublicBaseUrl: ref.watch(updateR2PublicBaseUrlProvider),
  ),
);

final updateFeedTransportProvider = Provider<UpdateBytesTransport>(
  (ref) => const _IoUpdateBytesTransport(),
);

final updateFeedClientProvider = Provider<UpdateFeedClient>(
  (ref) => UpdateFeedClient(
    sources: ref.watch(updateFeedSourcesProvider),
    transport: ref.watch(updateFeedTransportProvider),
    publicKey: updateSigningPublicKey,
  ),
);

final updateManifestLoaderProvider = Provider<UpdateManifestLoader>(
  (ref) => ref.watch(updateFeedClientProvider).fetchLatest,
);

final updateDownloadDirectoryProvider = FutureProvider<Directory>((ref) async {
  final support = await getApplicationSupportDirectory();
  return Directory('${support.path}${Platform.pathSeparator}updates');
});

final updateStagingDirectoryProvider = FutureProvider<Directory>((ref) async {
  final temporary = await getTemporaryDirectory();
  return Directory('${temporary.path}${Platform.pathSeparator}updates');
});

final resumableDownloaderProvider = Provider<ResumableDownloader>(
  (ref) => ResumableDownloader(),
);

final updateDownloadOperationProvider = Provider<UpdateDownloadOperation>(
  (ref) => ref.watch(resumableDownloaderProvider).download,
);

final updateVerifierProvider = Provider<UpdateVerifier>(
  (ref) => UpdateVerifier(),
);

final updateFileVerificationProvider = Provider<UpdateFileVerification>(
  (ref) => ref.watch(updateVerifierProvider).verifyFile,
);

final updatePackageVerificationProvider = Provider<UpdatePackageVerification>((
  ref,
) {
  final verifier = ref.watch(updateVerifierProvider);
  return (apk, manifest, installedVersion) => verifier.verifyAndroidPackage(
    apk: apk,
    manifest: manifest,
    installedVersion: installedVersion,
  );
});

final androidUpdateBridgeProvider = Provider<AndroidUpdateBridge>(
  (ref) => const AndroidUpdateBridge(),
);

final updateNetworkTransportProvider = Provider<UpdateNetworkTransport>(
  (ref) => ref.watch(androidUpdateBridgeProvider).networkTransport,
);

final updateApkInspectionProvider = Provider<UpdateApkInspection>(
  (ref) => ref.watch(androidUpdateBridgeProvider).inspectApk,
);

final updateInstallPermissionProvider = Provider<UpdateInstallPermission>(
  (ref) => ref.watch(androidUpdateBridgeProvider).canRequestPackageInstalls,
);

final updateOpenInstallPermissionProvider =
    Provider<UpdateOpenInstallPermission>(
      (ref) => ref.watch(androidUpdateBridgeProvider).openInstallPermission,
    );

final updateApkInstallProvider = Provider<UpdateApkInstall>(
  (ref) => ref.watch(androidUpdateBridgeProvider).installApk,
);

final updateApkStagingProvider = Provider<UpdateApkStaging>(
  (ref) => stageVerifiedUpdateApk,
);

Future<File> stageVerifiedUpdateApk(
  File source,
  AndroidUpdateAsset asset,
  Directory stagingDirectory,
) async {
  if (!_isSinglePathSegment(asset.fileName)) {
    throw const UpdateStagingException('invalid_staging_filename');
  }
  if (!await source.exists() || await source.length() != asset.size) {
    throw const UpdateStagingException('invalid_staging_source');
  }

  await stagingDirectory.create(recursive: true);
  final canonicalDirectory = Directory(
    await stagingDirectory.resolveSymbolicLinks(),
  );
  final destination = File(
    '${canonicalDirectory.path}${Platform.pathSeparator}${asset.fileName}',
  );
  final temporary = File('${destination.path}.staging');
  if (await temporary.exists()) {
    await temporary.delete();
  }

  final hashSink = Sha256().newHashSink();
  final output = temporary.openWrite(mode: FileMode.writeOnly);
  var copiedBytes = 0;
  try {
    await for (final chunk in source.openRead()) {
      copiedBytes += chunk.length;
      if (copiedBytes > asset.size) {
        throw const UpdateStagingException('staged_size_mismatch');
      }
      hashSink.add(chunk);
      output.add(chunk);
    }
    await output.flush();
  } finally {
    await output.close();
    hashSink.close();
  }

  try {
    final digest = await hashSink.hash();
    if (copiedBytes != asset.size ||
        _hexFromBytes(digest.bytes) != asset.sha256) {
      throw const UpdateStagingException('staged_hash_mismatch');
    }

    if (await destination.exists()) {
      final existingParent = await destination.parent.resolveSymbolicLinks();
      if (existingParent != canonicalDirectory.path) {
        throw const UpdateStagingException('invalid_staging_destination');
      }
      await destination.delete();
    }
    final staged = await temporary.rename(destination.path);
    final canonicalStaged = File(await staged.resolveSymbolicLinks());
    final canonicalParent = await canonicalStaged.parent.resolveSymbolicLinks();
    if (canonicalParent != canonicalDirectory.path ||
        canonicalStaged.path != destination.path) {
      await _deleteIfExists(staged);
      throw const UpdateStagingException('invalid_staging_destination');
    }
    return staged;
  } finally {
    await _deleteIfExists(temporary);
  }
}

bool _isSinglePathSegment(String value) =>
    value.isNotEmpty &&
    value != '.' &&
    value != '..' &&
    !value.contains('/') &&
    !value.contains(r'\');

String _hexFromBytes(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}

final class _IoUpdateBytesTransport implements UpdateBytesTransport {
  const _IoUpdateBytesTransport();

  @override
  Future<List<int>> get(Uri uri) async {
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('Update feed URL must use HTTPS');
    }
    final client = HttpClient()..connectionTimeout = _feedTimeout;
    try {
      final request = await client.getUrl(uri).timeout(_feedTimeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(_feedTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Unexpected HTTP status ${response.statusCode}');
      }
      if (response.contentLength > _maximumFeedBytes) {
        throw const FormatException('Update feed is too large');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(_feedTimeout)) {
        bytes.addAll(chunk);
        if (bytes.length > _maximumFeedBytes) {
          throw const FormatException('Update feed is too large');
        }
      }
      return bytes;
    } finally {
      client.close(force: true);
    }
  }
}
