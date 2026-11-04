import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_media_session/flutter_media_session.dart';

import '../media_session_cast.dart';
import '../models.dart';

/// ADR-014：flutter_media_session 系统媒体广播。
///
/// Android / iOS / macOS / Windows / Web 共用（Linux 走 [MprisCast]）。
/// 原生实现（前台 Service、Media3 MediaSession、通知卡片）全在插件内，
/// 工程侧不需要任何平台代码——这里只做抽象到插件 API 的翻译。
///
/// 关键点：**「播放的是什么」以插件的 metadata/state 为准**，所以每次
/// 状态变化都必须显式 update，否则锁屏会显示上一首（陈旧信息）。
class FmsCast implements MediaSessionCast {
  final _session = FlutterMediaSession();
  final _commands = StreamController<CastCommand>.broadcast();
  bool _activated = false;

  @override
  Stream<CastCommand> get commands => _commands.stream;

  @override
  Future<void> init() async {
    try {
      // Android 上会顺带申请通知权限（POST_NOTIFICATIONS）
      await _session.activate();
      // 来电 / 拔耳机自动暂停与恢复（插件内置，无需自己接 audio_session 事件流）
      await _session.setAutoHandleInterruptions(true);
      _activated = true;

      _session.setActionHandler(
        onPlay: () => _emit(CastCommandType.play),
        onPause: () => _emit(CastCommandType.pause),
        onSkipToNext: () => _emit(CastCommandType.next),
        onSkipToPrevious: () => _emit(CastCommandType.previous),
        onSeekTo: (pos) =>
            _emit(CastCommandType.seek, position: pos),
        onStop: () => _emit(CastCommandType.pause),
      );
    } catch (e) {
      // 会话不可用（如测试环境/无系统媒体中心的平台）：静默降级，
      // 播放功能本身不受影响。
      debugPrint('[FmsCast] init 失败，媒体广播降级: $e');
    }
  }

  void _emit(CastCommandType type, {Duration? position}) {
    if (!_commands.isClosed) {
      _commands.add(CastCommand(type, position: position));
    }
  }

  @override
  void updateNowPlaying(TrackMetadata meta) {
    if (!_activated) return;
    FlutterMediaSessionPlatform.instance.updateMetadata(MediaMetadata(
      title: meta.title,
      artist: meta.artist,
      album: meta.album,
      artworkUri: meta.artUri?.toString(),
      duration: meta.duration,
    ));
  }

  @override
  void updatePlayback({
    required bool playing,
    required Duration position,
    Duration? duration,
  }) {
    if (!_activated) return;
    FlutterMediaSessionPlatform.instance.updatePlaybackState(PlaybackState(
      status: playing ? PlaybackStatus.playing : PlaybackStatus.paused,
      position: position,
    ));
  }

  @override
  void updateQueue(List<TrackMetadata> queue, {int? currentIndex}) {
    // flutter_media_session 的队列由 Media3 侧自行维护，这里不做映射：
    // 传入的队列是解析前条目（可能还没 URL），映射过去反而会让
    // 系统控件显示不可播放的历史项。
  }
}
