import 'dart:async';
import 'package:media_kit/media_kit.dart';

import 'audio_engine.dart';
import 'models.dart';

/// ADR-002：唯一引擎实现，包装 media_kit（libmpv）。
class MediaKitEngine implements AudioEngine {
  MediaKitEngine._(this._player) {
    _subs.addAll([
      _player.stream.playing.listen((p) => _emit(playing: p, clearError: p)),
      _player.stream.completed.listen((c) {
        if (c) _emit(processing: EngineProcessing.completed, playing: false);
      }),
      _player.stream.position.listen((pos) {
        // 进度在走 = 音频确实在播；此时任何残留错误都应清掉
        _emit(position: pos, clearError: true);
      }),
      _player.stream.duration.listen((d) => _emit(duration: d)),
      _player.stream.buffer.listen((b) => _emit(buffered: b)),
      _player.stream.error.listen(_onPlayerError),
    ]);
  }

  /// mpv 会把大量**非致命**问题也塞进 error 流（"Failed to recognize file
  /// format" 常见于 HLS/无扩展名流，实际已能正常出声）。把这些当致命错误
  /// 上报，就会造成「正在播放 + 底部报红字」并存。
  /// 只保留真正导致无法播放的错误类型。
  void _onPlayerError(String e) {
    final fatal = isFatalError(e);
    if (!fatal) {
      // 非致命：记日志即可，不污染 UI 状态
      _lastWarning = e;
      // ignore: avoid_print
      print('[MediaKitEngine] 忽略非致命警告: $e');
      return;
    }
    _emit(processing: EngineProcessing.error, playing: false, error: e);
  }

  /// 最近一次被忽略的非致命警告（排障用）。
  String? _lastWarning;
  @override
  String? get lastWarning => _lastWarning;

  /// 判断 mpv 错误是否致命（公开用于测试；生产逻辑只经由 [_onPlayerError]）。
  static bool isFatalError(String e) => _isFatal(e);

  static bool _isFatal(String e) {
    final lower = e.toLowerCase();
    // 明确无法打开/解码 → 致命（这些确实放不出声）
    const fatalMarkers = [
      'failed to open',
      'failed to initialize',
      'no audio or video data',
      'cannot open',
      'unable to open',
      'failed to decode audio',
      'error opening',
      'unsupported',
      'http error',
      '403 forbidden',
      '404 not found',
    ];
    // 只是"识别不出容器/格式"，但 mpv 仍能播出声音 → 非致命
    const benignMarkers = [
      'failed to recognize file format',
      'could not recognize',
      'unknown format',
      'no extension',
      'unrecognized',
    ];
    if (benignMarkers.any(lower.contains)) return false;
    return fatalMarkers.any(lower.contains);
  }

  static bool _initialized = false;

  static MediaKitEngine create() {
    if (!_initialized) {
      MediaKit.ensureInitialized();
      _initialized = true;
    }
    return MediaKitEngine._(Player());
  }

  final Player _player;
  final List<StreamSubscription<dynamic>> _subs = [];

  /// 最后请求加载的媒体（load() 同步赋值，早于 mpv 的任何异步事件）。
  Uri? _source;
  @override
  Uri? get currentSource => _source;

  EngineSnapshot _snapshot = const EngineSnapshot();
  final _controller = StreamController<EngineSnapshot>.broadcast();

  void _emit({
    EngineProcessing? processing,
    bool? playing,
    Duration? position,
    Duration? duration,
    Duration? buffered,
    double? speed,
    Object? error,
    /// true 表示显式把错误清空（播放恢复后必须清，否则红字永远挂在那）。
    bool clearError = false,
  }) {
    _snapshot = EngineSnapshot(
      processing: processing ?? _snapshot.processing,
      playing: playing ?? _snapshot.playing,
      position: position ?? _snapshot.position,
      duration: duration ?? _snapshot.duration,
      buffered: buffered ?? _snapshot.buffered,
      speed: speed ?? _snapshot.speed,
      error: clearError ? null : (error ?? _snapshot.error),
    );
    if (!_controller.isClosed) _controller.add(_snapshot);
  }

  @override
  Future<Duration?> load(Uri source,
      {Map<String, String>? headers, String? formatHint}) async {
    _source = source; // 同步赋值：旧歌的迟到异步事件靠它丢弃
    _emit(processing: EngineProcessing.loading, playing: false, position: Duration.zero);
    final src = source.toString();
    await _tuneNetworkCache(src);
    await _player.open(Media(src, httpHeaders: headers ?? const {}));
    _emit(processing: EngineProcessing.ready);
    return _player.state.duration;
  }

  @override
  Future<void> play() async {
    _emit(playing: true);
    await _player.play();
  }

  @override
  Future<void> pause() async {
    _emit(playing: false);
    await _player.pause();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double v) => _player.setVolume(v * 100);

  @override
  Future<void> setSpeed(double v) async {
    final r = v.clamp(0.5, 2.0);
    await _player.setRate(r);
    _emit(speed: r);
  }

  @override
  Future<void> setEqualizer(List<double>? gainsDb) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    if (gainsDb == null || gainsDb.every((g) => g == 0)) {
      await platform.setProperty('af', '');
      return;
    }
    // 10 段 peaking EQ 链（lavfi equalizer），Hz 对应 AppSettings.eqBandHz
    final hz = const [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
    final chain = <String>[];
    for (var i = 0; i < gainsDb.length && i < hz.length; i++) {
      final g = gainsDb[i].clamp(-12.0, 12.0);
      chain.add('equalizer=f=${hz[i]}:w=1.0:t=q:g=${g.toStringAsFixed(2)}');
    }
    await platform.setProperty('af', chain.join(','));
  }

  /// 网络音源的缓冲调优。
  ///
  /// mpv 默认 cache=auto 在网络流上偏保守（几秒），遇到源站响应慢、
  /// 或 App 退到后台被限流时容易 underrun → 音频一卡一卡。
  /// 这里把缓冲窗口放大到 30s，并允许 mpv 在网速不够时降档播放
  /// （而不是直接断流）。
  ///
  /// 只对 http(s) 生效：本地文件不需要，且 cache 在本地文件上
  /// 反而会增加首播延迟。
  Future<void> _tuneNetworkCache(String source) async {
    if (!source.startsWith('http')) return;
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      // 预读窗口：缓存 30 秒数据（默认 auto 常常只有 1~5 秒）
      await platform.setProperty('cache', 'yes');
      await platform.setProperty('cache-secs', '30');
      // 缓冲不足时继续读，不要中途放弃（弱网容忍）
      await platform.setProperty('cache-pause-initial', 'yes');
      await platform.setProperty('cache-pause-wait', '3');
      // 网络超时放宽：源站偶尔几秒不响应不应判死
      await platform.setProperty('network-timeout', '60');
      // 音频流按需降档，避免瞬间断流
      await platform.setProperty('demuxer-max-bytes', '32MiB');
      await platform.setProperty('demuxer-max-back-bytes', '8MiB');
    } catch (_) {
      // 老版本 mpv 没有这些属性：忽略，播放本身不受影响
    }
  }

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _controller.close();
    await _player.dispose();
  }

  @override
  Stream<EngineSnapshot> get snapshots => _controller.stream;

  @override
  EngineSnapshot get current => _snapshot;
}
