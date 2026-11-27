import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:aiwli_music/player/audio_engine.dart';
import 'package:aiwli_music/player/media_session_cast.dart';
import 'package:aiwli_music/player/player_core.dart';
import 'package:aiwli_music/player/models.dart';

class _Engine extends StubEngine {
  final ctrl = StreamController<EngineSnapshot>.broadcast();
  @override
  Stream<EngineSnapshot> get snapshots => ctrl.stream;
  @override
  EngineSnapshot get current => const EngineSnapshot();
  @override
  Future<void> dispose() async => ctrl.close();
}

/// 模拟真实 FmsCast：init() 要等 platform channel，完成前
/// isReady=false 且 updateNowPlaying 会被静默丢弃。
class _DelayedCast implements MediaSessionCast {
  final Completer<void> gate = Completer<void>();
  bool ready = false;
  final nowPlaying = <TrackMetadata>[];
  final playback = <String>[];
  final commandsCtrl = StreamController<CastCommand>.broadcast();

  @override
  Future<void> init() async {
    await gate.future;
    ready = true;
  }

  @override
  bool get isReady => ready;

  @override
  void updateNowPlaying(TrackMetadata meta) {
    if (!ready) return; // 复刻 FmsCast 的 _activated 守卫
    nowPlaying.add(meta);
  }

  @override
  void updatePlayback({
    required bool playing,
    required Duration position,
    Duration? duration,
  }) {
    if (!ready) return;
    playback.add('$playing@${position.inMilliseconds}');
  }

  @override
  void updateQueue(List<TrackMetadata> queue, {int? currentIndex}) {}

  @override
  Stream<CastCommand> get commands => commandsCtrl.stream;

  Future<void> dispose() => commandsCtrl.close();
}

void main() {
  late _Engine engine;
  late _DelayedCast cast;
  late PlayerCore core;

  setUp(() {
    engine = _Engine();
    cast = _DelayedCast();
    core = PlayerCore(engine: engine, cast: cast);
  });

  tearDown(() async {
    if (!cast.gate.isCompleted) cast.gate.complete();
    await core.dispose();
    await cast.dispose();
    await engine.dispose();
  });

  test('init 未就绪时的首推不写去重 key，就绪后自动补推', () async {
    // 冷启动：先放一首真实曲目（走 setQueue → _loadAt），此时 activate()
    // 尚未返回，所有状态推送都被 cast 丢弃。
    await core.setQueue([
      PlayerItem(
        title: '测试曲',
        artist: '测试歌手',
        album: '测试专辑',
        sourceId: 'local',
        musicId: 'a.mp3',
        resolvedUrl: 'file:///a.mp3',
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(cast.nowPlaying, isEmpty, reason: '未激活时 cast 会丢弃推送');
    expect(cast.playback, isEmpty);

    // 同一首歌在 init 完成前又变了一次状态（旧实现会在这里被 key 挡掉）。
    core.state.value = core.state.value.copyWith(playing: false);
    await Future<void>.delayed(Duration.zero);

    cast.gate.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(cast.nowPlaying.length, 1,
        reason: 'init 完成后必须补推一次，否则通知栏整首歌都是空壳');
    expect(cast.nowPlaying.single.title, '测试曲');
    expect(cast.playback.length, 1);
  });

  test('init 就绪后状态变化仍按 key 去重，不会每帧重复推送', () async {
    cast.gate.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    core.state.value = core.state.value.copyWith(playing: true);
    await Future<void>.delayed(Duration.zero);
    final first = cast.playback.length;

    core.state.value = core.state.value.copyWith(playing: true);
    await Future<void>.delayed(Duration.zero);
    expect(cast.playback.length, first, reason: '同 key 不应重复推');
  });

  test('init 抛异常时 dispose 不受影响', () async {
    final bad = _ThrowingCast();
    final c = PlayerCore(engine: _Engine(), cast: bad);
    await Future<void>.delayed(Duration.zero);
    await expectLater(c.dispose(), completes);
  });
}

class _ThrowingCast implements MediaSessionCast {
  @override
  Future<void> init() async => throw StateError('no media session');
  @override
  bool get isReady => false;
  @override
  void updateNowPlaying(TrackMetadata meta) {}
  @override
  void updatePlayback({
    required bool playing,
    required Duration position,
    Duration? duration,
  }) {}
  @override
  void updateQueue(List<TrackMetadata> queue, {int? currentIndex}) {}
  @override
  Stream<CastCommand> get commands => const Stream.empty();
}
