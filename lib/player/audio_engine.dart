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
  Future<void> dispose();

  Stream<EngineSnapshot> get snapshots;
  EngineSnapshot get current;
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
  Future<void> dispose() async {}
  @override
  Stream<EngineSnapshot> get snapshots => const Stream.empty();
  @override
  EngineSnapshot get current => const EngineSnapshot();
}
