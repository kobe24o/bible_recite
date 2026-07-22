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
typedef UpdateCompletedDownloadCleanup = Future<void> Function(File file);
typedef UpdateStagingCopy =
    Future<void> Function(File source, RandomAccessFile output);
typedef UpdateStagingAfterCopy = Future<void> Function(File reserved);
typedef UpdateFinalFileNameForAttempt =
    String Function(String stem, String token, int attempt);
typedef UpdateDirectoryCanonicalizer =
    Future<Directory> Function(Directory directory);

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

final updateTemporaryDirectoryProvider = FutureProvider<Directory>(
  (ref) => getTemporaryDirectory(),
);

final updateStagingDirectoryProvider = FutureProvider<Directory>((ref) async {
  final temporary = await ref.watch(updateTemporaryDirectoryProvider.future);
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

final updateCompletedDownloadCleanupProvider =
    Provider<UpdateCompletedDownloadCleanup>((ref) => _deleteCompletedDownload);

Future<File> stageVerifiedUpdateApk(
  File source,
  AndroidUpdateAsset asset,
  Directory temporaryDirectory, {
  UpdateStagingCopy copyToReservedFile = _copyToReservedFile,
  UpdateStagingAfterCopy? afterCopy,
  UpdateFinalFileNameForAttempt finalFileNameForAttempt =
      _finalFileNameForAttempt,
  UpdateStagingCopy copyPendingToFinal = _copyToReservedFile,
  UpdateStagingAfterCopy? afterFinalCopy,
  UpdateDirectoryCanonicalizer canonicalizeOwnedDirectory =
      _canonicalizeDirectory,
}) async {
  if (!_isSinglePathSegment(asset.fileName)) {
    throw const UpdateStagingException('invalid_staging_filename');
  }
  if (!await source.exists() || await source.length() != asset.size) {
    throw const UpdateStagingException('invalid_staging_source');
  }

  await temporaryDirectory.create(recursive: true);
  final temporaryType = await FileSystemEntity.type(
    temporaryDirectory.path,
    followLinks: false,
  );
  if (temporaryType != FileSystemEntityType.directory) {
    throw const UpdateStagingException('invalid_temporary_root');
  }
  final canonicalTemporary = await _canonicalizeDirectory(temporaryDirectory);
  final updates = Directory(
    '${canonicalTemporary.path}${Platform.pathSeparator}updates',
  );
  var updatesType = await FileSystemEntity.type(
    updates.path,
    followLinks: false,
  );
  if (updatesType == FileSystemEntityType.notFound) {
    await updates.create();
    updatesType = await FileSystemEntity.type(updates.path, followLinks: false);
  }
  if (updatesType != FileSystemEntityType.directory) {
    throw const UpdateStagingException('invalid_staging_root');
  }
  final canonicalUpdates = await _canonicalizeDirectory(updates);
  final expectedUpdatesPath =
      '${canonicalTemporary.path}${Platform.pathSeparator}updates';
  if (canonicalUpdates.path != expectedUpdatesPath ||
      await canonicalUpdates.parent.resolveSymbolicLinks() !=
          canonicalTemporary.path) {
    throw const UpdateStagingException('invalid_staging_root');
  }

  final ownedDirectory = await canonicalTemporary.createTemp('.update-stage-');
  File? ownedFinal;
  var succeeded = false;
  try {
    final canonicalOwnedDirectory = await canonicalizeOwnedDirectory(
      ownedDirectory,
    );
    if (await canonicalOwnedDirectory.parent.resolveSymbolicLinks() !=
        canonicalTemporary.path) {
      throw const UpdateStagingException('invalid_staging_destination');
    }
    final pending = File(
      '${canonicalOwnedDirectory.path}${Platform.pathSeparator}candidate.pending',
    );
    await _copyAndFlush(
      source: source,
      destination: pending,
      copy: copyToReservedFile,
    );
    await afterCopy?.call(pending);
    final pendingDigest = await _hashFile(pending);
    if (pendingDigest.$1 != asset.size || pendingDigest.$2 != asset.sha256) {
      throw const UpdateStagingException('staged_hash_mismatch');
    }

    final token = _lastPathSegment(canonicalOwnedDirectory.path);
    final stem = asset.fileName.substring(0, asset.fileName.length - 4);
    for (var attempt = 0; attempt < 32; attempt++) {
      final fileName = finalFileNameForAttempt(stem, token, attempt);
      if (!_isSinglePathSegment(fileName) || !fileName.endsWith('.apk')) {
        throw const UpdateStagingException('invalid_final_filename');
      }
      final candidate = File(
        '${canonicalUpdates.path}${Platform.pathSeparator}$fileName',
      );
      try {
        ownedFinal = await candidate.create(exclusive: true);
        break;
      } on FileSystemException {
        if (await FileSystemEntity.type(candidate.path, followLinks: false) ==
            FileSystemEntityType.notFound) {
          rethrow;
        }
      }
    }
    final finalFile = ownedFinal;
    if (finalFile == null) {
      throw const UpdateStagingException('final_reservation_failed');
    }
    await _copyAndFlush(
      source: pending,
      destination: finalFile,
      copy: copyPendingToFinal,
    );
    await afterFinalCopy?.call(finalFile);
    final finalDigest = await _hashFile(finalFile);
    if (finalDigest.$1 != asset.size || finalDigest.$2 != asset.sha256) {
      throw const UpdateStagingException('final_hash_mismatch');
    }
    if (await FileSystemEntity.type(finalFile.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const UpdateStagingException('invalid_staging_destination');
    }
    final canonicalStaged = File(await finalFile.resolveSymbolicLinks());
    final canonicalParent = await canonicalStaged.parent.resolveSymbolicLinks();
    if (canonicalParent != canonicalUpdates.path ||
        canonicalStaged.path != finalFile.path) {
      throw const UpdateStagingException('invalid_staging_destination');
    }
    succeeded = true;
    return finalFile;
  } finally {
    if (!succeeded && ownedFinal != null) {
      await _bestEffortDeleteOwnedFile(ownedFinal);
    }
    await _bestEffortDeleteOwnedDirectory(ownedDirectory);
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

Future<void> _copyToReservedFile(File source, RandomAccessFile output) async {
  await for (final chunk in source.openRead()) {
    await output.writeFrom(chunk);
  }
}

Future<void> _copyAndFlush({
  required File source,
  required File destination,
  required UpdateStagingCopy copy,
}) async {
  final output = await destination.open(mode: FileMode.writeOnly);
  Object? writeFailure;
  StackTrace? writeStackTrace;
  try {
    await copy(source, output);
    await output.flush();
  } catch (error, stackTrace) {
    writeFailure = error;
    writeStackTrace = stackTrace;
  }
  try {
    await output.close();
  } catch (error, stackTrace) {
    writeFailure ??= error;
    writeStackTrace ??= stackTrace;
  }
  if (writeFailure != null) {
    Error.throwWithStackTrace(writeFailure, writeStackTrace!);
  }
}

Future<(int, String)> _hashFile(File file) async {
  var size = 0;
  final sink = Sha256().newHashSink();
  await for (final chunk in file.openRead()) {
    size += chunk.length;
    sink.add(chunk);
  }
  sink.close();
  final digest = await sink.hash();
  return (size, _hexFromBytes(digest.bytes));
}

String _lastPathSegment(String path) {
  final separator = path.lastIndexOf(Platform.pathSeparator);
  return separator < 0 ? path : path.substring(separator + 1);
}

String _finalFileNameForAttempt(String stem, String token, int attempt) =>
    '$stem-$token${attempt == 0 ? '' : '-$attempt'}.apk';

Future<Directory> _canonicalizeDirectory(Directory directory) async =>
    Directory(await directory.resolveSymbolicLinks());

Future<void> _deleteCompletedDownload(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}

Future<void> _bestEffortDeleteOwnedFile(File file) async {
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {}
}

Future<void> _bestEffortDeleteOwnedDirectory(Directory directory) async {
  try {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  } catch (_) {
    // Cleanup must never replace the staging failure that triggered it.
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
