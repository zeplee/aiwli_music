import 'dart:async';

import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'app_providers.dart';
import 'core/services/logger.dart';
import 'platform/hotkeys.dart';

/// 调试入口：与 main.dart 相同的初始化 + Flutter Driver 扩展。
/// 用于 dart mcp（flutter_driver_command）自动点击/输入与验收。
void main() {
  enableFlutterDriverExtension();
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(AppLog.init());
  AppLog.installErrorHooks();
  MediaKit.ensureInitialized();
  final container = ProviderContainer();
  registerDesktopHotkeys(() => container.read(playerCoreProvider));
  runApp(
      UncontrolledProviderScope(container: container, child: const AiwliApp()));
}