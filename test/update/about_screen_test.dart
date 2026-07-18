import 'dart:convert';
import 'dart:io';

import 'package:bible_recite/src/features/update/application/update_providers.dart';
import 'package:bible_recite/src/features/update/domain/app_version.dart';
import 'package:bible_recite/src/features/update/domain/update_manifest.dart';
import 'package:bible_recite/src/features/update/domain/update_status.dart';
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
}

Future<void> _pumpAbout(
  WidgetTester tester, {
  UpdateRuntimePlatform platform = UpdateRuntimePlatform.other,
  required UpdateStatus status,
  _Actions? actions,
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
