import 'package:flutter_test/flutter_test.dart';
import 'package:aiwli_music/player/audio_engine.dart';
import 'package:aiwli_music/player/models.dart';
import 'package:aiwli_music/player/player_core.dart';

/// K 歌模式的状态与滤镜链构建规则。
void main() {
  test('PlayerUiState 默认不开 K 歌模式', () {
    expect(const PlayerUiState().karaokeMode, isFalse);
  });

  test('copyWith 能独立切换 karaokeMode 且不影响其他字段', () {
    const s = PlayerUiState(speed: 1.5, title: 'x', playing: true);
    final on = s.copyWith(karaokeMode: true);
    expect(on.karaokeMode, isTrue);
    expect(on.speed, 1.5);
    expect(on.title, 'x');
    expect(on.playing, isTrue);
  });

  test('karaokeMode 不会被无关 copyWith 意外重置', () {
    const s = PlayerUiState(karaokeMode: true);
    expect(s.copyWith(playing: false).karaokeMode, isTrue);
    expect(s.copyWith(position: Duration.zero).karaokeMode, isTrue);
  });

  test('setKaraokeMode 真的把开关传给引擎（UI 与引擎不能断链）', () async {
    final eng = _RecEngine();
    final core = PlayerCore(engine: eng);
    await core.setKaraokeMode(true);
    expect(core.state.value.karaokeMode, isTrue);
    expect(eng.vocalCalls, [true], reason: '引擎必须收到开');

    await core.setKaraokeMode(false);
    expect(core.state.value.karaokeMode, isFalse);
    expect(eng.vocalCalls, [true, false], reason: '引擎必须收到关');
    await core.dispose();
  });

  test('重复设同值不重复调用引擎（避免无谓重建滤镜链）', () async {
    final eng = _RecEngine();
    final core = PlayerCore(engine: eng);
    await core.setKaraokeMode(true);
    await core.setKaraokeMode(true);
    expect(eng.vocalCalls, [true], reason: '同值应直接返回');
    await core.dispose();
  });
}

/// 只记录去人声调用的最简引擎。
class _RecEngine implements AudioEngine {
  final vocalCalls = <bool>[];
  @override
  Future<void> setVocalRemoval(bool enabled,
      {double bassCompensationDb = 3}) async {
    vocalCalls.add(enabled);
  }

  @override
  Future<Duration?> load(Uri source,
          {Map<String, String>? headers, String? formatHint}) async =>
      null;
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
