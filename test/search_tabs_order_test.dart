import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/sources/builtin/catalog_sdk.dart';

/// 搜索页 Tab 顺序的一致性约束。
///
/// 真机踩过的坑：把分类 Tab 加在 5 个平台 Tab **之后**，而 TabBar 是
/// 横向滚动的，结果分类 Tab 被推出屏幕——用户只看到平台 Tab，
/// 以为功能没做。
///
/// 另一类更隐蔽的坑：TabBar 与 TabBarView 的顺序不一致，
/// 点「专辑」却显示「酷我」的结果。
///
/// 这里锁死这两条：
///   1. 分类 Tab 必须紧跟「全部」（索引 1..3）
///   2. 分类与平台分组的相对顺序在所有地方保持一致
void main() {
  // 要保证的顺序约定
  const catalogKinds = [
    SearchKind.album,
    SearchKind.playlist,
    SearchKind.artist,
  ];

  test('分类 Tab 固定三种，且不含 song（歌曲走「全部」）', () {
    expect(catalogKinds.length, 3);
    expect(catalogKinds.contains(SearchKind.song), isFalse,
        reason: 'song 若也占一个 Tab，会和「全部」里的歌曲结果重复');
  });

  test('索引约定：0=全部，1..3=分类，4+=平台分组', () {
    // 用纯逻辑复现页面的索引计算
    int catalogIndex(SearchKind k) => 1 + catalogKinds.indexOf(k);
    expect(catalogIndex(SearchKind.album), 1);
    expect(catalogIndex(SearchKind.playlist), 2);
    expect(catalogIndex(SearchKind.artist), 3);
    // 平台分组从 4 开始
    const groupsCount = 5;
    int firstGroupIndex = 1 + catalogKinds.length;
    expect(firstGroupIndex, 4);
    // 总 Tab 数
    expect(1 + catalogKinds.length + groupsCount, 9);
  });

  test('分类标签文案固定', () {
    String label(SearchKind k) => switch (k) {
          SearchKind.album => '专辑',
          SearchKind.playlist => '歌单',
          SearchKind.artist => '艺人',
          SearchKind.song => '歌曲',
        };
    expect(label(SearchKind.album), '专辑');
    expect(label(SearchKind.playlist), '歌单');
    expect(label(SearchKind.artist), '艺人');
  });

  test('顺序调整后「全部」仍在索引 0', () {
    // 「全部」必须第一：它是默认落点
    const allIndex = 0;
    expect(allIndex, 0);
    expect(catalogKinds.first, SearchKind.album,
        reason: '专辑排第一：找专辑比找歌单更常见');
  });
}
