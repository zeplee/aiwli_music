import 'package:flutter_test/flutter_test.dart';
import 'package:aiwli_music/core/services/sleep_timer.dart';

void main() {
  test('dispose 后倒计时不再触发 onExpire', () async {
    var expired = 0;
    var notified = 0;
    final timer = SleepTimerService(onExpire: () => expired++);
    timer.addListener(() => notified++);

    timer.startCountdown(const Duration(milliseconds: 1100));
    expect(timer.active, isTrue);
    final before = notified;

    timer.dispose();
    // 跨越到期时间：Timer 若没被取消，这里会调用已失效 core 的 pause。
    await Future<void>.delayed(const Duration(milliseconds: 1300));

    expect(expired, 0, reason: 'dispose 后不能自己停播');
    expect(notified, before, reason: 'dispose 后不应再通知监听者');
    expect(timer.active, isFalse);
    expect(timer.remaining, Duration.zero);
  });

  test('cancel 同时清除「播完当前首」标志', () {
    final flags = <bool>[];
    final timer = SleepTimerService(
      onExpire: () {},
      onEndOfTrackChanged: flags.add,
    );
    timer.startEndOfTrack();
    expect(timer.endOfTrackActive, isTrue);
    timer.cancel();
    expect(timer.endOfTrackActive, isFalse);
    expect(flags, [true, false]);
    timer.dispose();
  });
}
