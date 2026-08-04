import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../features/update/application/update_controller.dart';
import '../features/update/domain/update_status.dart';
import '../features/update/presentation/update_available_notification.dart';
import '../features/plans/application/plan_providers.dart';
import '../features/plans/application/preset_plan_sync.dart';
import '../features/reminder/reminder_providers.dart';
import 'router.dart';

class BibleReciteApp extends ConsumerStatefulWidget {
  const BibleReciteApp({this.locale, super.key});

  final Locale? locale;

  @override
  ConsumerState<BibleReciteApp> createState() => _BibleReciteAppState();
}

class _BibleReciteAppState extends ConsumerState<BibleReciteApp>
    with WidgetsBindingObserver {
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkUpdateAtLaunch());
      unawaited(_refreshDailyReminders());
      unawaited(_syncPresetPlansAtLaunch());
    });
    _updateTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      unawaited(_checkUpdateAtLaunch());
    });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshDailyReminders());
      unawaited(_checkUpdateAtLaunch());
    }
  }

  Future<void> _refreshDailyReminders() async {
    final repository = await ref.read(planRepositoryProvider.future);
    await ref.read(dailyTaskReminderSchedulerProvider).reschedule(repository);
  }

  Future<void> _syncPresetPlansAtLaunch() async {
    try {
      final result = await syncPresetPlans(
        repository: await ref.read(planRepositoryProvider.future),
        client: ref.read(cloudPlanFeedClientProvider),
      );
      if (result.manifest.plans.isNotEmpty) {
        ref.read(presetPlanRevisionProvider.notifier).refresh();
      }
    } catch (_) {
      // A plan feed failure must never delay app startup or offline use.
    }
  }

  Future<void> _checkUpdateAtLaunch() async {
    final controller = ref.read(updateControllerProvider.notifier);
    await controller.restoreReadyUpdate();
    UpdateAvailableNotification.setDownloadedTapHandler(controller.install);
    await UpdateAvailableNotification.initialize();
    await controller.autoCheck();
    final status = ref.read(updateControllerProvider);
    if (status case UpdateAvailable(:final manifest)) {
      await UpdateAvailableNotification().show(manifest);
    } else if (status case ReadyToInstall(:final manifest)) {
      await UpdateAvailableNotification().showDownloaded(manifest);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      locale: widget.locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: appRouter,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF355E3B)),
      ),
    );
  }
}
