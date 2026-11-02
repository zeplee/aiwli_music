import 'dart:async';

import 'package:audio_session/audio_session.dart';

enum FocusEventType { interruptionBegin, interruptionEnd, duckBegin, duckEnd, becomingNoisy }

class FocusEvent {
  const FocusEvent(this.type, {this.isDuck = false});
  final FocusEventType type;
  final bool isDuck;
}

abstract interface class AudioFocusPolicy {
  Future<bool> activate(); // 返回是否获得焦点
  Future<void> deactivate();
  Stream<FocusEvent> get events;
}

/// 移动端 + macOS：包装 audio_session（ADR-009）。
class MobileAudioFocus implements AudioFocusPolicy {
  Future<AudioSession> _session() => AudioSession.instance;

  @override
  Future<bool> activate() async {
    final s = await _session();
    await s.configure(const AudioSessionConfiguration.music());
    return s.setActive(true);
  }

  @override
  Future<void> deactivate() async {
    await (await _session()).setActive(false);
  }

  @override
  Stream<FocusEvent> get events {
    late StreamController<FocusEvent> ctrl;
    StreamSubscription<FocusEvent>? subInt;
    StreamSubscription<void>? subNoisy;
    ctrl = StreamController<FocusEvent>.broadcast(onListen: () async {
      final s = await _session();
      subInt = s.interruptionEventStream.map((e) => switch (e.type) {
            AudioInterruptionType.pause =>
              const FocusEvent(FocusEventType.interruptionBegin),
            AudioInterruptionType.duck =>
              const FocusEvent(FocusEventType.duckBegin, isDuck: true),
            AudioInterruptionType.unknown =>
              const FocusEvent(FocusEventType.interruptionBegin),
          }).listen(ctrl.add);
      subNoisy = s.becomingNoisyEventStream
          .map((_) => const FocusEvent(FocusEventType.becomingNoisy))
          .listen(ctrl.add);
    }, onCancel: () async {
      await subInt?.cancel();
      await subNoisy?.cancel();
    });
    return ctrl.stream;
  }
}

/// Windows/Linux：桌面无音频焦点概念（ADR-009），全空操作。
class DesktopNoopFocus implements AudioFocusPolicy {
  @override
  Future<bool> activate() async => true;
  @override
  Future<void> deactivate() async {}
  @override
  Stream<FocusEvent> get events => const Stream.empty();
}
