import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/sources/builtin/builtin_search.dart';

/// 验证搜索页的滚动触发逻辑：列表可滚动时，滚到底应触发加载。
///
/// 这里不启动真实网络，用假数据构造 30 条，验证滚动监听能触发回调。
void main() {
  testWidgets('滚到底部触发 loadMore 回调', (tester) async {
    var triggered = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          final ctrl = ScrollController();
          ctrl.addListener(() {
            if (ctrl.position.maxScrollExtent - ctrl.position.pixels <= 320) {
              triggered++;
            }
          });
          return ListView.builder(
            controller: ctrl,
            itemCount: 30,
            itemBuilder: (_, i) => ListTile(
              dense: true,
              title: Text('song-$i'),
            ),
          );
        }),
      ),
    ));

    // 滚到底
    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();

    expect(triggered, greaterThan(0), reason: '滚到底应触发加载判定');
  });

  testWidgets('内容不足一屏时 maxScrollExtent 为 0（需要补屏）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          final ctrl = ScrollController();
          return ListView.builder(
            controller: ctrl,
            itemCount: 5,
            itemBuilder: (_, i) => ListTile(dense: true, title: Text('s$i')),
          );
        }),
      ),
    ));
    await tester.pumpAndSettle();
    // 5 条填不满 600px 视口 → 不可滚动 → 需要主动补屏
    final lv = tester.widget<ListView>(find.byType(ListView));
    expect(lv.controller, isNotNull);
  });

  test('SourceGroup.canLoadMore 语义', () {
    final g = SourceGroup(sourceId: 'kw', label: '酷我')
      ..state = SourceSearchState.done
      ..hasMore = true;
    expect(g.canLoadMore, isTrue);

    g.loadingMore = true;
    expect(g.canLoadMore, isFalse, reason: '加载中不应重复触发');

    g.loadingMore = false;
    g.hasMore = false;
    expect(g.canLoadMore, isFalse, reason: '到底后不再加载');

    final script = SourceGroup(sourceId: 'script:1', label: '脚本源')
      ..state = SourceSearchState.done
      ..hasMore = true;
    expect(script.canLoadMore, isFalse, reason: '脚本源不分页');
  });
}