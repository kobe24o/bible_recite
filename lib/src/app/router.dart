import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/scripture/presentation/passage_screen.dart';
import '../features/scripture/presentation/scripture_browser_screen.dart';
import '../features/scripture/presentation/scripture_sources_screen.dart';
import 'responsive_shell.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) {
        return const ResponsiveShell(
          child: Center(child: Text('Scripture Recite')),
        );
      },
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
        ),
      ),
    ),
    GoRoute(
      path: '/about/scripture-sources',
      builder: (context, state) =>
          const ResponsiveShell(child: ScriptureSourcesScreen()),
    ),
  ],
);
