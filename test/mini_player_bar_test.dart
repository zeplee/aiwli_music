import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/features/shell/mini_player_bar.dart';
import 'package:aiwli_music/player/audio_engine.dart';
import 'package:aiwli_music/player/models.dart';
import 'package:aiwli_music/player/player_core.dart';
import 'package:aiwli_music/app_providers.dart';
import 'package:aiwli_music/player/providers.dart';

/// 全局播放条：三个 Tab 共用的唯一实现。
///
/// 用户指出之前「每个页面都实现了一个，样子都不一样」，
/// 合并后必须验证：
///   1. 组件能渲染出标题/歌手/进度
///   2. 无歌曲时隐藏（不占位）
/// 高度固定 56（真机曾因 IconButton 48 + padding 溢出 4px）。
void main() {
  Widget wrap(PlayerCore core) => ProviderScope(
        overrides: [
          engineProvider.overrideWithValue(StubEngine()),
          playerCoreProvider.overrideWithValue(core),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Column(children: [MiniPlayerBar()])),
        ),
      );

  testWidgets('无歌曲时不渲染任何内容（不占位）', (tester) async {
    final core = PlayerCore(engine: StubEngine());
    await tester.pumpWidget(wrap(core));
    await tester.pump();

    // 空状态返回 SizedBox.shrink，界面上不该有播放/暂停按钮
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.byIcon(Icons.pause), findsNothing);
  });

  testWidgets('有歌曲时显示标题、歌手与操作按钮', (tester) async {
    final engine = StubEngine();
    final core = PlayerCore(engine: engine);
    await tester.pumpWidget(wrap(core));

    // 直接改状态模拟"正在播放"
    core.state.value = const PlayerUiState(
      title: '测试歌曲',
      artist: '测试歌手',
      playing: true,
      position: Duration(seconds: 30),
      duration: Duration(minutes: 3),
    );
    await tester.pump();

    expect(find.text('测试歌曲'), findsOneWidget);
    // 歌手与进度在同一行文本里
    expect(
        find.textContaining('测试歌手'), findsOneWidget);
    expect(find.textContaining('00:30'), findsOneWidget);
    // 播放中应显示暂停按钮
    expect(find.byIcon(Icons.pause), findsOneWidget);
    // 下一首按钮
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
  });

  testWidgets('高度不超过 64（防止底部溢出）', (tester) async {
    final engine = StubEngine();
    final core = PlayerCore(engine: engine);
    await tester.pumpWidget(wrap(core));
    core.state.value = const PlayerUiState(
      title: 'T',
      artist: 'A',
      playing: false,
      duration: Duration(minutes: 3),
    );
    await tester.pump();

    final size = tester.getSize(find.byType(MiniPlayerBar));
    // 2(进度线) + 56(行) = 58，留一点余量
    expect(size.height, lessThanOrEqualTo(64),
        reason: '播放条过高会挤占内容或被 Scaffold 裁切');
  });
}