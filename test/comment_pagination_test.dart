import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:aiwli_music/core/services/comment_paging.dart';

class _Item {
  const _Item(this.user, this.content, this.time);
  final String user;
  final String content;
  final String time;
}

class _Query {
  const _Query(this.key);
  final String key;
}

typedef _Page = CommentPageResult<_Item>;

void main() {
  late CommentPaging<_Query, _Item> paging;

  CommentPaging<_Query, _Item> build(
    Future<_Page> Function(_Query q, int offset, int limit) fetch,
  ) {
    return CommentPaging<_Query, _Item>(
      fetchPage: fetch,
      keyOf: (q) => q.key,
      onChanged: () {},
      pageSize: 2,
      dedupeKey: (i) => '${i.user}|${i.content}|${i.time}',
    );
  }

  _Page page(
    List<_Item> items, {
    bool hasMore = false,
    int total = 0,
    int? nextOffset,
  }) =>
      _Page(
        items: items,
        hasMore: hasMore,
        total: total,
        nextOffset: nextOffset ?? items.length,
      );

  test('首页请求 offset=0，loadMore 用累加后的 offset', () async {
    final offsets = <int>[];
    paging = build((q, offset, limit) async {
      offsets.add(offset);
      if (offset == 0) {
        return page(
          const [_Item('甲', '第1条', '1'), _Item('乙', '第2条', '2')],
          hasMore: true,
          total: 4,
          nextOffset: 2,
        );
      }
      return page(
        const [_Item('丙', '第3条', '3'), _Item('丁', '第4条', '4')],
        total: 4,
        nextOffset: 4,
      );
    });

    await paging.load(const _Query('A'));
    expect(offsets, [0]);
    expect(paging.items.length, 2);
    expect(paging.hasMore, isTrue);

    await paging.loadMore();
    expect(offsets, [0, 2]);
    expect(paging.items.length, 4);
    expect(paging.hasMore, isFalse);
    expect(paging.offset, 4);
  });

  test('合并结果按 dedupeKey 去重，翻页不重复显示同一条', () async {
    paging = build((q, offset, limit) async {
      if (offset == 0) {
        return page(const [_Item('甲', '重复', '1')],
            hasMore: true, total: 2, nextOffset: 1);
      }
      return page(const [_Item('甲', '重复', '1'), _Item('乙', '新', '2')],
          total: 2, nextOffset: 2);
    });

    await paging.load(const _Query('A'));
    await paging.loadMore();
    expect(paging.items.length, 2, reason: '重复评论只能出现一次');
    expect(paging.items.last.content, '新');
  });

  test('切歌竞态：旧歌慢响应不能覆盖新歌的评论', () async {
    final slow = Completer<_Page>();
    final calls = <int>[];
    paging = build((q, offset, limit) async {
      calls.add(offset);
      if (q.key == 'A') return slow.future;
      return page(const [_Item('新', 'B 的评论', '1')]);
    });

    final a = paging.load(const _Query('A'));
    // 立刻切歌：状态机同步清空 items 并递增 requestId。
    await paging.load(const _Query('B'));
    expect(paging.items.single.content, 'B 的评论');

    slow.complete(page(const [_Item('旧', 'A 的迟到评论', '1')]));
    await a;
    expect(paging.items.single.content, 'B 的评论',
        reason: 'A 的迟到响应必须被 requestId 丢弃');
  });

  test('切歌时旧列表先清空，不会闪现上一首的评论', () async {
    final gate = Completer<_Page>();
    paging = build((q, offset, limit) async =>
        q.key == 'A' ? page(const [_Item('甲', 'A', '1')]) : gate.future);

    await paging.load(const _Query('A'));
    expect(paging.items, isNotEmpty);

    final b = paging.load(const _Query('B'));
    expect(paging.items, isEmpty, reason: '切歌瞬间必须立刻清空');
    gate.complete(page(const [_Item('乙', 'B', '2')]));
    await b;
    expect(paging.items.single.content, 'B');
  });

  test('refresh 绕过缓存并重新拉首页', () async {
    var fetches = 0;
    paging = build((q, offset, limit) async {
      fetches++;
      return page(const [_Item('甲', '评论', '1')], total: 1);
    });

    await paging.load(const _Query('A'));
    expect(fetches, 1);
    await paging.load(const _Query('A'));
    expect(fetches, 1, reason: '同曲命中缓存不重复请求');
    await paging.refresh();
    expect(fetches, 2, reason: 'refresh 必须绕过缓存');
  });

  test('首页失败按 CommentFetchException 分类，loadMore 失败保留已加载项', () async {
    paging = build((q, offset, limit) async {
      if (offset == 0) {
        throw const CommentFetchException(
            CommentErrorKind.network, '网络不可用');
      }
      throw const CommentFetchException(
          CommentErrorKind.parse, '解析失败');
    });

    await paging.load(const _Query('A'));
    expect(paging.errorKind, CommentErrorKind.network);
    expect(paging.items, isEmpty);

    // 手工构造一个「已有数据 + hasMore」的场景验证底部错误不吞列表。
    paging = build((q, offset, limit) async {
      if (offset == 0) {
        return page(const [_Item('甲', '已有', '1')],
            hasMore: true, total: 2, nextOffset: 1);
      }
      throw const CommentFetchException(
          CommentErrorKind.parse, '第二页解析失败');
    });
    await paging.load(const _Query('B'));
    await paging.loadMore();
    expect(paging.items.length, 1, reason: '翻页失败不能清掉已有评论');
    expect(paging.loadMoreErrorKind, CommentErrorKind.parse);
  });

  test('错误文案分类可用，且 unsupported 与 network 不混淆', () {
    expect(
      const CommentFetchException(CommentErrorKind.unsupported, '不支持')
          .errorKind,
      CommentErrorKind.unsupported,
    );
    expect(
      const CommentFetchException(CommentErrorKind.network, '断网').toString(),
      '断网',
    );
  });
}
