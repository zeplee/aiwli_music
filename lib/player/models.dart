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

/// 播放模式三态（一个按钮循环切换）。
///
/// 为什么把原来的「循环」+「随机」两个独立按钮合并：
///   · 它们是**互斥**的用户意图，不该各占一个角、同时亮起
///   · 主流播放器（网易云 / QQ 音乐）都是一个按钮循环三态
///   · 两个按钮分居左右下角，中间夹着上一曲/暂停/下一曲，
///     手指从中心往外够，命中率低
///
/// 映射到既有状态机：
///   sequential → repeat=off,  shuffle=false   播完停
///   repeatOne  → repeat=one,  shuffle=false   单曲循环
///   shuffle    → repeat=all,  shuffle=true    随机（不重复当前）
enum PlayMode { sequential, repeatOne, shuffle }

extension PlayModeX on PlayMode {
  RepeatMode get repeatMode => switch (this) {
        PlayMode.sequential => RepeatMode.off,
        PlayMode.repeatOne => RepeatMode.one,
        PlayMode.shuffle => RepeatMode.all,
      };

  bool get shuffleOn => this == PlayMode.shuffle;

  /// 从既有状态反推三态（shuffle 优先：它一旦开启就压过 repeat）
  static PlayMode from({required RepeatMode repeat, required bool shuffle}) {
    if (shuffle) return PlayMode.shuffle;
    if (repeat == RepeatMode.one) return PlayMode.repeatOne;
    return PlayMode.sequential;
  }

  PlayMode get next => switch (this) {
        PlayMode.sequential => PlayMode.repeatOne,
        PlayMode.repeatOne => PlayMode.shuffle,
        PlayMode.shuffle => PlayMode.sequential,
      };
}

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
    this.buffered = Duration.zero,
    this.karaokeMode = false,
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

  /// K 歌模式：消除人声只留伴奏（立体声相减实现）。
  /// 不是真·音源分离，属于"能用"级别的近似——见 MediaKitEngine
  /// 里 setVocalRemoval 的注释。
  final bool karaokeMode;

  /// 已缓冲到的位置（进度条浅色叠加用）。
  final Duration buffered;

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
    Duration? buffered,
    bool? karaokeMode,
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
      buffered: buffered ?? this.buffered,
      karaokeMode: karaokeMode ?? this.karaokeMode,
    );
  }
}
