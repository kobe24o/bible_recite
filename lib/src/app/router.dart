import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'responsive_shell.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) {
        return const ResponsiveShell(child: SizedBox.shrink());
      },
    ),
  ],
);
