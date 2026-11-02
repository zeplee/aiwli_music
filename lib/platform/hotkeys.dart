import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../player/player_core.dart';

/// 桌面全局快捷键（仅 Windows/macOS/Linux）：
/// Ctrl/Cmd+Alt+P 播放暂停，Ctrl/Cmd+Alt+← 上一首，Ctrl/Cmd+Alt+→ 下一首。
Future<void> registerDesktopHotkeys(PlayerCore Function() coreOf) async {
  if (kIsWeb) return;
  if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
  try {
    final modifier =
        Platform.isMacOS ? HotKeyModifier.meta : HotKeyModifier.control;
    final manager = HotKeyManager.instance;
    await manager.register(
      HotKey(
        key: PhysicalKeyboardKey.keyP,
        modifiers: [modifier, HotKeyModifier.alt],
        scope: HotKeyScope.system,
      ),
      keyDownHandler: (_) async {
        final core = coreOf();
        core.state.value.playing ? await core.pause() : await core.play();
      },
    );
    await manager.register(
      HotKey(
        key: PhysicalKeyboardKey.arrowRight,
        modifiers: [modifier, HotKeyModifier.alt],
        scope: HotKeyScope.system,
      ),
      keyDownHandler: (_) => coreOf().next(),
    );
    await manager.register(
      HotKey(
        key: PhysicalKeyboardKey.arrowLeft,
        modifiers: [modifier, HotKeyModifier.alt],
        scope: HotKeyScope.system,
      ),
      keyDownHandler: (_) => coreOf().previous(),
    );
  } catch (_) {
    // 部分桌面环境不允许注册全局热键，静默降级（不影响应用启动）
  }
}
