import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'app_providers.dart';
import 'core/services/logger.dart';
import 'platform/hotkeys.dart';

/// 入口：仅做初始化 + runApp（设计文档 §2；平台分支只允许出现在本文件与 platform/）。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 日志落盘（release 包也要能取证：developer.log 不进 logcat）
  unawaited(AppLog.init());
  AppLog.installErrorHooks();
  MediaKit.ensureInitialized();
  final container = ProviderContainer();
  // 桌面全局快捷键（Windows/macOS/Linux，失败静默降级）
  registerDesktopHotkeys(() => container.read(playerCoreProvider));
  runApp(UncontrolledProviderScope(container: container, child: const AiwliApp()));
}
