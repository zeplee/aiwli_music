@Tags(['network'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/sources/builtin/builtin_search.dart';

void main() {
  test('SourceGroup 状态与计数', () {
    final g = SourceGroup(sourceId: 'kw', label: '酷我')
      ..state = SourceSearchState.done
      ..songs = [
        // 用最小占位验证计数与 hasResults（MusicInfo 需要真实构造）
      ];
    expect(g.hasResults, isFalse);
    expect(g.count, 0);
    expect(g.label, '酷我');
  });

  test('五个平台标签齐全且顺序固定', () {
    expect(BuiltinSearch.labels.keys.toSet(),
        {'kw', 'kg', 'tx', 'wy', 'mg'});
    expect(BuiltinSearch.order, ['kw', 'tx', 'wy', 'kg', 'mg']);
  });

  testWidgets('TabBar + TabBarView 切换（模拟搜索页结构）', (tester) async {
    // 复现搜索页的核心结构：1(全部) + 5 源 = 6 个 Tab
    final labels = ['全部', '酷我', 'QQ音乐', '网易云', '酷狗', '咪咕'];
    await tester.pumpWidget(MaterialApp(
      home: DefaultTabController(
        length: labels.length,
        child: Scaffold(
          appBar: AppBar(
            bottom: TabBar(
              isScrollable: true,
              tabs: [for (final l in labels) Tab(text: l)],
            ),
          ),
          body: TabBarView(
            children: [
              for (final l in labels)
                Center(child: Text('page-$l', key: ValueKey(l))),
            ],
          ),
        ),
      ),
    ));
    expect(find.text('page-全部'), findsOneWidget);

    // 点第 2 个 Tab
    await tester.tap(find.text('酷我'));
    await tester.pumpAndSettle();
    expect(find.text('page-酷我'), findsOneWidget);
  });
}
