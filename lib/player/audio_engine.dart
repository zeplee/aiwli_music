import 'models.dart';

/// 引擎抽象（ADR-002：唯一实现 MediaKitEngine）。
abstract interface class AudioEngine {
  Future<Duration?> load(
    Uri source, {
    Map<String, String>? headers, // UA / Referer，音源 URL 必需
    String? formatHint,
  });
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double v);

  /// 播放倍速（0.5–2.0）。media_kit 用 Player.setRate。
  Future<void> setSpeed(double v);

  /// 10 段均衡器（dB，对应 AppSettings.eqBandHz）；null/关 = 关闭。
  Future<void> setEqualizer(List<double>? gainsDb);

  Future<void> dispose();

  Stream<EngineSnapshot> get snapshots;
  EngineSnapshot get current;

  /// 当前（最后请求）加载的媒体地址。mpv 的错误/完成事件是【异步】的，
  /// 快速切歌时旧歌的迟到事件会在新歌 load 之后到达——
  /// 上层用 currentSource 比对，丢弃不属于当前曲目的陈旧事件。
  Uri? get currentSource;

  /// 最近一次被忽略的非致命警告（如 "Failed to recognize file format"）。
  /// 这类消息 mpv 会报，但音频通常仍能正常播放，不应展示给用户。
  String? get lastWarning;
}

/// M0/测试用空引擎：所有调用即记即忘，不发声。
class StubEngine implements AudioEngine {
  @override
  Future<Duration?> load(Uri source, {Map<String, String>? headers, String? formatHint}) async => null;
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double v) async {}
  @override
  Future<void> setSpeed(double v) async {}
  @override
  Future<void> setEqualizer(List<double>? gainsDb) async {}
  @override
  Future<void> dispose() async {}
  @override
  Stream<EngineSnapshot> get snapshots => const Stream.empty();
  @override
  EngineSnapshot get current => const EngineSnapshot();
  @override
  Uri? get currentSource => null;
  @override
  String? get lastWarning => null;
}
