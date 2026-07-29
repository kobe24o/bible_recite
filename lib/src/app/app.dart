import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../features/update/application/update_controller.dart';
import '../features/update/domain/update_status.dart';
import '../features/update/presentation/update_available_notification.dart';
import '../features/plans/application/plan_providers.dart';
import '../features/reminder/reminder_providers.dart';
import 'router.dart';

class BibleReciteApp extends ConsumerStatefulWidget {
  const BibleReciteApp({this.locale, super.key});

  final Locale? locale;

  @override
  ConsumerState<BibleReciteApp> createState() => _BibleReciteAppState();
}

class _BibleReciteAppState extends ConsumerState<BibleReciteApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkUpdateAtLaunch());
      unawaited(_refreshDailyReminders());
    });
  }

  Future<void> _refreshDailyReminders() async {
    final repository = await ref.read(planRepositoryProvider.future);
    await ref.read(dailyTaskReminderSchedulerProvider).reschedule(repository);
  }

  Future<void> _checkUpdateAtLaunch() async {
    final controller = ref.read(updateControllerProvider.notifier);
    await controller.autoCheck();
    final status = ref.read(updateControllerProvider);
    if (status case UpdateAvailable(:final manifest)) {
      await UpdateAvailableNotification().show(manifest);
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
