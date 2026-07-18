import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/resumable_downloader.dart';
import '../data/update_verifier.dart';
import '../domain/app_version.dart';
import '../domain/update_manifest.dart';
import '../domain/update_status.dart';
import 'update_providers.dart';

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateStatus>(UpdateController.new);

final class UpdateController extends Notifier<UpdateStatus> {
  bool _operationActive = false;
  DownloadCancellation? _downloadCancellation;
  AppVersion? _installedVersion;

  @override
  UpdateStatus build() => const UpdateIdle();

  Future<void> check() async {
    if (_operationActive) {
      return;
    }
    _operationActive = true;
    state = const UpdateChecking();
    try {
      final manifest = await ref.read(updateManifestLoaderProvider)();
      final installed = await ref.read(installedAppVersionProvider.future);
      _installedVersion = installed;
      state = manifest.version.isNewerThan(installed)
          ? UpdateAvailable(
              manifest: manifest,
              supportsDirectInstall: _isAndroid,
            )
          : UpdateCurrent(installedVersion: installed);
    } on UpdateConfigurationException catch (error) {
      state = UpdateFailed(reasonCode: error.reasonCode);
    } catch (_) {
      state = const UpdateFailed(reasonCode: UpdateFailureReason.checkFailed);
    } finally {
      _operationActive = false;
    }
  }

  Future<void> startDownload() async {
    if (_operationActive || !_isAndroid) {
      return;
    }
    final current = state;
    if (current is! UpdateAvailable || !current.supportsDirectInstall) {
      return;
    }

    _operationActive = true;
    try {
      final transport = await ref.read(updateNetworkTransportProvider)();
      if (transport == 'cellular') {
        state = AwaitingCellularConfirmation(manifest: current.manifest);
        return;
      }
      await _downloadAndVerify(current.manifest);
    } catch (_) {
      state = UpdateFailed(
        reasonCode: UpdateFailureReason.networkCheckFailed,
        manifest: current.manifest,
      );
    } finally {
      _operationActive = false;
    }
  }

  Future<void> confirmCellularDownload() async {
    if (_operationActive || !_isAndroid) {
      return;
    }
    final current = state;
    if (current is! AwaitingCellularConfirmation) {
      return;
    }
    _operationActive = true;
    try {
      await _downloadAndVerify(current.manifest);
    } finally {
      _operationActive = false;
    }
  }

  Future<void> cancelDownload() async {
    _downloadCancellation?.cancel();
  }

  Future<void> install() async {
    if (_operationActive || !_isAndroid) {
      return;
    }
    final current = state;
    final manifest = switch (current) {
      ReadyToInstall(:final manifest) => manifest,
      PermissionRequired(:final manifest) => manifest,
      _ => null,
    };
    final file = switch (current) {
      ReadyToInstall(:final file) => file,
      PermissionRequired(:final file) => file,
      _ => null,
    };
    if (manifest == null || file == null) {
      return;
    }

    _operationActive = true;
    try {
      late final bool allowed;
      try {
        allowed = await ref.read(updateInstallPermissionProvider)();
      } catch (_) {
        state = UpdateFailed(
          reasonCode: UpdateFailureReason.permissionCheckFailed,
          manifest: manifest,
        );
        return;
      }
      if (!allowed) {
        state = PermissionRequired(manifest: manifest, file: file);
        if (current is ReadyToInstall) {
          try {
            await ref.read(updateOpenInstallPermissionProvider)();
          } catch (_) {
            state = UpdateFailed(
              reasonCode: UpdateFailureReason.permissionSettingsFailed,
              manifest: manifest,
            );
          }
        }
        return;
      }

      state = UpdateInstalling(manifest: manifest, file: file);
      try {
        await ref.read(updateApkInstallProvider)(file);
        state = ReadyToInstall(manifest: manifest, file: file);
      } catch (_) {
        state = UpdateFailed(
          reasonCode: UpdateFailureReason.installFailed,
          manifest: manifest,
        );
      }
    } finally {
      _operationActive = false;
    }
  }

  Future<void> _downloadAndVerify(UpdateManifest manifest) async {
    final installed = _installedVersion;
    if (installed == null) {
      state = UpdateFailed(
        reasonCode: UpdateFailureReason.downloadFailed,
        manifest: manifest,
      );
      return;
    }

    final cancellation = DownloadCancellation();
    _downloadCancellation = cancellation;
    File? downloadedFile;
    var failureReason = UpdateFailureReason.downloadFailed;
    final stopwatch = Stopwatch()..start();
    state = UpdateDownloading(
      manifest: manifest,
      receivedBytes: 0,
      totalBytes: manifest.android.size,
      bytesPerSecond: 0,
    );
    try {
      final directory = await ref.read(updateDownloadDirectoryProvider.future);
      final downloaded = await ref.read(updateDownloadOperationProvider)(
        manifest.android,
        directory,
        cancellation: cancellation,
        onProgress: (progress) {
          if (cancellation.isCancelled) {
            return;
          }
          final elapsedMicros = stopwatch.elapsedMicroseconds;
          state = UpdateDownloading(
            manifest: manifest,
            receivedBytes: progress.receivedBytes,
            totalBytes: progress.totalBytes,
            bytesPerSecond: elapsedMicros == 0
                ? 0
                : (progress.receivedBytes * Duration.microsecondsPerSecond) ~/
                      elapsedMicros,
          );
        },
      );
      downloadedFile = downloaded.file;
      cancellation.throwIfCancelled();

      failureReason = UpdateFailureReason.packageInspectionFailed;
      await ref.read(updateFileVerificationProvider)(
        downloaded.file,
        manifest.android,
      );
      cancellation.throwIfCancelled();
      final apk = await ref.read(updateApkInspectionProvider)(downloaded.file);
      cancellation.throwIfCancelled();
      await ref.read(updatePackageVerificationProvider)(
        apk,
        manifest,
        installed,
      );
      cancellation.throwIfCancelled();

      failureReason = UpdateFailureReason.stagingFailed;
      final stagingDirectory = await ref.read(
        updateStagingDirectoryProvider.future,
      );
      final staged = await ref.read(updateApkStagingProvider)(
        downloaded.file,
        manifest.android,
        stagingDirectory,
      );
      cancellation.throwIfCancelled();
      state = ReadyToInstall(manifest: manifest, file: staged);
    } on DownloadCancelled {
      await _deleteCompletedDownload(downloadedFile);
      state = UpdateAvailable(manifest: manifest, supportsDirectInstall: true);
    } on UpdateVerificationException catch (error) {
      await _deleteCompletedDownload(downloadedFile);
      state = UpdateFailed(reasonCode: error.reason, manifest: manifest);
    } on UpdateStagingException {
      await _deleteCompletedDownload(downloadedFile);
      state = UpdateFailed(
        reasonCode: UpdateFailureReason.stagingFailed,
        manifest: manifest,
      );
    } catch (_) {
      await _deleteCompletedDownload(downloadedFile);
      state = UpdateFailed(reasonCode: failureReason, manifest: manifest);
    } finally {
      stopwatch.stop();
      if (identical(_downloadCancellation, cancellation)) {
        _downloadCancellation = null;
      }
    }
  }

  bool get _isAndroid =>
      ref.read(updateRuntimePlatformProvider) == UpdateRuntimePlatform.android;
}

Future<void> _deleteCompletedDownload(File? file) async {
  if (file != null && await file.exists()) {
    await file.delete();
  }
}
