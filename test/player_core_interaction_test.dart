import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:aiwli_music/player/audio_engine.dart';
import 'package:aiwli_music/player/models.dart';
import 'package:aiwli_music/player/player_core.dart';

class _Engine extends StubEngine {
  final ctrl = StreamController<EngineSnapshot>.broadcast();
  EngineSnapshot _snap = const EngineSnapshot();
  Uri? _src;
  int plays = 0;
  int pauses = 0;
  final seeks = <Duration>[];
  final loaded = <String>[];

  @override
  Future<Duration?> load(Uri source,
      {Map<String, String>? headers, String? formatHint}) async {
    _src = source;
    loaded.add(source.toString());
    return const Duration(minutes: 3);
  }

  @override
  Future<void> play() async {
    plays++;
    _snap = const EngineSnapshot(
        processing: EngineProcessing.ready,
        playing: true,
        duration: Duration(minutes: 3));
    ctrl.add(_snap);
  }

  @override
  Future<void> pause() async => pauses++;
  @override
  Future<void> seek(Duration position) async => seeks.add(position);
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

  void complete() => emit(const EngineSnapshot(
      processing: EngineProcessing.completed, playing: false));

  void emit(EngineSnapshot s) {
    _snap = s;
    ctrl.add(s);
  }
}

PlayerItem _item(String id) => PlayerItem(
      title: '歌$id',
      artist: '歌手',
      sourceId: 'local',
      musicId: '/$id.mp3',
      resolvedUrl: 'file:///$id.mp3',
    );

void main() {
  late _Engine engine;
  late PlayerCore core;

  setUp(() {
    engine = _Engine();
    core = PlayerCore(engine: engine);
  });
  tearDown(() async {
    await core.dispose();
    await engine.dispose();
  });

  test('清空队列必须真正停掉引擎并重置索引', () async {
    await core.setQueue([_item('a'), _item('b')]);
    await pump();
    expect(core.state.value.playing, isTrue);
    final before = engine.pauses;

    await core.setQueue([]);
    await pump();

    expect(engine.pauses, greaterThan(before), reason: '不能只改 UI 状态');
    expect(core.state.value.playing, isFalse);
    expect(core.current, isNull);
    expect(core.currentIndex, -1);
    expect(core.queueLength, 0);
  });

  test('逐条删到空也必须停播', () async {
    await core.setQueue([_item('a')]);
    await pump();
    final before = engine.pauses;

    await core.removeAt(0);
    await pump();

    expect(engine.pauses, greaterThan(before));
    expect(core.state.value.playing, isFalse);
  });

  test('定时「播完当前首」真停引擎，且标志用过即清', () async {
    await core.setQueue([_item('a'), _item('b')]);
    await pump();
    core.setEndOfTrackPause(true);

    engine.complete();
    await pump();
    expect(core.state.value.playing, isFalse);
    final pausesAfterFirst = engine.pauses;
    expect(pausesAfterFirst, greaterThan(0));

    // 手动切到下一首，播完时不应再被上一次的定时标志拦住：
    // 应该走正常的队列尾结束流程，而不是再次触发 _endOfTrackPause。
    await core.next();
    await pump();
    expect(core.current?.title, '歌b');
    engine.complete();
    await pump();
    expect(core.state.value.playing, isFalse);
    expect(engine.loaded, hasLength(2),
        reason: '标志已清，第二次 completed 不会误触发重载当前曲');
    expect(engine.pauses, pausesAfterFirst,
        reason: '第二次不应再走定时暂停分支');
  });

  test('seek 同步 UI 位置并转发给引擎', () async {
    await core.setQueue([_item('a')]);
    await pump();
    await core.seek(const Duration(seconds: 42));
    expect(engine.seeks, [const Duration(seconds: 42)]);
    expect(core.state.value.position, const Duration(seconds: 42));
  });
}

Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 10));
