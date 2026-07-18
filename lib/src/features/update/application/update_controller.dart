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
  bool _disposed = false;
  DownloadCancellation? _downloadCancellation;
  AppVersion? _installedVersion;

  @override
  UpdateStatus build() {
    ref.onDispose(() {
      _disposed = true;
      _downloadCancellation?.cancel();
    });
    return const UpdateIdle();
  }

  Future<void> check() async {
    if (_operationActive || !_mounted) {
      return;
    }
    _operationActive = true;
    _emit(const UpdateChecking());
    try {
      final loader = ref.read(updateManifestLoaderProvider);
      final manifest = await loader();
      if (!_mounted) {
        return;
      }
      final installedFuture = ref.read(installedAppVersionProvider.future);
      final installed = await installedFuture;
      if (!_mounted) {
        return;
      }
      _installedVersion = installed;
      _emit(
        manifest.version.isNewerThan(installed)
            ? UpdateAvailable(
                manifest: manifest,
                supportsDirectInstall: _isAndroid,
              )
            : UpdateCurrent(installedVersion: installed),
      );
    } on UpdateConfigurationException catch (error) {
      _emit(UpdateFailed(reasonCode: error.reasonCode));
    } catch (_) {
      _emit(const UpdateFailed(reasonCode: UpdateFailureReason.checkFailed));
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
      late final String transport;
      try {
        final readTransport = ref.read(updateNetworkTransportProvider);
        transport = await readTransport();
      } catch (_) {
        _emit(
          UpdateFailed(
            reasonCode: UpdateFailureReason.networkCheckFailed,
            manifest: current.manifest,
          ),
        );
        return;
      }
      if (!_mounted) {
        return;
      }
      if (transport == 'cellular') {
        _emit(AwaitingCellularConfirmation(manifest: current.manifest));
        return;
      }
      await _downloadAndVerify(current.manifest);
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
        final checkPermission = ref.read(updateInstallPermissionProvider);
        allowed = await checkPermission();
      } catch (_) {
        _emit(
          UpdateFailed(
            reasonCode: UpdateFailureReason.permissionCheckFailed,
            manifest: manifest,
          ),
        );
        return;
      }
      if (!_mounted) {
        return;
      }
      if (!allowed) {
        final shouldOpenSettings =
            current is ReadyToInstall ||
            current is PermissionRequired &&
                current.retryPhase == PermissionRetryPhase.explicitRetry;
        _emit(
          PermissionRequired(
            manifest: manifest,
            file: file,
            retryPhase: shouldOpenSettings
                ? PermissionRetryPhase.awaitingResume
                : PermissionRetryPhase.explicitRetry,
          ),
        );
        if (shouldOpenSettings) {
          try {
            if (!_mounted) {
              return;
            }
            final openSettings = ref.read(updateOpenInstallPermissionProvider);
            await openSettings();
          } catch (_) {
            _emit(
              UpdateFailed(
                reasonCode: UpdateFailureReason.permissionSettingsFailed,
                manifest: manifest,
              ),
            );
          }
        }
        return;
      }

      _emit(UpdateInstalling(manifest: manifest, file: file));
      try {
        if (!_mounted) {
          return;
        }
        final openInstaller = ref.read(updateApkInstallProvider);
        await openInstaller(file);
        if (!_mounted) {
          return;
        }
        _emit(ReadyToInstall(manifest: manifest, file: file));
      } catch (_) {
        _emit(
          UpdateFailed(
            reasonCode: UpdateFailureReason.installFailed,
            manifest: manifest,
          ),
        );
      }
    } finally {
      _operationActive = false;
    }
  }

  Future<void> _downloadAndVerify(UpdateManifest manifest) async {
    final installed = _installedVersion;
    if (installed == null || !_mounted) {
      _emit(
        UpdateFailed(
          reasonCode: UpdateFailureReason.downloadFailed,
          manifest: manifest,
        ),
      );
      return;
    }

    final cleanup = ref.read(updateCompletedDownloadCleanupProvider);
    final cancellation = DownloadCancellation();
    _downloadCancellation = cancellation;
    File? downloadedFile;
    var failureReason = UpdateFailureReason.downloadFailed;
    final stopwatch = Stopwatch()..start();
    _emit(
      UpdateDownloading(
        manifest: manifest,
        receivedBytes: 0,
        totalBytes: manifest.android.size,
        bytesPerSecond: 0,
      ),
    );
    try {
      final directoryFuture = ref.read(updateDownloadDirectoryProvider.future);
      final directory = await directoryFuture;
      if (!_mounted) {
        return;
      }
      final download = ref.read(updateDownloadOperationProvider);
      final downloaded = await download(
        manifest.android,
        directory,
        cancellation: cancellation,
        onProgress: (progress) {
          if (cancellation.isCancelled || !_mounted) {
            return;
          }
          final elapsedMicros = stopwatch.elapsedMicroseconds;
          _emit(
            UpdateDownloading(
              manifest: manifest,
              receivedBytes: progress.receivedBytes,
              totalBytes: progress.totalBytes,
              bytesPerSecond: elapsedMicros == 0
                  ? 0
                  : (progress.receivedBytes * Duration.microsecondsPerSecond) ~/
                        elapsedMicros,
            ),
          );
        },
      );
      downloadedFile = downloaded.file;
      if (!_mounted) {
        await _bestEffortCleanup(cleanup, downloadedFile);
        return;
      }
      cancellation.throwIfCancelled();

      failureReason = UpdateFailureReason.fileVerificationFailed;
      final verifyFile = ref.read(updateFileVerificationProvider);
      await verifyFile(downloaded.file, manifest.android);
      if (!_mounted) {
        await _bestEffortCleanup(cleanup, downloadedFile);
        return;
      }
      cancellation.throwIfCancelled();

      failureReason = UpdateFailureReason.packageInspectionFailed;
      final inspect = ref.read(updateApkInspectionProvider);
      final apk = await inspect(downloaded.file);
      if (!_mounted) {
        await _bestEffortCleanup(cleanup, downloadedFile);
        return;
      }
      cancellation.throwIfCancelled();

      failureReason = UpdateFailureReason.packageVerificationFailed;
      final verifyPackage = ref.read(updatePackageVerificationProvider);
      await verifyPackage(apk, manifest, installed);
      if (!_mounted) {
        await _bestEffortCleanup(cleanup, downloadedFile);
        return;
      }
      cancellation.throwIfCancelled();

      failureReason = UpdateFailureReason.stagingFailed;
      final stagingFuture = ref.read(updateStagingDirectoryProvider.future);
      final stagingDirectory = await stagingFuture;
      if (!_mounted) {
        await _bestEffortCleanup(cleanup, downloadedFile);
        return;
      }
      final stage = ref.read(updateApkStagingProvider);
      final staged = await stage(
        downloaded.file,
        manifest.android,
        stagingDirectory,
      );
      if (!_mounted) {
        await _bestEffortCleanup(cleanup, downloadedFile);
        return;
      }
      cancellation.throwIfCancelled();

      await _bestEffortCleanup(cleanup, downloaded.file);
      if (!_mounted) {
        return;
      }
      _emit(ReadyToInstall(manifest: manifest, file: staged));
    } on DownloadCancelled {
      await _bestEffortCleanup(cleanup, downloadedFile);
      _emit(UpdateAvailable(manifest: manifest, supportsDirectInstall: true));
    } on UpdateVerificationException catch (error) {
      await _bestEffortCleanup(cleanup, downloadedFile);
      _emit(UpdateFailed(reasonCode: error.reason, manifest: manifest));
    } on UpdateStagingException {
      await _bestEffortCleanup(cleanup, downloadedFile);
      _emit(
        UpdateFailed(
          reasonCode: UpdateFailureReason.stagingFailed,
          manifest: manifest,
        ),
      );
    } catch (_) {
      await _bestEffortCleanup(cleanup, downloadedFile);
      _emit(UpdateFailed(reasonCode: failureReason, manifest: manifest));
    } finally {
      stopwatch.stop();
      if (identical(_downloadCancellation, cancellation)) {
        _downloadCancellation = null;
      }
    }
  }

  bool get _mounted => !_disposed && ref.mounted;

  bool get _isAndroid =>
      _mounted &&
      ref.read(updateRuntimePlatformProvider) == UpdateRuntimePlatform.android;

  void _emit(UpdateStatus next) {
    if (_mounted) {
      state = next;
    }
  }
}

Future<void> _bestEffortCleanup(
  UpdateCompletedDownloadCleanup cleanup,
  File? file,
) async {
  if (file == null) {
    return;
  }
  try {
    await cleanup(file);
  } catch (_) {
    // Cleanup must never hide the cancellation or verification failure.
  }
}
