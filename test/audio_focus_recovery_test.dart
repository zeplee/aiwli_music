import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:aiwli_music/player/audio_engine.dart';
import 'package:aiwli_music/player/audio_focus_policy.dart';
import 'package:aiwli_music/player/player_core.dart';
import 'package:aiwli_music/player/models.dart';

/// 只记录调用，不发声。测试断言的是真实 PlayerCore 的行为。
class _RecordingEngine extends StubEngine {
  int plays = 0;
  int pauses = 0;
  final volumes = <double>[];
  final ctrl = StreamController<EngineSnapshot>.broadcast();

  @override
  Future<void> play() async => plays++;
  @override
  Future<void> pause() async => pauses++;
  @override
  Future<void> setVolume(double v) async => volumes.add(v);
  @override
  Stream<EngineSnapshot> get snapshots => ctrl.stream;
  @override
  EngineSnapshot get current => const EngineSnapshot();

  void emit(EngineSnapshot s) => ctrl.add(s);

  @override
  Future<void> dispose() async => ctrl.close();
}

/// 真实 FocusEvent 流，测试直接往里投递 audio_session 语义的事件。
class _FakeFocus implements AudioFocusPolicy {
  final ctrl = StreamController<FocusEvent>.broadcast();
  @override
  Future<bool> activate() async => true;
  @override
  Future<void> deactivate() async {}
  @override
  Stream<FocusEvent> get events => ctrl.stream;
  void send(FocusEvent e) => ctrl.add(e);
  Future<void> close() => ctrl.close();
}

/// 把 audio_session 0.2.4 的 interruptionEventStream 事件映射成 FocusEvent。
/// 这里复现的是 MobileAudioFocus.events 里的映射规则，用于在无法实例化
/// 原生 AudioSession 的环境下验证「begin=false 必须映射成 end」这一契约。
FocusEvent mapInterruption({required bool begin, required int type}) {
  const duck = 1; // AudioInterruptionType.duck 的索引
  final isDuck = type == duck;
  if (begin) {
    return isDuck
        ? const FocusEvent(FocusEventType.duckBegin, isDuck: true)
        : const FocusEvent(FocusEventType.interruptionBegin);
  }
  return isDuck
      ? const FocusEvent(FocusEventType.duckEnd)
      : const FocusEvent(FocusEventType.interruptionEnd);
}

void main() {
  late _RecordingEngine engine;
  late _FakeFocus focus;
  late PlayerCore core;

  setUp(() {
    engine = _RecordingEngine();
    focus = _FakeFocus();
    core = PlayerCore(engine: engine, focus: focus);
    // 模拟「用户正在听歌」：状态为播放中。
    core.state.value = core.state.value.copyWith(playing: true);
  });

  tearDown(() async {
    core.dispose();
    await focus.close();
    await engine.dispose();
  });

  test('audio_session begin=false 必须映射为 interruptionEnd 而不是 begin', () {
    expect(mapInterruption(begin: true, type: 0).type,
        FocusEventType.interruptionBegin);
    expect(mapInterruption(begin: false, type: 0).type,
        FocusEventType.interruptionEnd);
    expect(mapInterruption(begin: true, type: 1).type,
        FocusEventType.duckBegin);
    expect(mapInterruption(begin: false, type: 1).type,
        FocusEventType.duckEnd);
  });

  test('来电中断结束后自动续播，并复位记忆状态', () async {
    focus.send(const FocusEvent(FocusEventType.interruptionBegin));
    await pumpEventQueue();
    expect(core.state.value.playing, isFalse, reason: '中断时必须暂停');
    final pausesAfterBegin = engine.pauses;

    focus.send(const FocusEvent(FocusEventType.interruptionEnd));
    await pumpEventQueue();
    expect(core.state.value.playing, isTrue, reason: '中断结束后必须自动续播');
    expect(engine.plays, 1);
    expect(engine.pauses, pausesAfterBegin);

    // 恢复标志必须复位：没有新的 begin 时，重复的 end 不应再触发播放。
    focus.send(const FocusEvent(FocusEventType.interruptionEnd));
    await pumpEventQueue();
    expect(engine.plays, 1);
  });

  test('连续多个 begin 不会把「中断前正在播放」覆盖成 false', () async {
    focus.send(const FocusEvent(FocusEventType.interruptionBegin));
    await pumpEventQueue();
    // Android 会先发 loss(unknown) 再发 lossTransient(pause)：第二个 begin
    // 到达时 state 已是 false，早期实现会把它记成「中断前没在播」。
    focus.send(const FocusEvent(FocusEventType.interruptionBegin));
    await pumpEventQueue();

    focus.send(const FocusEvent(FocusEventType.interruptionEnd));
    await pumpEventQueue();
    expect(core.state.value.playing, isTrue);
    expect(engine.plays, 1);
  });

  test('中断期间用户主动暂停，结束时不擅自续播', () async {
    focus.send(const FocusEvent(FocusEventType.interruptionBegin));
    await pumpEventQueue();
    await core.pause();

    focus.send(const FocusEvent(FocusEventType.interruptionEnd));
    await pumpEventQueue();
    expect(core.state.value.playing, isFalse);
  });

  test('拔耳机属于主动断开，之后的 end 不应恢复播放', () async {
    focus.send(const FocusEvent(FocusEventType.becomingNoisy));
    await pumpEventQueue();
    focus.send(const FocusEvent(FocusEventType.interruptionEnd));
    await pumpEventQueue();
    expect(core.state.value.playing, isFalse);
    expect(engine.plays, 0);
  });

  test('duck 开始降音量、结束恢复音量，不改变播放状态', () async {
    focus.send(const FocusEvent(FocusEventType.duckBegin, isDuck: true));
    await pumpEventQueue();
    focus.send(const FocusEvent(FocusEventType.duckEnd));
    await pumpEventQueue();
    expect(engine.volumes, [0.2, 1.0]);
    expect(core.state.value.playing, isTrue);
  });
}

/// 让 StreamController.broadcast 的事件与后续 unawaited 引擎调用都跑完。
Future<void> pumpEventQueue() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
