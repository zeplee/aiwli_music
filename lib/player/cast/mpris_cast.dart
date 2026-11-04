import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_service_mpris/audio_service_mpris.dart';
import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:flutter/foundation.dart';

import '../media_session_cast.dart';
import '../models.dart';

/// Linux 桌面：走 MPRIS（D-Bus），由 audio_service_mpris 插件提供原生侧。
///
/// Linux 没有 Media3/MediaRemote，flutter_media_session 也不支持，
/// 所以单独一条路径。原生（D-Bus 对象注册）全在插件内，
/// 这里只把抽象翻译成插件调用。
class MprisCast implements MediaSessionCast {
  final _commands = StreamController<CastCommand>.broadcast();
  bool _ready = false;
  AudioServicePlatform? _platform;

  @override
  Stream<CastCommand> get commands => _commands.stream;

  @override
  Future<void> init() async {
    if (kIsWeb || !Platform.isLinux) return; // 防止在非 Linux 误初始化
    try {
      final platform = AudioServiceMpris();
      AudioServicePlatform.instance = platform;
      _platform = platform;
      await platform.configure(ConfigureRequest(
        config: AudioServiceConfigMessage(
          androidResumeOnClick: true,
          // MPRIS 用它当 D-Bus 名称与媒体播放器身份
          androidNotificationChannelId: 'com.aiwli.aiwli_music.channel.audio',
          androidNotificationChannelName: 'AiwliMusic',
          androidNotificationIcon: 'mipmap/ic_launcher',
        ),
      ));
      _ready = true;
    } catch (e) {
      debugPrint('[MprisCast] 初始化失败，系统媒体控制降级: $e');
    }
  }

  @override
  void updateNowPlaying(TrackMetadata meta) {
    final p = _platform;
    if (!_ready || p == null) return;
    p.setMediaItem(SetMediaItemRequest(
      mediaItem: MediaItemMessage(
        id: '${meta.title}/${meta.artist}',
        title: meta.title,
        artist: meta.artist,
        album: meta.album,
        duration: meta.duration,
        artUri: meta.artUri,
      ),
    ));
  }

  @override
  void updatePlayback({
    required bool playing,
    required Duration position,
    Duration? duration,
  }) {
    final p = _platform;
    if (!_ready || p == null) return;
    p.setState(SetStateRequest(
      state: PlaybackStateMessage(
        playing: playing,
        processingState: AudioProcessingStateMessage.ready,
        updatePosition: position,
        bufferedPosition: position,
        speed: 1.0,
      ),
    ));
  }

  @override
  void updateQueue(List<TrackMetadata> queue, {int? currentIndex}) {
    // MPRIS 插件的 setQueue 未实现（见包内 setQueue 的 log 说明），跳过。
  }
}
