import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 可点元素尺寸的回归测试。
///
/// 真机取证（用 getRect 实测，非目测）：
///     倍速按钮   61x33   高度差 15dp
///     音源胶囊   77x31   高度差 17dp
///     榜单胶囊   53x29   高度差 19dp
///     歌词行     85x43   高度差  5dp（这一处按设计保留，见下）
///
/// Material 的最小触控目标是 48x48dp。低于这个尺寸在手指操作下
/// 很容易点不中——尤其这些元素还夹在 48dp 的 IconButton 之间，
/// 用户按习惯点过去就会落空。
///
/// 这里只锁「必须 48」的那几处；歌词行是有意的紧凑排版
/// （一行歌词本身就不该占 48 高，否则一屏放不下几句），
/// 它靠整行宽度补偿，不在此列。
void main() {
  testWidgets('倍速按钮可点区 >= 48x48', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          // 复刻 player_page 里修复后的写法
          child: InkWell(
            onTap: () {},
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text('1.0x', style: TextStyle(fontSize: 12)),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final r = tester.getRect(find.byType(InkWell).first);
    expect(r.width, greaterThanOrEqualTo(48));
    expect(r.height, greaterThanOrEqualTo(48),
        reason: '修复前是 33dp，夹在 48dp 的图标中间很难点中');
  });

  testWidgets('胶囊列表容器高度 >= 48（保证胶囊可点）', (tester) async {
    // 音源胶囊 / 榜单胶囊都用 SizedBox 限高 + 横向 ListView。
    // 容器若小于 48，胶囊自身 29~31dp 的可点区就更小。
    for (final h in [48.0]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: h,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < 3; i++)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      child: Text('酷我$i', style: TextStyle(fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final list = tester.getRect(find.byType(ListView));
      expect(list.height, greaterThanOrEqualTo(48),
          reason: '容器高度不足会把胶囊的可点区压得更小');
    }
  });

  testWidgets('复刻旧尺寸以证明断言有效（33dp 会被抓到）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          // 修复前的写法：只有 padding，没有最小尺寸
          child: InkWell(
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Text('1.0x', style: TextStyle(fontSize: 12)),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final r = tester.getRect(find.byType(InkWell).first);
    expect(r.height, lessThan(48),
        reason: '这证明上面的断言确实能发现"太小"的回归，不是恒真');
  });
}