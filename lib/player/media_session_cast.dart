import 'dart:async';

import 'models.dart';

enum CastCommandType { play, pause, next, previous, seek, setRepeat, setShuffle }

class CastCommand {
  const CastCommand(this.type, {this.position});
  final CastCommandType type;
  final Duration? position; // seek 用
}

/// 系统媒体广播抽象（ADR-003/ADR-014）。
abstract interface class MediaSessionCast {
  Future<void> init();

  /// init() 是否已经成功完成。未就绪时上层不应记录去重 key，
  /// 否则「首推被丢弃 + key 已写」会让这首歌整段生命周期都不再推送。
  bool get isReady;
  /// 没有正在播放的曲目时停用媒体会话，避免通知栏出现一张无信息的黑卡片。
  Future<void> deactivate();
  void updateNowPlaying(TrackMetadata meta);
  void updatePlayback({required bool playing, required Duration position, Duration? duration});
  void updateQueue(List<TrackMetadata> queue, {int? currentIndex});
  Stream<CastCommand> get commands;
}

/// 空实现：测试与未实现平台兜底。
class NullCast implements MediaSessionCast {
  @override
  Future<void> init() async {}
  @override
  bool get isReady => true;
  @override
  Future<void> deactivate() async {}
  @override
  void updateNowPlaying(TrackMetadata meta) {}
  @override
  void updatePlayback({required bool playing, required Duration position, Duration? duration}) {}
  @override
  void updateQueue(List<TrackMetadata> queue, {int? currentIndex}) {}
  @override
  Stream<CastCommand> get commands => const Stream.empty();
}
