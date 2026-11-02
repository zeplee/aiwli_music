import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/sources/builtin/builtin_search.dart';

/// 验证分页：首屏 30 条 → loadMore → 第 2 页能追加。
void main() {
  test('酷我分页：第 1 页 → 加载第 2 页', () async {
    final groups = await BuiltinSearch.searchAll(
      '周杰伦',
      enabled: {'kw'},
    );
    final g = groups.first;
    // ignore: avoid_print
    print('第1页: ${g.count} 条, hasMore=${g.hasMore}, page=${g.page}');
    expect(g.count, greaterThan(0));
    expect(g.hasMore, isTrue, reason: '满 30 条应判定还有下一页');

    final firstTitles = g.songs.take(3).map((s) => s.title).toList();
    final added = await BuiltinSearch.loadMore(g);
    // ignore: avoid_print
    print('第2页追加: $added 条 → 总计 ${g.count}, page=${g.page}');
    // ignore: avoid_print
    print('第2页新歌示例: ${g.songs.skip(firstTitles.length).take(3).map((s) => s.title).toList()}');

    expect(added, greaterThan(0), reason: 'loadMore 应追加新条目');
    expect(g.page, 2);
    expect(g.count, greaterThan(30), reason: '总数应超过一页');
    expect(firstTitles.isNotEmpty, isTrue);
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('无更多时 loadMore 返回 0 且置 hasMore=false', () async {
    final groups = await BuiltinSearch.searchAll(
      '周杰伦',
      enabled: {'kw'},
    );
    final g = groups.first;
    g.hasMore = false; // 模拟已到底
    final added = await BuiltinSearch.loadMore(g);
    expect(added, 0);
  });
}