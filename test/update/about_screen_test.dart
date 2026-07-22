import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bible_recite/src/features/update/application/update_controller.dart';
import 'package:bible_recite/src/features/update/application/update_providers.dart';
import 'package:bible_recite/src/features/update/data/resumable_downloader.dart';
import 'package:bible_recite/src/features/update/domain/app_version.dart';
import 'package:bible_recite/src/features/update/domain/update_manifest.dart';
import 'package:bible_recite/src/features/update/domain/update_status.dart';
import 'package:bible_recite/src/features/update/platform/android_update_bridge.dart';
import 'package:bible_recite/src/features/update/presentation/about_screen.dart';
import 'package:bible_recite/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  testWidgets('checks after About opens and shows installed current version', (
    tester,
  ) async {
    final actions = _Actions();
    await _pumpAbout(
      tester,
      status: UpdateCurrent(installedVersion: AppVersion.parse('1.0.4', '7')),
      actions: actions,
    );

    expect(actions.checks, 1);
    expect(find.text('Version 1.0.4 (build 7)'), findsOneWidget);
    expect(find.text("You're up to date"), findsOneWidget);
    await tester.tap(find.byKey(const Key('about-check')));
    expect(actions.checks, 2);
  });

  testWidgets('Android presents update, progress, cancellation, and install', (
    tester,
  ) async {
    final actions = _Actions();
    await _pumpAbout(
      tester,
      platform: UpdateRuntimePlatform.android,
      status: UpdateAvailable(
        manifest: _manifest(),
        supportsDirectInstall: true,
      ),
      actions: actions,
    );
    expect(find.text('Version 1.0.5 is available'), findsOneWidget);
    expect(find.text('Safer installs'), findsOneWidget);
    await tester.tap(find.byKey(const Key('about-update')));
    expect(actions.downloads, 1);

    await _pumpAbout(
      tester,
      platform: UpdateRuntimePlatform.android,
      status: UpdateDownloading(
        manifest: _manifest(),
        receivedBytes: 512 * 1024,
        totalBytes: 1024 * 1024,
        bytesPerSecond: 256 * 1024,
      ),
      actions: actions,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.tap(find.byKey(const Key('about-cancel')));
    expect(actions.cancellations, 1);

    await _pumpAbout(
      tester,
      platform: UpdateRuntimePlatform.android,
      status: ReadyToInstall(manifest: _manifest(), file: File('verified.apk')),
      actions: actions,
    );
    expect(find.text('Update ready'), findsOneWidget);
    await tester.tap(find.byKey(const Key('about-install')));
    expect(actions.installs, 1);
  });

  testWidgets(
    'Android cellular confirmation includes size and starts download',
    (tester) async {
      final actions = _Actions();
      await _pumpAbout(
        tester,
        platform: UpdateRuntimePlatform.android,
        status: AwaitingCellularConfirmation(manifest: _manifest()),
        actions: actions,
      );

      expect(find.text('Use cellular data?'), findsOneWidget);
      expect(find.textContaining('1.0 MB'), findsNWidgets(2));
      await tester.tap(find.byKey(const Key('about-update')));
      expect(actions.cellularConfirmations, 1);
    },
  );

  testWidgets('resumes the pending permission install exactly once', (
    tester,
  ) async {
    final actions = _Actions();
    await _pumpAbout(
      tester,
      platform: UpdateRuntimePlatform.android,
      status: PermissionRequired(
        manifest: _manifest(),
        file: File('verified.apk'),
      ),
      actions: actions,
    );

    expect(find.text('Allow installs from this app'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(actions.installs, 1);
  });

  testWidgets('non-Android permission resume never starts an APK install', (
    tester,
  ) async {
    final actions = _Actions();
    await _pumpAbout(
      tester,
      status: PermissionRequired(
        manifest: _manifest(),
        file: File('verified.apk'),
      ),
      actions: actions,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(actions.installs, 0);
    expect(find.byKey(const Key('about-release-link')), findsOneWidget);
    expect(find.byKey(const Key('about-install')), findsNothing);
  });

  testWidgets('cellular cancel closes the protected dialog without download', (
    tester,
  ) async {
    final actions = _Actions();
    await _pumpAbout(
      tester,
      platform: UpdateRuntimePlatform.android,
      status: AwaitingCellularConfirmation(manifest: _manifest()),
      actions: actions,
    );
    expect(find.text('Use cellular data?'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Use cellular data?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('about-cellular-cancel')));
    await tester.pumpAndSettle();
    expect(actions.cancellations, 1);
    expect(actions.downloads, 0);
  });

  testWidgets(
    'does not auto-check or expose APK UI for pending non-Android state',
    (tester) async {
      final actions = _Actions();
      await _pumpAbout(
        tester,
        status: ReadyToInstall(
          manifest: _manifest(),
          file: File('verified.apk'),
        ),
        actions: actions,
      );
      expect(actions.checks, 0);
      expect(find.byKey(const Key('about-release-link')), findsOneWidget);
      expect(find.byKey(const Key('about-install')), findsNothing);
      expect(find.byKey(const Key('about-cancel')), findsNothing);
    },
  );

  testWidgets('shows stable failure text and non-Android Release link', (
    tester,
  ) async {
    await _pumpAbout(
      tester,
      status: const UpdateFailed(reasonCode: 'private_exception_detail'),
    );
    expect(find.text('Unable to update'), findsOneWidget);
    expect(find.textContaining('private_exception_detail'), findsNothing);

    await _pumpAbout(
      tester,
      platform: UpdateRuntimePlatform.other,
      status: UpdateAvailable(
        manifest: _manifest(),
        supportsDirectInstall: false,
      ),
    );
    expect(find.byKey(const Key('about-release-link')), findsOneWidget);
    expect(find.byKey(const Key('about-update')), findsNothing);
    expect(find.byKey(const Key('about-install')), findsNothing);
  });

  testWidgets('non-Android pending Android states expose only a release link', (
    tester,
  ) async {
    final manifest = _manifest();
    final states = <UpdateStatus>[
      AwaitingCellularConfirmation(manifest: manifest),
      UpdateDownloading(
        manifest: manifest,
        receivedBytes: 1,
        totalBytes: 2,
        bytesPerSecond: 1,
      ),
      ReadyToInstall(manifest: manifest, file: File('verified.apk')),
      PermissionRequired(manifest: manifest, file: File('verified.apk')),
      UpdateInstalling(manifest: manifest, file: File('verified.apk')),
    ];
    for (final state in states) {
      await _pumpAbout(tester, status: state);
      expect(find.byKey(const Key('about-release-link')), findsOneWidget);
      expect(find.byKey(const Key('about-update')), findsNothing);
      expect(find.byKey(const Key('about-cancel')), findsNothing);
      expect(find.byKey(const Key('about-install')), findsNothing);
    }
  });

  testWidgets('release launcher suppresses duplicates and hides raw failures', (
    tester,
  ) async {
    final gate = Completer<bool>();
    var calls = 0;
    await _pumpAbout(
      tester,
      status: UpdateAvailable(
        manifest: _manifest(),
        supportsDirectInstall: false,
      ),
      launcher: (_) {
        calls++;
        return gate.future;
      },
    );
    await tester.tap(find.byKey(const Key('about-release-link')));
    await tester.tap(find.byKey(const Key('about-release-link')));
    expect(calls, 1);
    gate.complete(true);
    await tester.pumpAndSettle();

    await _pumpAbout(
      tester,
      status: UpdateAvailable(
        manifest: _manifest(),
        supportsDirectInstall: false,
      ),
      launcher: (_) async => false,
    );
    await tester.tap(find.byKey(const Key('about-release-link')));
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to open the release page. Please try again.'),
      findsOneWidget,
    );

    await _pumpAbout(
      tester,
      status: UpdateAvailable(
        manifest: _manifest(),
        supportsDirectInstall: false,
      ),
      launcher: (_) async => throw StateError('private launcher failure'),
    );
    await tester.tap(find.byKey(const Key('about-release-link')));
    await tester.pumpAndSettle();
    expect(find.textContaining('private launcher failure'), findsNothing);
  });

  testWidgets(
    'real controller preserves a staged update when About is remounted',
    (tester) async {
      final harness = _RealControllerHarness.create();
      addTearDown(harness.dispose);

      await _pumpRealAbout(tester, harness.container);
      await _pumpUntilControllerState<UpdateAvailable>(
        tester,
        harness.container,
      );
      expect(harness.feedChecks, 1);
      expect(
        harness.container.read(updateControllerProvider),
        isA<UpdateAvailable>(),
      );

      await tester.tap(find.byKey(const Key('about-update')));
      await _pumpUntilControllerState<ReadyToInstall>(
        tester,
        harness.container,
      );
      final staged = harness.container.read(updateControllerProvider);
      expect(staged, isA<ReadyToInstall>());
      expect(find.byKey(const Key('about-install')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpRealAbout(tester, harness.container);

      expect(harness.feedChecks, 1);
      expect(harness.container.read(updateControllerProvider), same(staged));
      expect(find.byKey(const Key('about-install')), findsOneWidget);
    },
  );

  testWidgets(
    'real controller handles permission lifecycle and explicit retry once each',
    (tester) async {
      final harness = _RealControllerHarness.create(
        permissionResults: [false, false, false, true],
      );
      addTearDown(harness.dispose);

      await _pumpRealAbout(tester, harness.container);
      await _pumpUntilControllerState<UpdateAvailable>(
        tester,
        harness.container,
      );
      await tester.tap(find.byKey(const Key('about-update')));
      await _pumpUntilControllerState<ReadyToInstall>(
        tester,
        harness.container,
      );
      await tester.tap(find.byKey(const Key('about-install')));
      await _pumpUntilControllerState<PermissionRequired>(
        tester,
        harness.container,
      );

      final pending = harness.container.read(updateControllerProvider);
      expect(
        pending,
        isA<PermissionRequired>().having(
          (state) => state.retryPhase,
          'retryPhase',
          PermissionRetryPhase.awaitingResume,
        ),
      );
      expect(harness.permissionChecks, 1);
      expect(harness.settingsOpens, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpRealAbout(tester, harness.container);
      expect(harness.feedChecks, 1);
      expect(harness.container.read(updateControllerProvider), same(pending));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _pumpUntilControllerState<PermissionRequired>(
        tester,
        harness.container,
        where: (state) =>
            state.retryPhase == PermissionRetryPhase.explicitRetry,
      );

      expect(harness.permissionChecks, 2);
      expect(harness.settingsOpens, 1);
      expect(harness.installerLaunches, 0);
      expect(
        harness.container.read(updateControllerProvider),
        isA<PermissionRequired>().having(
          (state) => state.retryPhase,
          'retryPhase',
          PermissionRetryPhase.explicitRetry,
        ),
      );

      await tester.tap(find.byKey(const Key('about-install')));
      await _pumpUntilControllerState<PermissionRequired>(
        tester,
        harness.container,
        where: (state) =>
            state.retryPhase == PermissionRetryPhase.awaitingResume,
      );
      expect(harness.permissionChecks, 3);
      expect(harness.settingsOpens, 2);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _pumpUntilControllerState<ReadyToInstall>(
        tester,
        harness.container,
      );

      expect(harness.permissionChecks, 4);
      expect(harness.settingsOpens, 2);
      expect(harness.installerLaunches, 1);
      expect(
        harness.container.read(updateControllerProvider),
        isA<ReadyToInstall>(),
      );
    },
  );
}

Future<void> _pumpRealAbout(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AboutScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _pumpUntilControllerState<T extends UpdateStatus>(
  WidgetTester tester,
  ProviderContainer container, {
  bool Function(T state)? where,
}) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
    final state = container.read(updateControllerProvider);
    if (state is T && (where == null || where(state))) {
      return;
    }
  }
  fail(
    'UpdateController did not reach $T; '
    'last state: ${container.read(updateControllerProvider)}',
  );
}

Future<void> _pumpAbout(
  WidgetTester tester, {
  UpdateRuntimePlatform platform = UpdateRuntimePlatform.other,
  required UpdateStatus status,
  _Actions? actions,
  UpdateReleaseLauncher? launcher,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        updateRuntimePlatformProvider.overrideWith((ref) => platform),
        installedPackageInfoProvider.overrideWith(
          (ref) async => PackageInfo(
            appName: 'Bible Recite',
            packageName: 'app.biblerecite',
            version: '1.0.4',
            buildNumber: '7',
            buildSignature: '',
          ),
        ),
        aboutUpdateStatusProvider.overrideWith((ref) => status),
        aboutUpdateActionsProvider.overrideWith((ref) => actions ?? _Actions()),
        if (launcher != null)
          updateReleaseLauncherProvider.overrideWith((ref) => launcher),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AboutScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _Actions implements AboutUpdateActions {
  var checks = 0;
  var downloads = 0;
  var cellularConfirmations = 0;
  var cancellations = 0;
  var installs = 0;

  @override
  Future<void> cancelDownload() async => cancellations++;

  @override
  Future<void> cancelCellularDownload() async => cancellations++;

  @override
  Future<void> check() async => checks++;

  @override
  Future<void> confirmCellularDownload() async => cellularConfirmations++;

  @override
  Future<void> install() async => installs++;

  @override
  Future<void> startDownload() async => downloads++;
}

final class _RealControllerHarness {
  _RealControllerHarness._({
    required this.root,
    required this.container,
    required this._permissionResults,
  });

  static _RealControllerHarness create({
    List<bool> permissionResults = const [true],
  }) {
    final root = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'about-real-controller',
    );
    late _RealControllerHarness harness;
    final container = ProviderContainer(
      overrides: [
        updateRuntimePlatformProvider.overrideWith(
          (ref) => UpdateRuntimePlatform.android,
        ),
        installedPackageInfoProvider.overrideWith(
          (ref) async => PackageInfo(
            appName: 'Bible Recite',
            packageName: 'app.biblerecite',
            version: '1.0.4',
            buildNumber: '7',
            buildSignature: '',
          ),
        ),
        updateManifestLoaderProvider.overrideWith(
          (ref) => () async {
            harness.feedChecks++;
            return _manifest();
          },
        ),
        updateNetworkTransportProvider.overrideWith(
          (ref) =>
              () async => 'wifi',
        ),
        updateDownloadDirectoryProvider.overrideWith(
          (ref) async =>
              Directory('${root.path}${Platform.pathSeparator}download'),
        ),
        updateTemporaryDirectoryProvider.overrideWith(
          (ref) async =>
              Directory('${root.path}${Platform.pathSeparator}cache'),
        ),
        updateDownloadOperationProvider.overrideWith(
          (ref) =>
              (
                asset,
                directory, {
                required onProgress,
                required cancellation,
              }) async {
                onProgress(
                  DownloadProgress(
                    receivedBytes: asset.size,
                    totalBytes: asset.size,
                  ),
                );
                return DownloadedUpdate(
                  file: File(
                    '${directory.path}${Platform.pathSeparator}${asset.fileName}',
                  ),
                );
              },
        ),
        updateFileVerificationProvider.overrideWith(
          (ref) => (file, asset) async {},
        ),
        updateApkInspectionProvider.overrideWith(
          (ref) =>
              (file) async => const AndroidApkInfo(
                packageName: 'app.biblerecite',
                versionName: '1.0.5',
                versionCode: 8,
                certificateSha256:
                    '4066fe3c0e57ec575e5d37b741d68d347f8af80b7cf9da4799636d7039b5a7e7',
              ),
        ),
        updatePackageVerificationProvider.overrideWith(
          (ref) => (apk, manifest, installedVersion) async {},
        ),
        updateApkStagingProvider.overrideWith(
          (ref) =>
              (file, asset, directory) async => File(
                '${directory.path}${Platform.pathSeparator}updates'
                '${Platform.pathSeparator}${asset.fileName}',
              ),
        ),
        updateCompletedDownloadCleanupProvider.overrideWith(
          (ref) => (file) async {},
        ),
        updateInstallPermissionProvider.overrideWith(
          (ref) => () async {
            harness.permissionChecks++;
            return harness._permissionResults.length == 1
                ? harness._permissionResults.single
                : harness._permissionResults.removeAt(0);
          },
        ),
        updateOpenInstallPermissionProvider.overrideWith(
          (ref) =>
              () async => harness.settingsOpens++,
        ),
        updateApkInstallProvider.overrideWith(
          (ref) =>
              (file) async => harness.installerLaunches++,
        ),
      ],
    );
    harness = _RealControllerHarness._(
      root: root,
      container: container,
      permissionResults: [...permissionResults],
    );
    return harness;
  }

  final Directory root;
  final ProviderContainer container;
  final List<bool> _permissionResults;
  var feedChecks = 0;
  var permissionChecks = 0;
  var settingsOpens = 0;
  var installerLaunches = 0;

  void dispose() {
    container.dispose();
  }
}

UpdateManifest _manifest() => UpdateManifest.fromPayloadBytes(
  utf8.encode(
    jsonEncode({
      'versionName': '1.0.5',
      'buildNumber': '8',
      'sourceCommit': 'abc1234',
      'publishedAt': '2026-07-18T00:00:00Z',
      'releaseNotes': 'Safer installs',
      'releasePageUrl': 'https://example.com/release',
      'android': {
        'packageName': 'app.biblerecite',
        'fileName': 'BibleRecite-1.0.5.apk',
        'size': 1024 * 1024,
        'sha256': 'a' * 64,
        'signingCertificateSha256':
            '4066fe3c0e57ec575e5d37b741d68d347f8af80b7cf9da4799636d7039b5a7e7',
        'urls': ['https://example.com/app.apk'],
      },
    }),
  ),
);
