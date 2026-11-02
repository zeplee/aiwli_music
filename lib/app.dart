import 'package:flutter/material.dart';

import 'router.dart';
import 'theme/app_theme.dart';

class AiwliApp extends StatelessWidget {
  const AiwliApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Aiwli Music',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
    );
  }
}
