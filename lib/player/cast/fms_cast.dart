import '../media_session_cast.dart';
import '../models.dart';

/// ADR-014：flutter_media_session 广播（Android/iOS/macOS/Windows/Web）。
/// M1/M5 落地真实实现；M0 提供可编译的空实现。
class FmsCast implements MediaSessionCast {
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
