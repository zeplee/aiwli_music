import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/player/models.dart';

/// 播放模式三态（顺序 / 单曲 / 随机）的映射与循环切换。
///
/// 背景：原来「循环」和「随机」是两个独立按钮，分居左右下角。
/// 用户反馈应合并成一个按钮——它们是互斥的用户意图，不该各占一角。
///
/// 这里锁死三件事：
///   1. 三态 → (repeat, shuffle) 的映射正确
///   2. 点击循环顺序固定：顺序 → 单曲 → 随机 → 顺序
///   3. 从既有状态反推时，shuffle 优先（它一旦开就压过 repeat）
void main() {
  test('三态映射到状态机', () {
    // 顺序：播完停（repeat=off）
    expect(PlayMode.sequential.repeatMode, RepeatMode.off);
    expect(PlayMode.sequential.shuffleOn, isFalse);

    // 单曲：重播本曲
    expect(PlayMode.repeatOne.repeatMode, RepeatMode.one);
    expect(PlayMode.repeatOne.shuffleOn, isFalse);

    // 随机：靠 shuffle 分支随机跳，同时 repeat=all 让手动「下一首」
    // 也能在末尾回绕
    expect(PlayMode.shuffle.repeatMode, RepeatMode.all);
    expect(PlayMode.shuffle.shuffleOn, isTrue);
  });

  test('点击循环：顺序 → 单曲 → 随机 → 顺序', () {
    var m = PlayMode.sequential;
    expect(m.next, PlayMode.repeatOne);
    m = m.next;
    expect(m.next, PlayMode.shuffle);
    m = m.next;
    expect(m.next, PlayMode.sequential, reason: '必须回到起点，不能断链');
  });

  test('三次点击回到原点（幂等循环）', () {
    final start = PlayMode.repeatOne;
    final after3 = start.next.next.next;
    expect(after3, start);
  });

  test('从状态反推：shuffle 优先于 repeat', () {
    // 随机开启时，即使 repeat=one 也应显示为随机
    expect(
      PlayModeX.from(repeat: RepeatMode.one, shuffle: true),
      PlayMode.shuffle,
      reason: 'shuffle 一旦开启就压过 repeat，否则图标与实际行为不符',
    );
  });

  test('从状态反推：各组合都能落到确定的三态', () {
    final cases = <(RepeatMode, bool), PlayMode>{
      (RepeatMode.off, false): PlayMode.sequential,
      (RepeatMode.all, false): PlayMode.sequential,
      (RepeatMode.one, false): PlayMode.repeatOne,
      (RepeatMode.one, true): PlayMode.shuffle,
      (RepeatMode.off, true): PlayMode.shuffle,
      (RepeatMode.all, true): PlayMode.shuffle,
    };
    for (final e in cases.entries) {
      expect(PlayModeX.from(repeat: e.key.$1, shuffle: e.key.$2), e.value,
          reason: 'repeat=${e.key.$1} shuffle=${e.key.$2}');
    }
  });

  test('每个模式都有独立的图标语义（不能有两个相同）', () {
    // 图标在 UI 层定义，这里只保证枚举三态互不相同
    expect(PlayMode.values.toSet().length, 3);
  });
}
