import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/features/player/player_page.dart';

/// 播放页「顶部白条」的回归测试。
///
/// 真机/桌面取证：播放页顶部有一条白色横条，状态栏、折叠箭头、歌曲
/// 标题都在里面，但**背景色没铺到那里**。
///
/// 根因：`SafeArea` 包在 `Stack` 外层。
///   Scaffold(body: SafeArea(child: Stack([Positioned.fill(背景), 内容])))
/// SafeArea 通过 padding 把子树整体内缩，`Positioned.fill` 只能填满
/// 内缩后的区域 → 状态栏那条**没有任何 widget 绘制** → 露出 Scaffold
/// 默认背景（主题 surface，浅色主题下就是白色）。
///
/// 正确结构：SafeArea 只包「内容」，背景层留在 Stack 里铺满全屏。
///
/// 注意：widget test 默认没有系统状态栏，SafeArea 的 padding 是 0，
/// 复现不出白条。所以这里**显式注入 MediaQuery padding** 模拟刘海。
void main() {
  veilTests();

  const notch = EdgeInsets.only(top: 47, bottom: 34);

  Future<void> pumpHarness(WidgetTester tester,
      {required bool brokenStructure}) async {
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(padding: notch, size: Size(390, 844)),
      child: MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.transparent,
          body: brokenStructure
              // 修复前：SafeArea 包住整个 Stack → 背景被内缩 → 白条
              ? const SafeArea(child: _BackdropAndContent())
              : const _BackdropAndContent(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('正确结构：背景铺到屏幕最上沿（无白条）', (tester) async {
    await pumpHarness(tester, brokenStructure: false);

    final screen = tester.getRect(find.byType(Scaffold));
    final backdrop = tester.getRect(find.byKey(const Key('backdrop')));

    expect(backdrop.top, screen.top,
        reason: '背景必须贴到屏幕最上沿；被 SafeArea 内缩就会露白条');
    expect(backdrop.height, screen.height, reason: '背景要铺满整个高度');
  });

  testWidgets('正确结构：内容仍避让刘海（修复背景不能顶掉安全区）',
      (tester) async {
    await pumpHarness(tester, brokenStructure: false);

    final content = tester.getRect(find.byKey(const Key('content')));
    final screen = tester.getRect(find.byType(Scaffold));

    expect(content.top, screen.top + notch.top,
        reason: '内容顶部应正好让出状态栏高度（$notch）');
  });

  testWidgets('反证：SafeArea 包住背景时确实会产生顶部白条', (tester) async {
    await pumpHarness(tester, brokenStructure: true);

    final screen = tester.getRect(find.byType(Scaffold));
    final backdrop = tester.getRect(find.byKey(const Key('backdrop')));

    // 背景被下推了 notch.top —— 这段没人绘制，就是用户看到的白条
    expect(backdrop.top, screen.top + notch.top,
        reason: '这正是白条的成因：SafeArea 在外层时背景被下推');

    final gap = backdrop.top - screen.top;
    expect(gap, notch.top, reason: '缺口高度 = 状态栏高度');
  });
}

/// 正确结构：背景层在 SafeArea 之外，只有内容避让。
class _BackdropAndContent extends StatelessWidget {
  const _BackdropAndContent();

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          const Positioned.fill(
            child: ColoredBox(
              key: Key('backdrop'),
              color: Color(0xFF3B2F6B),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(key: const Key('content'), height: 40),
            ),
          ),
        ],
      );
}
/// 只测纯函数，不需要 widget 环境。
void veilTests() {
  group('背景遮罩强度（顶部白条的真正成因）', () {
    test('浅色+无封面：遮罩必须很淡，否则糊成白带', () {
      final v = PlayerBackdropVeil.of(
        brightness: Brightness.light,
        hasArt: false,
      );
      // 真机数据：alpha≈0.74 时顶部 RGB 为 (222,220,229) 近中性白
      expect(v.top, lessThanOrEqualTo(0.15),
          reason: '浅色主题白色遮罩一旦超过 ~0.15 就会把背景糊白');
      expect(v.top, lessThan(v.mid), reason: '自上而下应逐渐加深');
      expect(v.mid, lessThan(v.bottom));
    });

    test('浅色+有封面：遮罩要够，保证文字可读', () {
      final v = PlayerBackdropVeil.of(
        brightness: Brightness.light,
        hasArt: true,
      );
      expect(v.top, greaterThanOrEqualTo(0.45),
          reason: '封面图案花哨，需要足够遮罩');
      expect(v.bottom, greaterThan(v.top));
    });

    test('深色主题比浅色容忍更高的遮罩', () {
      final dark = PlayerBackdropVeil.of(
        brightness: Brightness.dark,
        hasArt: false,
      );
      final light = PlayerBackdropVeil.of(
        brightness: Brightness.light,
        hasArt: false,
      );
      // 深色 surface 近黑，同样 alpha 只是压暗，不会变白
      expect(dark.top, greaterThan(light.top),
          reason: '深色主题的遮罩不会产生"白条"观感');
    });

    test('所有情况 alpha 都在合法区间', () {
      for (final b in Brightness.values) {
        for (final art in [true, false]) {
          final v = PlayerBackdropVeil.of(brightness: b, hasArt: art);
          expect(v.top, inInclusiveRange(0, 1));
          expect(v.mid, inInclusiveRange(0, 1));
          expect(v.bottom, inInclusiveRange(0, 1));
        }
      }
    });
  });
}
