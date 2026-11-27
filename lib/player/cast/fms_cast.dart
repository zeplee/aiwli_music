import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter_media_session/flutter_media_session.dart';

import '../../core/services/app_paths.dart';
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
  int _artGeneration = 0;

  @override
  bool get isReady => _activated;

  @override
  Future<void> deactivate() async {
    if (!_activated) return;
    try {
      await _session.deactivate();
    } catch (e) {
      debugPrint('[FmsCast] deactivate 失败: $e');
    }
    _activated = false;
    _artGeneration++;
  }

  @override
  Stream<CastCommand> get commands => _commands.stream;

  @override
  Future<void> init() async {
    try {
      // Android 上会顺带申请通知权限（POST_NOTIFICATIONS）
      await _session.activate();
      // 来电 / 拔耳机自动暂停与恢复（插件内置，无需自己接 audio_session 事件流）
      await _session.setAutoHandleInterruptions(true);

      // 后台播放抗卡顿（关键）。
      //
      // 插件文档：背景保活会持有一把 partial wake lock（CPU）+
      // high-perf Wi-Fi lock（射频），并把 Service 钉在前台，
      // **整个会话期间有效，不随播放/暂停降级**。
      // 不开的话：App 退到后台 → Service 被降级 → Android 的
      // cached-app freezer 冻结进程 → decoders 停摆 → 音频一卡一卡。
      // 默认是 false（为了省电），音乐播放器必须开。
      await _session.setBackgroundKeepAlive(true);
      // 先注册 action handler，再置 _activated=true。
      // 否则存在「isReady 已为 true、但系统控件回调还没挂上」的窗口：
      // 此时推送的 metadata 可能带着未初始化的通知一起丢失。
      _session.setActionHandler(
        onPlay: () => _emit(CastCommandType.play),
        onPause: () => _emit(CastCommandType.pause),
        onSkipToNext: () => _emit(CastCommandType.next),
        onSkipToPrevious: () => _emit(CastCommandType.previous),
        onSeekTo: (pos) => _emit(CastCommandType.seek, position: pos),
        onStop: () => _emit(CastCommandType.pause),
      );
      _activated = true;
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
    // 本地封面只有字节，插件 MediaMetadata 只收 artworkUri。
    // 异步落文件后用 generation 防止慢写入覆盖新切到的歌。
    final bytes = meta.artBytes;
    if (bytes != null && bytes.isNotEmpty) {
      final gen = ++_artGeneration;
      unawaited(_pushWithLocalArt(meta, bytes, gen));
      return;
    }
    _artGeneration++;
    final url = meta.artUri;
    // 只有 http(s) 网络图或已存在的本地文件才交给 Media3 解码；
    // 非法/不支持的 scheme（如 data:、svg 源）传过去只会得到黑色占位。
    final artwork = (url != null &&
            (url.scheme == 'http' ||
                url.scheme == 'https' ||
                url.scheme == 'file'))
        ? url.toString()
        : null;
    _push(meta, artwork);
  }

  Future<void> _pushWithLocalArt(
      TrackMetadata meta, Uint8List bytes, int gen) async {
    String? path;
    try {
      final dir = await AppPaths.supportDir();
      // 固定文件名：同一时刻只有一首歌在用，且切歌时会整体覆盖，
      // 避免每首歌都留一个缓存文件。
      final f = File('$dir/notification_art.bin');
      await f.writeAsBytes(bytes, flush: false);
      path = f.uri.toString();
    } catch (e) {
      debugPrint('[FmsCast] 本地封面落盘失败: $e');
      // 落盘失败也要把标题/歌手推给系统，不能整条 metadata 丢掉。
      path = meta.artUri?.toString();
    }
    if (gen != _artGeneration || !_activated) return;
    _push(meta, path);
  }

  void _push(TrackMetadata meta, String? artworkUri) {
    FlutterMediaSessionPlatform.instance.updateMetadata(MediaMetadata(
      title: meta.title,
      artist: meta.artist,
      album: meta.album,
      artworkUri: artworkUri,
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
