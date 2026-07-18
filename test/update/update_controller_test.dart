import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bible_recite/src/features/update/application/update_controller.dart';
import 'package:bible_recite/src/features/update/application/update_providers.dart';
import 'package:bible_recite/src/features/update/data/resumable_downloader.dart';
import 'package:bible_recite/src/features/update/data/update_verifier.dart';
import 'package:bible_recite/src/features/update/domain/app_version.dart';
import 'package:bible_recite/src/features/update/domain/update_manifest.dart';
import 'package:bible_recite/src/features/update/domain/update_status.dart';
import 'package:bible_recite/src/features/update/platform/android_update_bridge.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('update-controller-test-');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('check reports current and available releases', () async {
    final current = _manifest(versionName: '1.0.3', buildNumber: 4);
    final currentHarness = _Harness(root: root, manifest: current);
    await currentHarness.controller.check();
    expect(currentHarness.controller.state, isA<UpdateCurrent>());
    currentHarness.dispose();

    final newer = _manifest(versionName: '1.0.4', buildNumber: 5);
    final availableHarness = _Harness(root: root, manifest: newer);
    await availableHarness.controller.check();
    final state = availableHarness.controller.state as UpdateAvailable;
    expect(state.manifest, same(newer));
    expect(state.supportsDirectInstall, isTrue);
    availableHarness.dispose();
  });

  test('check maps technical errors to a stable reason code', () async {
    final harness = _Harness(
      root: root,
      manifestLoader: () => throw StateError('secret transport detail'),
    );

    await harness.controller.check();

    final failed = harness.controller.state as UpdateFailed;
    expect(failed.reasonCode, UpdateFailureReason.checkFailed);
    expect(failed.reasonCode, isNot(contains('secret transport detail')));
    harness.dispose();
  });

  test('a second check is ignored while the first is active', () async {
    final gate = Completer<UpdateManifest>();
    var calls = 0;
    final harness = _Harness(
      root: root,
      manifestLoader: () {
        calls++;
        return gate.future;
      },
    );

    final first = harness.controller.check();
    await Future<void>.delayed(Duration.zero);
    final second = harness.controller.check();
    expect(harness.controller.state, isA<UpdateChecking>());
    expect(calls, 1);
    gate.complete(_manifest());
    await Future.wait([first, second]);
    expect(calls, 1);
    harness.dispose();
  });

  test('cellular requires confirmation before download', () async {
    final harness = _Harness(root: root, networkTransport: 'cellular');
    await harness.controller.check();

    await harness.controller.startDownload();

    final awaiting = harness.controller.state as AwaitingCellularConfirmation;
    expect(awaiting.manifest.android.size, 3);
    expect(harness.downloadCalls, 0);

    await harness.controller.confirmCellularDownload();

    expect(harness.controller.state, isA<ReadyToInstall>());
    expect(harness.downloadCalls, 1);
    harness.dispose();
  });

  test('Wi-Fi downloads immediately and publishes progress', () async {
    final downloadGate = Completer<void>();
    final harness = _Harness(root: root, downloadGate: downloadGate);
    await harness.controller.check();

    final download = harness.controller.startDownload();
    await harness.progressPublished.future;
    final progress = harness.controller.state as UpdateDownloading;
    expect(progress.receivedBytes, 2);
    expect(progress.totalBytes, 3);
    expect(harness.events, ['download', 'progress']);

    final duplicate = harness.controller.startDownload();
    expect(harness.downloadCalls, 1);
    downloadGate.complete();
    await Future.wait([download, duplicate]);

    expect(harness.events, [
      'download',
      'progress',
      'verify-file',
      'inspect',
      'verify-package',
      'stage',
    ]);
    expect(harness.controller.state, isA<ReadyToInstall>());
    harness.dispose();
  });

  test('cancellation is non-fallback and returns to available', () async {
    final harness = _Harness(root: root, waitForCancellation: true);
    await harness.controller.check();

    final downloading = harness.controller.startDownload();
    await harness.downloadStarted.future;
    await harness.controller.cancelDownload();
    await downloading;

    expect(harness.controller.state, isA<UpdateAvailable>());
    expect(harness.downloadCalls, 1);
    expect(harness.events, ['download', 'cancel']);
    harness.dispose();
  });

  test('verification failure never stages or installs bytes', () async {
    final harness = _Harness(
      root: root,
      verificationFailure: const UpdateVerificationException('sha256_mismatch'),
    );
    await harness.controller.check();

    await harness.controller.startDownload();

    final failed = harness.controller.state as UpdateFailed;
    expect(failed.reasonCode, 'sha256_mismatch');
    expect(failed.manifest, isNotNull);
    expect(harness.events, ['download', 'progress', 'verify-file']);
    expect(harness.installCalls, 0);
    harness.dispose();
  });

  test('package verification strictly precedes staging and install', () async {
    final harness = _Harness(root: root);
    await harness.controller.check();
    await harness.controller.startDownload();
    await harness.controller.install();

    expect(harness.events, [
      'download',
      'progress',
      'verify-file',
      'inspect',
      'verify-package',
      'stage',
      'permission-check',
      'install',
    ]);
    expect(harness.controller.state, isA<ReadyToInstall>());
    harness.dispose();
  });

  test('install remains serialized while the system installer opens', () async {
    final installGate = Completer<void>();
    final harness = _Harness(root: root, installGate: installGate);
    await harness.controller.check();
    await harness.controller.startDownload();

    final first = harness.controller.install();
    await harness.installStarted.future;
    expect(harness.controller.state, isA<UpdateInstalling>());
    final second = harness.controller.install();
    expect(harness.installCalls, 1);
    installGate.complete();
    await Future.wait([first, second]);

    expect(harness.installCalls, 1);
    expect(harness.controller.state, isA<ReadyToInstall>());
    harness.dispose();
  });

  test('permission settings return rechecks before installation', () async {
    final harness = _Harness(root: root, permissionResults: [false, true]);
    await harness.controller.check();
    await harness.controller.startDownload();

    await harness.controller.install();
    expect(harness.controller.state, isA<PermissionRequired>());
    expect(harness.events.takeLast(2), ['permission-check', 'open-settings']);
    expect(harness.installCalls, 0);

    await harness.controller.install();
    expect(harness.events.takeLast(2), ['permission-check', 'install']);
    expect(harness.installCalls, 1);
    expect(harness.controller.state, isA<ReadyToInstall>());
    harness.dispose();
  });

  test(
    'denied permission remains required without reopening settings',
    () async {
      final harness = _Harness(root: root, permissionResults: [false, false]);
      await harness.controller.check();
      await harness.controller.startDownload();
      await harness.controller.install();
      await harness.controller.install();

      expect(harness.controller.state, isA<PermissionRequired>());
      expect(
        harness.events.where((event) => event == 'open-settings'),
        hasLength(1),
      );
      expect(harness.installCalls, 0);
      harness.dispose();
    },
  );

  test(
    'non-Android exposes the Release only and never downloads APK',
    () async {
      final harness = _Harness(
        root: root,
        runtimePlatform: UpdateRuntimePlatform.other,
      );
      await harness.controller.check();

      final available = harness.controller.state as UpdateAvailable;
      expect(available.supportsDirectInstall, isFalse);
      expect(available.manifest.releasePageUrl.scheme, 'https');
      await harness.controller.startDownload();
      await harness.controller.install();

      expect(harness.downloadCalls, 0);
      expect(harness.installCalls, 0);
      expect(harness.events, isEmpty);
      harness.dispose();
    },
  );

  test('R2 public base URL configuration has stable failures', () {
    expect(
      () => parseR2PublicBaseUrl(''),
      throwsA(
        isA<UpdateConfigurationException>().having(
          (error) => error.reasonCode,
          'reasonCode',
          UpdateFailureReason.r2PublicBaseUrlMissing,
        ),
      ),
    );
    expect(
      () => parseR2PublicBaseUrl('http://updates.example.com'),
      throwsA(
        isA<UpdateConfigurationException>().having(
          (error) => error.reasonCode,
          'reasonCode',
          UpdateFailureReason.r2PublicBaseUrlInvalid,
        ),
      ),
    );
    expect(
      parseR2PublicBaseUrl('https://updates.example.com/base').toString(),
      'https://updates.example.com/base',
    );
  });

  test('staging replaces collisions with the exact verified APK', () async {
    final bytes = [1, 2, 3];
    final digest = await Sha256().hash(bytes);
    final sha = digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final manifest = _manifest(sha256: sha);
    final source = File('${root.path}${Platform.pathSeparator}source.apk');
    await source.writeAsBytes(bytes);
    final staging = Directory(
      '${root.path}${Platform.pathSeparator}cache${Platform.pathSeparator}updates',
    );
    await staging.create(recursive: true);
    final collision = File(
      '${staging.path}${Platform.pathSeparator}${manifest.android.fileName}',
    );
    await collision.writeAsBytes([9, 9, 9]);

    final staged = await stageVerifiedUpdateApk(
      source,
      manifest.android,
      staging,
    );

    expect(await staged.readAsBytes(), bytes);
    expect(
      await staged.parent.resolveSymbolicLinks(),
      await staging.resolveSymbolicLinks(),
    );
    expect(staged.path, collision.path);
  });

  test(
    'staging rejects a manifest filename that is not one path segment',
    () async {
      final source = File('${root.path}${Platform.pathSeparator}source.apk');
      await source.writeAsBytes([1, 2, 3]);
      final staging = Directory('${root.path}${Platform.pathSeparator}updates');
      final manifest = _manifest(fileName: 'BibleRecite-nested/evil.apk');

      await expectLater(
        stageVerifiedUpdateApk(source, manifest.android, staging),
        throwsA(isA<UpdateStagingException>()),
      );
      expect(await staging.exists(), isFalse);
    },
  );

  test('staging removes temporary bytes when copy verification fails', () async {
    final source = File('${root.path}${Platform.pathSeparator}source.apk');
    await source.writeAsBytes([1, 2, 3]);
    final staging = Directory('${root.path}${Platform.pathSeparator}updates');

    await expectLater(
      stageVerifiedUpdateApk(source, _manifest().android, staging),
      throwsA(isA<UpdateStagingException>()),
    );

    expect(await staging.list().toList(), isEmpty);
  });
}

final class _Harness {
  _Harness({
    required this.root,
    UpdateManifest? manifest,
    Future<UpdateManifest> Function()? manifestLoader,
    this.networkTransport = 'wifi',
    this.runtimePlatform = UpdateRuntimePlatform.android,
    this.downloadGate,
    this.installGate,
    this.waitForCancellation = false,
    this.verificationFailure,
    List<bool> permissionResults = const [true],
  }) : manifest = manifest ?? _manifest(),
       _permissionResults = [...permissionResults] {
    container = ProviderContainer(
      overrides: [
        updateRuntimePlatformProvider.overrideWith((ref) => runtimePlatform),
        installedAppVersionProvider.overrideWith(
          (ref) async => AppVersion.parse('1.0.3', '4'),
        ),
        updateManifestLoaderProvider.overrideWith(
          (ref) => manifestLoader ?? () async => this.manifest,
        ),
        updateNetworkTransportProvider.overrideWith(
          (ref) =>
              () async => networkTransport,
        ),
        updateDownloadDirectoryProvider.overrideWith(
          (ref) async => Directory(
            '${root.path}${Platform.pathSeparator}support${Platform.pathSeparator}updates',
          ),
        ),
        updateStagingDirectoryProvider.overrideWith(
          (ref) async => Directory(
            '${root.path}${Platform.pathSeparator}cache${Platform.pathSeparator}updates',
          ),
        ),
        updateDownloadOperationProvider.overrideWith((ref) => _download),
        updateFileVerificationProvider.overrideWith((ref) => _verifyFile),
        updateApkInspectionProvider.overrideWith((ref) => _inspect),
        updatePackageVerificationProvider.overrideWith((ref) => _verifyPackage),
        updateApkStagingProvider.overrideWith((ref) => _stage),
        updateInstallPermissionProvider.overrideWith((ref) => _canInstall),
        updateOpenInstallPermissionProvider.overrideWith(
          (ref) => _openSettings,
        ),
        updateApkInstallProvider.overrideWith((ref) => _install),
      ],
    );
    controller = container.read(updateControllerProvider.notifier);
  }

  final Directory root;
  final UpdateManifest manifest;
  final String networkTransport;
  final UpdateRuntimePlatform runtimePlatform;
  final Completer<void>? downloadGate;
  final Completer<void>? installGate;
  final bool waitForCancellation;
  final UpdateVerificationException? verificationFailure;
  final List<bool> _permissionResults;
  final events = <String>[];
  final downloadStarted = Completer<void>();
  final progressPublished = Completer<void>();
  final installStarted = Completer<void>();
  late final ProviderContainer container;
  late final UpdateController controller;
  int downloadCalls = 0;
  int installCalls = 0;

  Future<DownloadedUpdate> _download(
    AndroidUpdateAsset asset,
    Directory directory, {
    required void Function(DownloadProgress) onProgress,
    required DownloadCancellation cancellation,
  }) async {
    downloadCalls++;
    events.add('download');
    if (!downloadStarted.isCompleted) {
      downloadStarted.complete();
    }
    if (waitForCancellation) {
      final cancelled = Completer<void>();
      cancellation.register(() {
        events.add('cancel');
        cancelled.complete();
      });
      await cancelled.future;
      throw const DownloadCancelled();
    }
    onProgress(const DownloadProgress(receivedBytes: 2, totalBytes: 3));
    events.add('progress');
    if (!progressPublished.isCompleted) {
      progressPublished.complete();
    }
    await downloadGate?.future;
    return DownloadedUpdate(
      file: File('${directory.path}${Platform.pathSeparator}${asset.fileName}'),
    );
  }

  Future<void> _verifyFile(File file, AndroidUpdateAsset asset) async {
    events.add('verify-file');
    if (verificationFailure case final failure?) {
      throw failure;
    }
  }

  Future<AndroidApkInfo> _inspect(File file) async {
    events.add('inspect');
    return const AndroidApkInfo(
      packageName: 'app.biblerecite',
      versionName: '1.0.4',
      versionCode: 5,
      certificateSha256:
          '4066fe3c0e57ec575e5d37b741d68d347f8af80b7cf9da4799636d7039b5a7e7',
    );
  }

  Future<void> _verifyPackage(
    AndroidApkInfo apk,
    UpdateManifest manifest,
    AppVersion installedVersion,
  ) async {
    events.add('verify-package');
  }

  Future<File> _stage(
    File file,
    AndroidUpdateAsset asset,
    Directory directory,
  ) async {
    events.add('stage');
    return File('${directory.path}${Platform.pathSeparator}${asset.fileName}');
  }

  Future<bool> _canInstall() async {
    events.add('permission-check');
    return _permissionResults.length == 1
        ? _permissionResults.single
        : _permissionResults.removeAt(0);
  }

  Future<void> _openSettings() async {
    events.add('open-settings');
  }

  Future<void> _install(File file) async {
    events.add('install');
    installCalls++;
    if (!installStarted.isCompleted) {
      installStarted.complete();
    }
    await installGate?.future;
  }

  void dispose() => container.dispose();
}

extension<T> on Iterable<T> {
  List<T> takeLast(int count) => skip(length - count).toList();
}

UpdateManifest _manifest({
  String versionName = '1.0.4',
  int buildNumber = 5,
  String sha256 =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  String fileName = 'BibleRecite-1.0.4+5.apk',
}) {
  final payload = jsonEncode({
    'versionName': versionName,
    'buildNumber': '$buildNumber',
    'sourceCommit': '0123456789abcdef',
    'publishedAt': '2026-07-18T00:00:00Z',
    'releaseNotes': 'Safer app updates.',
    'releasePageUrl':
        'https://github.com/kobe24o/bible_recite/releases/tag/v$versionName',
    'android': {
      'packageName': 'app.biblerecite',
      'fileName': fileName,
      'size': 3,
      'sha256': sha256,
      'signingCertificateSha256':
          '4066fe3c0e57ec575e5d37b741d68d347f8af80b7cf9da4799636d7039b5a7e7',
      'urls': [
        'https://updates.example.com/$fileName',
        'https://github.com/kobe24o/bible_recite/releases/download/v$versionName/$fileName',
      ],
    },
  });
  return UpdateManifest.fromPayloadBytes(utf8.encode(payload));
}
