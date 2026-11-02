import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'audio_engine.dart';
import 'models.dart';

/// ADR-002：唯一引擎实现，包装 media_kit（libmpv）。
class MediaKitEngine implements AudioEngine {
  MediaKitEngine._(this._player) {
    _subs.addAll([
      _player.stream.playing.listen((p) => _emit(playing: p)),
      _player.stream.completed.listen((c) {
        if (c) _emit(processing: EngineProcessing.completed, playing: false);
      }),
      _player.stream.position.listen((pos) => _emit(position: pos)),
      _player.stream.duration.listen((d) => _emit(duration: d)),
      _player.stream.buffer.listen((b) => _emit(buffered: b)),
      _player.stream.error.listen((e) =>
          _emit(processing: EngineProcessing.error, playing: false, error: e)),
    ]);
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
  }) {
    _snapshot = EngineSnapshot(
      processing: processing ?? _snapshot.processing,
      playing: playing ?? _snapshot.playing,
      position: position ?? _snapshot.position,
      duration: duration ?? _snapshot.duration,
      buffered: buffered ?? _snapshot.buffered,
      speed: speed ?? _snapshot.speed,
      error: error ?? _snapshot.error,
    );
    if (!_controller.isClosed) _controller.add(_snapshot);
  }

  @override
  Future<Duration?> load(Uri source,
      {Map<String, String>? headers, String? formatHint}) async {
    _emit(processing: EngineProcessing.loading, playing: false, position: Duration.zero);
    await _player.open(Media(source.toString(), httpHeaders: headers ?? const {}));
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
