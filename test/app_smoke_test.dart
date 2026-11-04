import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/app.dart';
import 'package:aiwli_music/features/discover/daily_recommend.dart';
import 'package:aiwli_music/player/audio_engine.dart';
import 'package:aiwli_music/player/providers.dart';

void main() {
  testWidgets('app boots to home', (tester) async {
    // 每日推荐会发起真实网络请求；测试环境无网络且禁止挂起定时器，
    // 注入固定结果让首帧可预测（生产不受影响）。
    DailyRecommend.overrideFetcher = () async => const [];

    await tester.pumpWidget(ProviderScope(
      overrides: [engineProvider.overrideWithValue(StubEngine())],
      child: const AiwliApp(),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    // 三 Tab 壳（发现/曲库/我的）+ 发现页顶栏
    expect(find.text('发现'), findsWidgets);
    expect(find.text('曲库'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    DailyRecommend.overrideFetcher = null;
  });
}