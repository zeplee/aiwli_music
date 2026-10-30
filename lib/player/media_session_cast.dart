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
  void updateNowPlaying(TrackMetadata meta) {}
  @override
  void updatePlayback({required bool playing, required Duration position, Duration? duration}) {}
  @override
  void updateQueue(List<TrackMetadata> queue, {int? currentIndex}) {}
  @override
  Stream<CastCommand> get commands => const Stream.empty();
}
