import 'package:go_router/go_router.dart';

import '../features/dashboard/presentation/today_screen.dart';
import '../features/update/presentation/about_screen.dart';
import '../features/plans/presentation/plans_screen.dart';
import '../features/quiz/presentation/quiz_practice_request.dart';
import '../features/quiz/presentation/quiz_practice_screen.dart';
import '../features/recitation/presentation/recitation_practice_screen.dart';
import '../features/scripture/presentation/passage_screen.dart';
import '../features/scripture/presentation/scripture_browser_screen.dart';
import '../features/scripture/presentation/scripture_sources_screen.dart';
import '../features/statistics/presentation/statistics_screen.dart';
import '../features/statistics/presentation/recitation_map_screen.dart';
import '../features/statistics/presentation/recitation_timeline_screen.dart';
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
          initialVerse: int.tryParse(state.uri.queryParameters['verse'] ?? ''),
          initialEndVerse: int.tryParse(
            state.uri.queryParameters['endVerse'] ?? '',
          ),
          initialEndChapter: int.tryParse(
            state.uri.queryParameters['endChapter'] ?? '',
          ),
          searchQuery: state.uri.queryParameters['search'],
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
      path: '/quiz',
      builder: (context, state) => ResponsiveShell(
        child: QuizPracticeScreen(request: state.extra! as QuizPracticeRequest),
      ),
    ),
    GoRoute(
      path: '/statistics',
      builder: (context, state) =>
          const ResponsiveShell(child: StatisticsScreen()),
    ),
    GoRoute(
      path: '/statistics/data',
      builder: (context, state) => const ResponsiveShell(
        child: StatisticsScreen(view: StatisticsScreenView.learningData),
      ),
    ),
    GoRoute(
      path: '/statistics/achievements',
      builder: (context, state) => const ResponsiveShell(
        child: StatisticsScreen(view: StatisticsScreenView.achievements),
      ),
    ),
    GoRoute(
      path: '/statistics/map',
      builder: (context, state) => ResponsiveShell(
        child: RecitationMapScreen(
          translationId: state.uri.queryParameters['translation'],
          testament: state.uri.queryParameters['testament'],
          bookId: state.uri.queryParameters['book'],
          chapter: int.tryParse(state.uri.queryParameters['chapter'] ?? ''),
        ),
      ),
    ),
    GoRoute(
      path: '/statistics/timeline',
      builder: (context, state) =>
          const ResponsiveShell(child: RecitationTimelineScreen()),
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
