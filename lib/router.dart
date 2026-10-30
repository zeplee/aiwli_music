import 'package:go_router/go_router.dart';

import 'features/shell/home_shell.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeShell()),
  ],
);
