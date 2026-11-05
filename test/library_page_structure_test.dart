import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/features/library/library_page.dart';
import 'package:aiwli_music/player/audio_engine.dart';
import 'package:aiwli_music/player/providers.dart';

/// 曲库页结构回归测试。
///
/// 真机曾报 `No TabController for TabBar`（加 TabBar 忘了给 controller），
/// 以及「本机歌曲未就绪时整页转圈导致 Tab 都不显示」。
/// 这里锁死：
///   1. 页面能构建（不抛 TabController / Provider / 原生库异常）
///   2. 标题是「曲库」而不是旧的「音乐库」
///   3. 三个 Tab 文案存在（歌单 / 最近 / 本机）
///   4. **本机扫描未完成时 Tab 仍然可见**（不被 loading 吞掉）
void main() {
  testWidgets('曲库页能构建且标题/Tab 正确（扫描未完成也不挡 Tab）', (tester) async {
    await tester.pumpWidget(ProviderScope(
      // 测试环境没有 Mpv 原生库，必须用 StubEngine，否则会抛
      // "Cannot find Mpv.framework/Mpv"
      overrides: [engineProvider.overrideWithValue(StubEngine())],
      child: const MaterialApp(home: LibraryPage()),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);

    expect(find.text('曲库'), findsWidgets);
    expect(find.text('音乐库'), findsNothing);

    // 三个 Tab 必须在（即使本机扫描还没返回/失败）
    expect(find.text('歌单'), findsWidgets);
    expect(find.text('最近'), findsWidgets);
    expect(find.text('本机'), findsWidgets);
  });
}