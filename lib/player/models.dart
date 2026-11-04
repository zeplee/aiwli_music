enum EngineProcessing { idle, loading, buffering, ready, completed, error }

class EngineSnapshot {
  const EngineSnapshot({
    this.processing = EngineProcessing.idle,
    this.playing = false,
    this.position = Duration.zero,
    this.duration,
    this.buffered = Duration.zero,
    this.speed = 1.0,
    this.error,
  });
  final EngineProcessing processing;
  final bool playing;
  final Duration position;
  final Duration? duration;
  final Duration buffered;
  final double speed;
  final Object? error;
}

enum RepeatMode { off, all, one }

/// 给系统媒体层展示的曲目元数据。
class TrackMetadata {
  const TrackMetadata({
    required this.title,
    required this.artist,
    this.album,
    this.duration,
    this.artUri,
  });
  final String title;
  final String artist;
  final String? album;
  final Duration? duration;
  final Uri? artUri;
}

class PlayerUiState {
  const PlayerUiState({
    this.processing = EngineProcessing.idle,
    this.playing = false,
    this.position = Duration.zero,
    this.duration,
    this.title = '',
    this.artist = '',
    this.error,
    this.repeatMode = RepeatMode.off,
    this.shuffleOn = false,
    this.speed = 1.0,
  });
  final EngineProcessing processing;
  final bool playing;
  final Duration position;
  final Duration? duration;
  final String title;
  final String artist;
  final Object? error;
  final RepeatMode repeatMode;
  final bool shuffleOn;
  final double speed;

  PlayerUiState copyWith({
    EngineProcessing? processing,
    bool? playing,
    Duration? position,
    Duration? duration,
    String? title,
    String? artist,
    Object? error,
    /// 显式清空错误。copyWith 无法用 null 表达"清空"（null 表示"不改"），
    /// 否则一旦报过错就永远挂着红字——这正是"播放成功仍显示错误"的根因。
    bool clearError = false,
    RepeatMode? repeatMode,
    bool? shuffleOn,
    double? speed,
  }) {
    return PlayerUiState(
      processing: processing ?? this.processing,
      playing: playing ?? this.playing,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      error: clearError ? null : (error ?? this.error),
      repeatMode: repeatMode ?? this.repeatMode,
      shuffleOn: shuffleOn ?? this.shuffleOn,
      speed: speed ?? this.speed,
    );
  }
}
