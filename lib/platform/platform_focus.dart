import 'package:flutter/foundation.dart';

import '../player/audio_focus_policy.dart';

/// 唯一允许的平台分支点之一（设计文档 §2 强制规则）。
AudioFocusPolicy createFocusPolicy() {
  final t = defaultTargetPlatform;
  if (t == TargetPlatform.windows || t == TargetPlatform.linux) {
    return DesktopNoopFocus();
  }
  return MobileAudioFocus();
}
