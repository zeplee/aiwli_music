import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_providers.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class AiwliApp extends ConsumerWidget {
  const AiwliApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 跟随设置里的主题模式（system / light / dark）。
    // 用 ref.watch 而不是在 main 里写死：用户在设置里切换后要即时生效，
    // 不需要重启 App。
    final mode = ref.watch(appSettingsProvider).themeMode;
    return MaterialApp.router(
      title: 'AiwliMusic',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: switch (mode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      routerConfig: appRouter,
    );
  }
}