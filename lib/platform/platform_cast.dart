import '../player/cast/fms_cast.dart';
import '../player/cast/mpris_cast.dart';
import '../player/media_session_cast.dart';
import 'package:flutter/foundation.dart';

/// 唯一允许的平台分支点之一。M1 接真实实现；M0 返回各平台占位实现。
MediaSessionCast createCast() {
  final t = defaultTargetPlatform;
  if (t == TargetPlatform.linux) return MprisCast();
  return FmsCast();
}
