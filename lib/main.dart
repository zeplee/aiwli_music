import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'app_providers.dart';
import 'core/services/logger.dart';
import 'platform/hotkeys.dart';

/// 入口：仅做初始化 + runApp（设计文档 §2；平台分支只允许出现在本文件与 platform/）。
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 日志落盘（release 包也要能取证：developer.log 不进 logcat）
  unawaited(AppLog.init());
  AppLog.installErrorHooks();
  MediaKit.ensureInitialized();

  // 液态玻璃着色器预热：只做磁盘→内存读取，不产生 GPU 绘制，
  // 所以不会拖慢首帧。失败不阻断启动（老设备可能不支持某些 shader）。
  try {
    await LiquidGlassWidgets.initialize(
      // release 包关掉帧率监控浮层，debug 下保留便于看降级情况。
      enablePerformanceMonitor: false,
    );
  } catch (e) {
    AppLog.w('liquid_glass', 'shader 预热失败，玻璃效果将降级: $e');
  }

  final container = ProviderContainer();
  // 桌面全局快捷键（Windows/macOS/Linux，失败静默降级）
  registerDesktopHotkeys(() => container.read(playerCoreProvider));
  runApp(UncontrolledProviderScope(
    container: container,
    child: const AiwliApp(),
  ));
}