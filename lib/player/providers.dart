import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/platform_focus.dart';
import 'audio_engine.dart';
import 'audio_focus_policy.dart';
import 'media_kit_engine.dart';

/// 进程级引擎单例。
///
/// **不能用 `ref.onDispose(engine.dispose)`**：Player 是昂贵的原生资源，
/// 一旦被 Riverpod 生命周期回收，仍在持有旧引用的 PlayerCore 调用
/// `play()/open()` 就会抛 `Assertion failed: "[Player] has been disposed"`。
///
/// 这里改为懒创建 + 永不主动销毁（进程退出时由系统回收原生资源）。
/// 同理，依赖它的 provider 必须用 `ref.read`，不能用 `ref.watch`，
/// 否则任何上游变化都会重建 consumer 并拿到已失效的引擎。
AudioEngine? _engineSingleton;

final engineProvider = Provider<AudioEngine>((ref) {
  return _engineSingleton ??= MediaKitEngine.create();
});

final focusPolicyProvider =
    Provider<AudioFocusPolicy>((ref) => createFocusPolicy());