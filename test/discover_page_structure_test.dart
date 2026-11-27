import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/features/discover/daily_recommend.dart';
import 'package:aiwli_music/features/discover/discover_page.dart';
import 'package:aiwli_music/features/discover/featured_playlists.dart';
import 'package:aiwli_music/player/audio_engine.dart';
import 'package:aiwli_music/player/providers.dart';

/// 发现页结构与玻璃接入的结构性断言。
///
/// 这里不测像素，只测「该有的版块确实存在」和「玻璃组件确实生效」——
/// 视觉回归靠真机截图，结构回归靠这组测试。

Widget _wrap() => ProviderScope(
      overrides: [engineProvider.overrideWithValue(StubEngine())],
      child: const MaterialApp(home: DiscoverPage()),
    );

void main() {
  setUp(() {
    // 两个数据源都会发真实网络请求；测试环境不能有挂起定时器。
    DailyRecommend.overrideFetcher = () async => const [];
    FeaturedPlaylists.overrideFetcher = (_) async => const [];
  });

  tearDown(() {
    DailyRecommend.overrideFetcher = null;
    FeaturedPlaylists.overrideFetcher = null;
  });

  testWidgets('发现页包含四个核心版块', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump(const Duration(milliseconds: 300));

    // 顶栏
    expect(find.text('发现'), findsOneWidget);
    // 搜索入口
    expect(find.byKey(const ValueKey('discover_search_bar')), findsOneWidget);
    // 每日推荐
    expect(find.text('每日推荐'), findsOneWidget);
    // 排行榜
    expect(find.text('排行榜'), findsOneWidget);
    // 精选歌单（本次新增，此前完全没有）
    expect(find.text('精选歌单'), findsOneWidget);
  });

  testWidgets('每日推荐与精选歌单都做了区块标题', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump(const Duration(milliseconds: 300));

    // 有副标题的区块：排行榜/精选歌单
    expect(find.text('各平台实时热榜'), findsOneWidget);
    expect(find.text('按平台分类浏览'), findsOneWidget);
  });

  testWidgets('精选歌单列 5 家可用平台', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump(const Duration(milliseconds: 300));

    // PlaylistCatalog 为 5 家都提供了无需签名的公开浏览接口，
    // 不再受关键词搜索能力限制。
    final supported = FeaturedPlaylists.supportedSources;
    expect(supported, equals(['wy', 'kw', 'tx', 'kg', 'mg']));
  });

  testWidgets('无脚本时给出说明而不是空白', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump(const Duration(milliseconds: 300));

    // 默认没有导入任何脚本，必须提示"能浏览但不能播"，
    // 而不是让用户点下去才看到「资源失效」。
    expect(find.textContaining('内置接口'), findsOneWidget);
    expect(find.text('去导入'), findsOneWidget);
  });

  testWidgets('玻璃组件确实参与渲染（非纯 Material 外观）', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump(const Duration(milliseconds: 300));

    // GlassContainer 是液态玻璃的核心载体；搜索栏与每日推荐都用它。
    // 用 runtimeType 名字匹配，避免直接 import 私有实现。
    final glassCount = tester
        .widgetList(find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == 'GlassContainer'))
        .length;
    expect(glassCount, greaterThanOrEqualTo(2),
        reason: '搜索栏 + 每日推荐卡片至少两处玻璃容器');
  });
}