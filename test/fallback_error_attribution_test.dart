import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:aiwli_music/player/audio_engine.dart';
import 'package:aiwli_music/player/models.dart';
import 'package:aiwli_music/player/playback_resolver.dart';
import 'package:aiwli_music/player/player_core.dart';

class _Engine implements AudioEngine {
  final ctrl = StreamController<EngineSnapshot>.broadcast();
  EngineSnapshot _snap = const EngineSnapshot();
  Uri? _src;
  final loaded = <String>[];

  @override
  Future<Duration?> load(Uri source,
      {Map<String, String>? headers, String? formatHint}) async {
    loaded.add(source.toString());
    _src = source;
    return const Duration(minutes: 3);
  }

  @override
  Future<void> play() async {
    _snap = const EngineSnapshot(
        processing: EngineProcessing.ready,
        playing: true,
        duration: Duration(minutes: 3));
    ctrl.add(_snap);
  }

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
  Future<void> dispose() async => ctrl.close();
  @override
  Stream<EngineSnapshot> get snapshots => ctrl.stream;
  @override
  EngineSnapshot get current => _snap;
  @override
  Uri? get currentSource => _src;
  @override
  String? get lastWarning => null;

  void error(String url) {
    _snap = EngineSnapshot(
        processing: EngineProcessing.error,
        playing: false,
        error: 'Failed to open $url');
    ctrl.add(_snap);
  }
}

ResolvedPlayback _resolved(String url, String id) => ResolvedPlayback(
      url: url,
      sourceId: 'kw',
      winnerId: id,
      winnerPlatform: 'kw',
      sourceLabel: '酷我',
      musicId: '1',
      title: '歌',
      artist: '歌手',
    );

PlayerItem _item() => PlayerItem(
      title: '歌',
      artist: '歌手',
      sourceId: 'kw',
      musicId: '1',
    );

void main() {
  late _Engine engine;

  setUp(() => engine = _Engine());
  tearDown(() => engine.dispose());

  test('换源成功后的旧链残留 error 仍然被吞掉', () async {
    var round = 0;
    final core = PlayerCore(
      engine: engine,
      urlResolver: (item, exclude) async {
        round++;
        return _resolved(round == 1
            ? 'https://old.example/a.mp3'
            : 'https://new.example/a.mp3', '源$round');
      },
      onSourceUnplayable: (r, e) {},
    );

    await core.setQueue([_item()]);
    await pump();
    expect(engine.loaded, ['https://old.example/a.mp3']);

    engine.error('https://old.example/a.mp3');
    await pump();
    expect(engine.loaded, [
      'https://old.example/a.mp3',
      'https://new.example/a.mp3',
    ]);

    // 旧链迟到的 error 不应再弹红条。
    engine.error('https://old.example/a.mp3');
    await pump();
    expect(core.state.value.error, isNull);
    expect(core.state.value.processing, isNot(EngineProcessing.error));

    await core.dispose();
  });

  test('换源成功后【新链】再次失败必须可见，不能被布尔标志吞掉', () async {
    var round = 0;
    final core = PlayerCore(
      engine: engine,
      urlResolver: (item, exclude) async {
        round++;
        if (round == 1) return _resolved('https://old.example/a.mp3', '源1');
        if (round == 2) return _resolved('https://new.example/a.mp3', '源2');
        throw StateError('没有更多源了');
      },
      onSourceUnplayable: (r, e) {},
    );

    await core.setQueue([_item()]);
    await pump();
    engine.error('https://old.example/a.mp3');
    await pump();
    expect(engine.loaded.last, 'https://new.example/a.mp3');
    expect(core.state.value.error, isNull, reason: '换源成功不留红条');

    // 新地址随后真的失败：早期 _fallbackDone=true 会把这条吞成
    // error=null + playing=false，用户看到「显示播放中却没声音」。
    engine.error('https://new.example/a.mp3');
    await pump();

    expect(core.state.value.error, isNotNull,
        reason: '所有源耗尽后必须让用户看见失败，而不是静默停住');
    expect(core.state.value.processing, EngineProcessing.error);

    await core.dispose();
  });
}

Future<void> pump() async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
}
