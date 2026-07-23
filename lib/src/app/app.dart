import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../features/update/application/update_controller.dart';
import 'router.dart';

class BibleReciteApp extends ConsumerStatefulWidget {
  const BibleReciteApp({this.locale, super.key});

  final Locale? locale;

  @override
  ConsumerState<BibleReciteApp> createState() => _BibleReciteAppState();
}

class _BibleReciteAppState extends ConsumerState<BibleReciteApp> {
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(updateControllerProvider.notifier).autoCheck());
      _updateTimer = Timer.periodic(
        const Duration(minutes: 30),
        (_) =>
            unawaited(ref.read(updateControllerProvider.notifier).autoCheck()),
      );
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
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
