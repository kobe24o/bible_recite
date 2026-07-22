import 'dart:io';

import 'app_version.dart';
import 'update_manifest.dart';

sealed class UpdateStatus {
  const UpdateStatus();
}

final class UpdateIdle extends UpdateStatus {
  const UpdateIdle();
}

final class UpdateChecking extends UpdateStatus {
  const UpdateChecking();
}

final class UpdateCurrent extends UpdateStatus {
  const UpdateCurrent({required this.installedVersion});

  final AppVersion installedVersion;
}

final class UpdateAvailable extends UpdateStatus {
  const UpdateAvailable({
    required this.manifest,
    required this.supportsDirectInstall,
  });

  final UpdateManifest manifest;
  final bool supportsDirectInstall;
}

final class AwaitingCellularConfirmation extends UpdateStatus {
  const AwaitingCellularConfirmation({required this.manifest});

  final UpdateManifest manifest;
}

final class UpdateDownloading extends UpdateStatus {
  const UpdateDownloading({
    required this.manifest,
    required this.receivedBytes,
    required this.totalBytes,
    required this.bytesPerSecond,
  });

  final UpdateManifest manifest;
  final int receivedBytes;
  final int totalBytes;
  final int bytesPerSecond;
}

final class ReadyToInstall extends UpdateStatus {
  const ReadyToInstall({required this.manifest, required this.file});

  final UpdateManifest manifest;
  final File file;
}

final class PermissionRequired extends UpdateStatus {
  const PermissionRequired({
    required this.manifest,
    required this.file,
    this.retryPhase = PermissionRetryPhase.awaitingResume,
  });

  final UpdateManifest manifest;
  final File file;
  final PermissionRetryPhase retryPhase;
}

enum PermissionRetryPhase { awaitingResume, explicitRetry }

final class UpdateInstalling extends UpdateStatus {
  const UpdateInstalling({required this.manifest, required this.file});

  final UpdateManifest manifest;
  final File file;
}

final class UpdateFailed extends UpdateStatus {
  const UpdateFailed({required this.reasonCode, this.manifest});

  final String reasonCode;
  final UpdateManifest? manifest;
}

abstract final class UpdateFailureReason {
  static const r2PublicBaseUrlMissing = 'r2_public_base_url_missing';
  static const r2PublicBaseUrlInvalid = 'r2_public_base_url_invalid';
  static const checkFailed = 'check_failed';
  static const networkCheckFailed = 'network_check_failed';
  static const downloadFailed = 'download_failed';
  static const fileVerificationFailed = 'file_verification_failed';
  static const packageInspectionFailed = 'package_inspection_failed';
  static const packageVerificationFailed = 'package_verification_failed';
  static const stagingFailed = 'staging_failed';
  static const permissionCheckFailed = 'permission_check_failed';
  static const permissionSettingsFailed = 'permission_settings_failed';
  static const installFailed = 'install_failed';
}
