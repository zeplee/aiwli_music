import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

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
    final app = MaterialApp.router(
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

    // LiquidGlassWidgets.wrap 负责三件事：
    //   1. 把 Material 的 ThemeMode 桥接给玻璃层（否则深色模式下阴影/描边会消失）
    //   2. adaptiveQuality：启动时基准测试设备，慢机自动降到 minimal，
    //      过热降级、降温恢复——这是它能安全用在低端 Android 上的前提
    //   3. 全局玻璃主题
    return LiquidGlassWidgets.wrap(
      child: app,
      // MaterialApp 用户必须传这个，否则玻璃读的是系统亮度而不是主题亮度
      brightnessResolver: Theme.maybeBrightnessOf,
      adaptiveQuality: true,
      respectSystemAccessibility: true, // 跟随「减弱动态效果」「增强对比度」
    );
  }
}