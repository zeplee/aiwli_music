import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/core/models/music.dart';
import 'package:aiwli_music/features/discover/online_playlist_page.dart';
import 'package:aiwli_music/player/audio_engine.dart';
import 'package:aiwli_music/player/providers.dart';
import 'package:aiwli_music/sources/builtin/catalog_sdk.dart';

/// 在线歌单详情页的结构测试。
///
/// 重点验证两个真实约束：
///   1. 不支持的平台要给明确提示，不能转圈后一片空白
///   2. 有曲目时要能整单播放（按钮存在）

Widget _wrap({required String source}) => ProviderScope(
      overrides: [engineProvider.overrideWithValue(StubEngine())],
      child: MaterialApp(
        home: OnlinePlaylistPage(
          source: source,
          playlistId: '3778678',
          title: '测试歌单',
        ),
      ),
    );

void main() {
  tearDown(() => CatalogSdk.overridePlaylistFetcher = null);

  testWidgets('酷我不支持展开时给明确提示而非空白', (tester) async {
    // 酷我走不到网络（playlistSongs 内部直接 return const []），
    // 所以这里不需要注入，正好验证"明确拒绝"这条路径。
    await tester.pumpWidget(_wrap(source: 'kw'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('这个平台暂不支持展开歌单'), findsOneWidget);
    expect(find.textContaining('只有网易云'), findsOneWidget);
  });

  testWidgets('标题显示且可返回', (tester) async {
    await tester.pumpWidget(_wrap(source: 'kw'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('测试歌单'), findsOneWidget);
    expect(find.byTooltip('返回'), findsOneWidget);
  });

  testWidgets('有曲目时展示播放全部与曲目列表', (tester) async {
    CatalogSdk.overridePlaylistFetcher =
        ({required String source, required String playlistId, int limit = 100}) async =>
            const [
              MusicInfo(
                sourceId: 'wy',
                musicId: '1',
                title: '测试曲目一',
                artist: '测试歌手',
                duration: Duration(seconds: 200),
              ),
            ];

    await tester.pumpWidget(_wrap(source: 'wy'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('播放全部'), findsOneWidget);
    expect(find.text('测试曲目一'), findsOneWidget);
    expect(find.text('1 首'), findsOneWidget);
  });

  testWidgets('空曲目时给重试而不是死界面', (tester) async {
    CatalogSdk.overridePlaylistFetcher =
        ({required String source, required String playlistId, int limit = 100}) async =>
            const [];

    await tester.pumpWidget(_wrap(source: 'wy'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('这个歌单暂时没有曲目'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}