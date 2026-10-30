import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/platform_focus.dart';
import 'audio_engine.dart';
import 'audio_focus_policy.dart';
import 'media_kit_engine.dart';

/// 全局唯一的引擎与焦点策略（App 生命周期内单例）。
final engineProvider = Provider<AudioEngine>((ref) {
  final engine = MediaKitEngine.create();
  ref.onDispose(engine.dispose);
  return engine;
});

final focusPolicyProvider =
    Provider<AudioFocusPolicy>((ref) => createFocusPolicy());
