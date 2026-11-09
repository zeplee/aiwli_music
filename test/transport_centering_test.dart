import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 底部走带区居中不变量。
///
/// 真机反馈：加了 K 歌按钮后，播放键明显偏左。
/// 根因是左右两侧按钮数量不等（左 2 个、右 1 个），而当时用的是
/// `Spacer`——它只把**剩余**空间均分，不关心两侧已有内容多宽：
///
///     [队列][K歌] Spacer [走带区] Spacer [模式]
///                ↑ 剩余空间被均分，但左侧本身更宽
///
/// 结果是走带区被推离屏幕中心。正确做法是两侧各用一个 Expanded
/// 占等宽空间，走带区才会严格居中。
void main() {
  /// 量出走带区中心相对屏幕中心的偏移。
  Future<double> centerOffset(
    WidgetTester tester, {
    required bool useExpandedFix,
  }) async {
    const screenW = 400.0;
    Widget left() => Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(width: 48, height: 48), // 队列
            SizedBox(width: 48, height: 48), // K 歌
          ],
        );
    Widget middle() => const SizedBox(key: Key('transport'), width: 160, height: 56);
    Widget right() => const SizedBox(width: 48, height: 48); // 模式

    final row = useExpandedFix
        // 修复后：两侧 Expanded 等宽
        ? Row(children: [
            Expanded(
                child: Align(alignment: Alignment.centerLeft, child: left())),
            middle(),
            Expanded(
                child: Align(alignment: Alignment.centerRight, child: right())),
          ])
        // 修复前：Spacer 均分剩余空间
        : Row(children: [
            left(),
            const Spacer(),
            middle(),
            const Spacer(),
            right(),
          ]);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(width: screenW, child: Center(child: row)),
      ),
    ));
    await tester.pumpAndSettle();

    final t = tester.getRect(find.byKey(const Key('transport')));
    return t.center.dx - screenW / 2;
  }

  testWidgets('修复后：走带区严格居中（偏移接近 0）', (tester) async {
    final offset = await centerOffset(tester, useExpandedFix: true);
    expect(offset.abs(), lessThan(1.0),
        reason: '播放键必须落在屏幕水平中心，偏移 $offset');
  });

  testWidgets('反证：用 Spacer 时确实偏移（证明这个约束有效）', (tester) async {
    final offset = await centerOffset(tester, useExpandedFix: false);
    // 实测：左侧 96dp、右侧 48dp 时偏移 +24dp。
    // 方向是**偏右**——左侧内容更宽会把走带区往右挤，
    // 这点我一开始判断反了，靠实测纠正。
    expect(offset.abs(), greaterThan(10),
        reason: 'Spacer 方案下走带区必须明显偏离中心，否则这条测试没意义');
    expect(offset, closeTo(24, 2),
        reason: '偏移量应约为左右内容宽度差的一半：(96-48)/2');
  });
}
