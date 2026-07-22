import 'package:go_router/go_router.dart';

import '../features/dashboard/presentation/today_screen.dart';
import '../features/update/presentation/about_screen.dart';
import '../features/plans/presentation/plans_screen.dart';
import '../features/recitation/presentation/recitation_practice_screen.dart';
import '../features/scripture/presentation/passage_screen.dart';
import '../features/scripture/presentation/scripture_browser_screen.dart';
import '../features/scripture/presentation/scripture_sources_screen.dart';
import '../features/statistics/presentation/statistics_screen.dart';
import 'responsive_shell.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const ResponsiveShell(child: TodayScreen()),
    ),
    GoRoute(
      path: '/bible',
      builder: (context, state) =>
          const ResponsiveShell(child: ScriptureBrowserScreen()),
    ),
    GoRoute(
      path: '/bible/:translation/:book/:chapter',
      builder: (context, state) => ResponsiveShell(
        child: PassageScreen(
          translationId: state.pathParameters['translation']!,
          bookId: state.pathParameters['book']!,
          chapter: int.parse(state.pathParameters['chapter']!),
          reviewId: state.extra is int ? state.extra! as int : null,
        ),
      ),
    ),
    GoRoute(
      path: '/plans',
      builder: (context, state) => const ResponsiveShell(child: PlansScreen()),
    ),
    GoRoute(
      path: '/recitation',
      builder: (context, state) => ResponsiveShell(
        child: RecitationPracticeScreen(
          request: state.extra! as RecitationRequest,
        ),
      ),
    ),
    GoRoute(
      path: '/statistics',
      builder: (context, state) =>
          const ResponsiveShell(child: StatisticsScreen()),
    ),
    GoRoute(
      path: '/about',
      builder: (context, state) => const ResponsiveShell(child: AboutScreen()),
    ),
    GoRoute(
      path: '/about/scripture-sources',
      builder: (context, state) =>
          const ResponsiveShell(child: ScriptureSourcesScreen()),
    ),
  ],
);
