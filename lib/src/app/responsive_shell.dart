import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';

class ResponsiveShell extends StatelessWidget {
  const ResponsiveShell({required this.child, super.key});

  static const breakpoint = 720.0;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final labels = (
      today: localizations?.navToday ?? '今日',
      bible: localizations?.navBible ?? '圣经',
      plans: localizations?.navPlans ?? '计划',
      statistics: localizations?.navStatistics ?? '统计',
    );
    final router = GoRouter.maybeOf(context);
    final location =
        router?.routerDelegate.currentConfiguration.uri.path ?? '/';
    final selectedIndex = location.startsWith('/bible') ? 1 : 0;
    void navigate(int index) {
      if (router == null) return;
      if (index == 0) context.go('/');
      if (index == 1) context.go('/bible');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= breakpoint) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: navigate,
                  destinations: [
                    NavigationRailDestination(
                      icon: const Icon(Icons.today_outlined),
                      label: Text(labels.today),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.menu_book_outlined),
                      label: Text(labels.bible),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.event_note_outlined),
                      label: Text(labels.plans),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.insights_outlined),
                      label: Text(labels.statistics),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            ),
          );
        }

        return Scaffold(
          body: child,
          bottomNavigationBar: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: navigate,
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.today_outlined),
                label: labels.today,
              ),
              NavigationDestination(
                icon: const Icon(Icons.menu_book_outlined),
                label: labels.bible,
              ),
              NavigationDestination(
                icon: const Icon(Icons.event_note_outlined),
                label: labels.plans,
              ),
              NavigationDestination(
                icon: const Icon(Icons.insights_outlined),
                label: labels.statistics,
              ),
            ],
          ),
        );
      },
    );
  }
}
