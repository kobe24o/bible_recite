import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../application/update_controller.dart';
import '../application/update_providers.dart';
import '../domain/update_manifest.dart';
import '../domain/update_status.dart';

final aboutUpdateStatusProvider = Provider<UpdateStatus>(
  (ref) => ref.watch(updateControllerProvider),
);

final aboutUpdateActionsProvider = Provider<AboutUpdateActions>(
  (ref) => _ControllerAboutUpdateActions(
    ref.read(updateControllerProvider.notifier),
  ),
);

abstract interface class AboutUpdateActions {
  Future<void> check();
  Future<void> startDownload();
  Future<void> confirmCellularDownload();
  Future<void> cancelDownload();
  Future<void> install();
}

class _ControllerAboutUpdateActions implements AboutUpdateActions {
  const _ControllerAboutUpdateActions(this._controller);

  final UpdateController _controller;

  @override
  Future<void> cancelDownload() => _controller.cancelDownload();

  @override
  Future<void> check() => _controller.check();

  @override
  Future<void> confirmCellularDownload() =>
      _controller.confirmCellularDownload();

  @override
  Future<void> install() => _controller.install();

  @override
  Future<void> startDownload() => _controller.startDownload();
}

class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen>
    with WidgetsBindingObserver {
  ProviderSubscription<UpdateStatus>? _statusSubscription;
  bool _permissionResumePending = false;
  bool _cellularDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _statusSubscription = ref.listenManual<UpdateStatus>(
      aboutUpdateStatusProvider,
      (_, next) {
        _permissionResumePending =
            next is PermissionRequired &&
            next.retryPhase == PermissionRetryPhase.awaitingResume;
        if (next is AwaitingCellularConfirmation) {
          _showCellularDialog(next.manifest);
        }
      },
      fireImmediately: true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(aboutUpdateActionsProvider).check());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_permissionResumePending) {
      return;
    }
    _permissionResumePending = false;
    unawaited(ref.read(aboutUpdateActionsProvider).install());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusSubscription?.close();
    super.dispose();
  }

  void _showCellularDialog(UpdateManifest manifest) {
    if (_cellularDialogOpen) {
      return;
    }
    _cellularDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) {
          final strings = AppLocalizations.of(context)!;
          return AlertDialog(
            title: Text(strings.updateCellularTitle),
            content: Text(
              strings.updateCellularMessage(
                _formatBytes(manifest.android.size),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  unawaited(ref.read(aboutUpdateActionsProvider).check());
                },
                child: Text(strings.updateNotNow),
              ),
              FilledButton(
                key: const Key('about-update'),
                onPressed: () {
                  Navigator.pop(context);
                  unawaited(
                    ref
                        .read(aboutUpdateActionsProvider)
                        .confirmCellularDownload(),
                  );
                },
                child: Text(strings.updateDownload),
              ),
            ],
          );
        },
      );
      _cellularDialogOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final package = ref.watch(installedPackageInfoProvider);
    final status = ref.watch(aboutUpdateStatusProvider);
    final isAndroid =
        ref.watch(updateRuntimePlatformProvider) ==
        UpdateRuntimePlatform.android;

    return Scaffold(
      appBar: AppBar(title: Text(strings.aboutTitle)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            strings.appTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          package.when(
            data: (info) => Text(
              strings.updateInstalledVersion(info.version, info.buildNumber),
            ),
            loading: () => const SizedBox(height: 20),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 24),
          _UpdatePanel(status: status, isAndroid: isAndroid),
        ],
      ),
    );
  }
}

class _UpdatePanel extends ConsumerWidget {
  const _UpdatePanel({required this.status, required this.isAndroid});

  final UpdateStatus status;
  final bool isAndroid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context)!;
    final controller = ref.read(aboutUpdateActionsProvider);

    Widget checkButton() => OutlinedButton(
      key: const Key('about-check'),
      onPressed: () => unawaited(controller.check()),
      child: Text(strings.updateCheck),
    );

    switch (status) {
      case UpdateIdle():
        return checkButton();
      case UpdateChecking():
        return _UpdateCard(
          title: strings.updateChecking,
          child: const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        );
      case UpdateCurrent():
        return _UpdateCard(title: strings.updateCurrent, child: checkButton());
      case UpdateAvailable(:final manifest, :final supportsDirectInstall):
        return _AvailablePanel(
          manifest: manifest,
          directInstall: isAndroid && supportsDirectInstall,
        );
      case AwaitingCellularConfirmation(:final manifest):
        return _UpdateCard(
          title: strings.updateDownloadPending,
          child: Text(strings.updateSize(_formatBytes(manifest.android.size))),
        );
      case UpdateDownloading(
        :final receivedBytes,
        :final totalBytes,
        :final bytesPerSecond,
      ):
        final hasTotal = totalBytes > 0;
        return _UpdateCard(
          title: strings.updateDownloading,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                hasTotal
                    ? strings.updateProgress(
                        _formatBytes(receivedBytes),
                        _formatBytes(totalBytes),
                        _formatBytes(bytesPerSecond),
                      )
                    : strings.updateProgressUnknown(
                        _formatBytes(receivedBytes),
                      ),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: hasTotal ? receivedBytes / totalBytes : null,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('about-cancel'),
                onPressed: () => unawaited(controller.cancelDownload()),
                child: Text(strings.updateCancel),
              ),
            ],
          ),
        );
      case ReadyToInstall():
        return _InstallPanel(
          title: strings.updateReady,
          message: strings.updateReadyMessage,
        );
      case PermissionRequired(:final retryPhase):
        return _InstallPanel(
          title: strings.updatePermissionTitle,
          message: retryPhase == PermissionRetryPhase.awaitingResume
              ? strings.updatePermissionMessage
              : strings.updatePermissionRetryMessage,
        );
      case UpdateInstalling():
        return _UpdateCard(
          title: strings.updateInstalling,
          child: const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        );
      case UpdateFailed():
        return _UpdateCard(
          title: strings.updateFailed,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(strings.updateFailedMessage),
              const SizedBox(height: 12),
              checkButton(),
            ],
          ),
        );
    }
  }
}

class _AvailablePanel extends ConsumerWidget {
  const _AvailablePanel({required this.manifest, required this.directInstall});

  final UpdateManifest manifest;
  final bool directInstall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context)!;
    return _UpdateCard(
      title: strings.updateAvailable(
        '${manifest.version.major}.${manifest.version.minor}.${manifest.version.patch}',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(strings.updateSize(_formatBytes(manifest.android.size))),
          if (manifest.releaseNotes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(manifest.releaseNotes),
          ],
          const SizedBox(height: 12),
          if (directInstall)
            FilledButton(
              key: const Key('about-update'),
              onPressed: () => unawaited(
                ref.read(aboutUpdateActionsProvider).startDownload(),
              ),
              child: Text(strings.updateDownload),
            )
          else
            FilledButton.icon(
              key: const Key('about-release-link'),
              onPressed: () => unawaited(
                launchUrl(
                  manifest.releasePageUrl,
                  mode: LaunchMode.externalApplication,
                ),
              ),
              icon: const Icon(Icons.open_in_new),
              label: Text(strings.updateViewRelease),
            ),
        ],
      ),
    );
  }
}

class _InstallPanel extends ConsumerWidget {
  const _InstallPanel({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context)!;
    return _UpdateCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('about-install'),
            onPressed: () =>
                unawaited(ref.read(aboutUpdateActionsProvider).install()),
            child: Text(strings.updateInstall),
          ),
        ],
      ),
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          child,
        ],
      ),
    ),
  );
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
