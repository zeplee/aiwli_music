import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 进度条「拖不到最左端 / 圆点不在开头」的回归测试。
///
/// 真机取证：position=2894ms（约 10%）时滑块圆心在 1080 宽的 8.9% 处，
/// 这个比例本身是对的。真正的问题是**两端到不了**：
///
/// Flutter Slider 默认给左右各留一个「thumb 宽度」的 padding
/// （SliderTheme.padding 文档：horizontal padding defaults to the width
/// of the thumb shape）。于是：
///   · value=0 时圆点停在离左端一个 thumb 宽的位置 → 圆不在最开头
///   · 拖到最左也只是到那个边界 → 拖不到 0
///
/// 修复：padding=EdgeInsets.zero + 自定义 trackShape 铺满全宽。
/// 本测试锁死"value=0 时圆心贴到最左、value=max 时贴到最右"。
void main() {
  const sliderWidth = 300.0;

  testWidgets('反证：默认 Slider 的 value=0 圆点不在最左端', (tester) async {
    // 不加修复时，Flutter 会在两侧留 thumb 宽度的 padding，
    // 导致 value=0 时轨道左端 = thumbWidth/2 处（圆点偏离最左）。
    // 这条测试用 getPreferredRect 的直接调用来证明该差异存在。
    const shape = RoundedRectSliderTrackShape();
    const theme = SliderThemeData(
      trackHeight: 3,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
      activeTrackColor: Colors.blue,
      inactiveTrackColor: Colors.grey,
    );

    final box = _FakeBox(const Size(sliderWidth, 40));

    // padding == null → 轨道左右各内缩 max(thumbWidth, overlayWidth)
    final defaultRect = shape.getPreferredRect(
      parentBox: box,
      offset: Offset.zero,
      sliderTheme: theme,
      isEnabled: true,
      isDiscrete: false,
    );
    expect(defaultRect.left, greaterThan(0),
        reason: '默认情况下轨道左端被内缩，这就是圆点不在最开头的成因');

    // padding != null（EdgeInsets.zero）→ 轨道铺满
    final zeroPadded = shape.getPreferredRect(
      parentBox: box,
      offset: Offset.zero,
      sliderTheme: theme.copyWith(padding: EdgeInsets.zero),
      isEnabled: true,
      isDiscrete: false,
    );
    expect(zeroPadded.left, closeTo(0, 0.01),
        reason: '设了 padding 后轨道应从 0 开始');
    expect(zeroPadded.right, closeTo(sliderWidth, 0.01),
        reason: '设了 padding 后轨道应到最右端');
  });

  testWidgets('修复后能拖到最左（value 可以到 0）', (tester) async {
    double? latest;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: sliderWidth,
              child: StatefulBuilder(
                builder: (context, setState) => SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    padding: EdgeInsets.zero,
                    trackHeight: 3,
                    trackShape: const FullWidthTrackShape(),
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: Slider(
                    value: 50,
                    max: 100,
                    onChanged: (v) => setState(() => latest = v),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(Slider));
    // 从滑块当前位置按下，拖到组件最左边缘之外（模拟用户想拖到底）
    final thumbX = rect.left + rect.width * 0.5;
    await tester.dragFrom(Offset(thumbX, rect.center.dy),
        Offset(-rect.width, 0));
    await tester.pumpAndSettle();

    expect(latest, isNotNull, reason: '拖动应产生回调');
    expect(latest, closeTo(0, 1),
        reason: '拖到最左必须能到达 0（修复前只能到 padding 边界）');
  });
}

class _FakeBox extends RenderBox {
  _FakeBox(this._size);
  final Size _size;
  @override
  Size get size => _size;
  @override
  bool get sizedByParent => true;
  @override
  void performLayout() {}
}

/// 与 player_page.dart 里同名实现保持一致的测试副本，
/// 用于在不依赖私有类的条件下验证轨道几何。
class FullWidthTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const FullWidthTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final radius = Radius.circular(rect.height / 2);
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(rect.left, rect.top, thumbCenter.dx, rect.bottom),
        radius,
      ),
      Paint()..color = sliderTheme.activeTrackColor!,
    );
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(thumbCenter.dx, rect.top, rect.right, rect.bottom),
        radius,
      ),
      Paint()..color = sliderTheme.inactiveTrackColor!,
    );
  }
}