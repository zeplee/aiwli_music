@Tags(['network'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/sources/builtin/builtin_search.dart';

/// 验证分页：首屏 30 条 → loadMore → 第 2 页能追加。
///
/// 真实网络测试（打酷我接口），默认跳过：flutter test --tags network
void main() {
  test('酷我分页：第 1 页 → 加载第 2 页', () async {
    final groups = await BuiltinSearch.searchAll(
      '周杰伦',
      enabled: {'kw'},
    );
    final g = groups.first;

    expect(g.songs.length, 30, reason: '首屏应为 30 条');
    expect(g.hasMore, isTrue, reason: '应还有更多');

    final before = g.songs.length;
    final more = await BuiltinSearch.loadMore(g);
    expect(more, 30, reason: '第 2 页应再取 30 条');
    expect(g.songs.length, before + more);
    // 第 2 页不能与第 1 页重复
    final ids = g.songs.map((e) => e.musicId).toSet();
    expect(ids.length, g.songs.length, reason: '分页不得出现重复条目');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('无更多时 loadMore 返回 0 且置 hasMore=false', () async {
    final groups = await BuiltinSearch.searchAll(
      '周杰伦',
      enabled: {'kw'},
    );
    final g = groups.first;
    // 反复翻页直到到底
    var guard = 0;
    while (g.canLoadMore && guard < 20) {
      await BuiltinSearch.loadMore(g);
      guard++;
    }
    expect(g.hasMore, isFalse);
    expect(await BuiltinSearch.loadMore(g), 0,
        reason: '到底后应返回 0 而不是继续请求');
  }, timeout: const Timeout(Duration(seconds: 90)));
}