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

  PlayerUiState copyWith({
    EngineProcessing? processing,
    bool? playing,
    Duration? position,
    Duration? duration,
    String? title,
    String? artist,
    Object? error,
    RepeatMode? repeatMode,
    bool? shuffleOn,
  }) {
    return PlayerUiState(
      processing: processing ?? this.processing,
      playing: playing ?? this.playing,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      error: error,
      repeatMode: repeatMode ?? this.repeatMode,
      shuffleOn: shuffleOn ?? this.shuffleOn,
    );
  }
}
