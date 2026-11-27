import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiwli_music/core/ui/spinning_cover.dart';

void main() {
  Future<RotationTransition> findRotation(WidgetTester tester) async {
    return tester.widget<RotationTransition>(find.byType(RotationTransition));
  }

  testWidgets('播放时旋转 controller 在跑，暂停时停止且不回零', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(
        child: SpinningCover(size: 200, playing: true, round: true),
      ),
    ));
    await tester.pump();

    final spinning = await findRotation(tester);
    final controller = spinning.turns as AnimationController;
    expect(controller.isAnimating, isTrue, reason: '播放态应旋转');

    await tester.pump(const Duration(milliseconds: 300));
    final before = controller.value;
    expect(before, greaterThan(0), reason: '角度应随时间推进');

    await tester.pumpWidget(const MaterialApp(
      home: Center(
        child: SpinningCover(size: 200, playing: false, round: true),
      ),
    ));
    await tester.pump();
    expect(controller.isAnimating, isFalse, reason: '暂停应停止');
    expect(controller.value, closeTo(before, 0.05), reason: '暂停应保留角度');
  });

  testWidgets('方形模式冻结角度但 controller 不销毁', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(
        child: SpinningCover(size: 200, playing: true, round: false),
      ),
    ));
    await tester.pump();

    final rt = await findRotation(tester);
    expect(rt.turns, isA<AlwaysStoppedAnimation<double>>(),
        reason: '方形时角度冻结');
    expect((rt.turns as AlwaysStoppedAnimation<double>).value, 0.0);
  });

  testWidgets('无封面时渲染唱片占位（CustomPaint）而非空白', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(
        child: SpinningCover(size: 160, playing: false, round: true),
      ),
    ));
    await tester.pump();
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
