/// 评论加载错误的分类：UI 据此区分「网络失败 / 解析失败 / 音源不支持」，
/// 避免把所有失败都当成「暂无评论」。
enum CommentErrorKind { network, parse, unsupported }

/// 评论获取失败时抛出，而不是返回空列表。
class CommentFetchException implements Exception {
  const CommentFetchException(this.errorKind, this.message, [this.cause]);

  final CommentErrorKind errorKind;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// 分页结果的公共形状。[CommentPage] 在 comment_sdk.dart 内继承它，
/// 这样 SDK 的返回值可以直接交给本状态机，无需中间转换。
class CommentPageResult<T> {
  const CommentPageResult({
    required this.items,
    this.hasMore = false,
    this.total = 0,
    this.nextOffset = 0,
  });

  final List<T> items;
  final bool hasMore;
  final int total;

  /// 下一页应使用的 offset。首页会把热评并入 items，但热评不占服务端
  /// 普通评论的游标，所以不能简单用 items.length 推算。
  final int nextOffset;
}

class _Snapshot<T> {
  const _Snapshot(this.items, this.offset, this.hasMore, this.total);
  final List<T> items;
  final int offset;
  final bool hasMore;
  final int total;
}

/// 切歌时用于定位评论的上下文；[key] 只按曲目身份去重，标题变化不触发重拉。
class CommentQuery {
  const CommentQuery({
    required this.sourceId,
    required this.musicId,
    this.title = '',
    this.artist = '',
  });

  final String sourceId;
  final String musicId;
  final String title;
  final String artist;
  String get key => '$sourceId/$musicId';
}

/// 评论分页状态机（纯 Dart，可独立实例化、可注入 fetchPage）。
///
/// 职责：缓存、offset 累加、去重、requestId 竞态守卫、错误分类。
/// 不含 Flutter/Riverpod 依赖；[onChanged] 由 CommentService 接到 notifyListeners。
class CommentPaging<Q, T> {
  CommentPaging({
    required this.fetchPage,
    required this.keyOf,
    required this.onChanged,
    this.pageSize = 30,
    this.dedupeKey,
  });

  final Future<CommentPageResult<T>> Function(Q query, int offset, int limit)
      fetchPage;
  final String Function(Q query) keyOf;
  final void Function() onChanged;
  final int pageSize;
  final String Function(T item)? dedupeKey;

  final Map<String, _Snapshot<T>> _cache = {};

  Q? query;
  String? key;

  /// 每次开始新请求 / 切歌都递增；响应回来时 id 不等即直接丢弃。
  int requestId = 0;

  List<T> items = const [];
  int offset = 0;
  bool hasMore = false;
  int total = 0;
  bool loading = false;
  bool loadingMore = false;
  CommentErrorKind? errorKind;
  CommentErrorKind? loadMoreErrorKind;
  String? error;
  String? loadMoreError;

  bool get canLoadMore => hasMore && !loading && !loadingMore;
  bool hasCache(String k) => _cache.containsKey(k);
  int get cachedCount => _cache.length;

  /// 切歌（或同一首歌首次进入）：立即清空旧评论再请求，避免旧歌评论闪现。
  /// [refresh] 为 true 时绕过缓存强制重拉首页。
  Future<void> load(Q newQuery, {bool refresh = false}) async {
    final k = keyOf(newQuery);
    final reset = k != key || refresh;
    if (reset) {
      // 同步作废在飞的旧请求，旧响应回来时 requestId 已不匹配。
      requestId++;
      key = k;
      _reset();
      onChanged();
    } else if (loading || (items.isNotEmpty && errorKind == null)) {
      return;
    }
    query = newQuery;

    if (!refresh) {
      final cached = _cache[k];
      if (cached != null) {
        _restore(cached);
        loading = false;
        onChanged();
        return;
      }
    }

    final id = ++requestId;
    loading = true;
    errorKind = null;
    error = null;
    loadMoreErrorKind = null;
    loadMoreError = null;
    onChanged();
    try {
      final page = await fetchPage(newQuery, 0, pageSize);
      if (id != requestId || k != key) return;
      items = _dedupe(<T>[], page.items);
      offset = page.nextOffset;
      hasMore = page.hasMore && offset > 0;
      total = page.total;
      loading = false;
      _save(k);
      onChanged();
    } on CommentFetchException catch (e) {
      if (id != requestId || k != key) return;
      loading = false;
      errorKind = e.errorKind;
      error = e.message;
      onChanged();
    } catch (e) {
      if (id != requestId || k != key) return;
      loading = false;
      errorKind = CommentErrorKind.network;
      error = '评论获取失败: $e';
      onChanged();
    }
  }

  /// 滚动接近底部时调用；失败只影响底部状态，保留已加载的评论。
  Future<void> loadMore() async {
    final q = query;
    final k = key;
    if (q == null || k == null || !canLoadMore || errorKind != null) return;
    final baseOffset = offset;
    final id = ++requestId;
    loadingMore = true;
    loadMoreErrorKind = null;
    loadMoreError = null;
    onChanged();
    try {
      final page = await fetchPage(q, baseOffset, pageSize);
      if (id != requestId || k != key) return;
      items = _dedupe(items, page.items);
      final next = page.nextOffset > baseOffset
          ? page.nextOffset
          : baseOffset + page.items.length;
      offset = next;
      hasMore = page.hasMore && next > baseOffset;
      total = page.total;
      loadingMore = false;
      _save(k);
      onChanged();
    } on CommentFetchException catch (e) {
      if (id != requestId || k != key) return;
      loadingMore = false;
      loadMoreErrorKind = e.errorKind;
      loadMoreError = e.message;
      onChanged();
    } catch (e) {
      if (id != requestId || k != key) return;
      loadingMore = false;
      loadMoreErrorKind = CommentErrorKind.network;
      loadMoreError = '评论获取失败: $e';
      onChanged();
    }
  }

  /// 手动重试 / 刷新：清空当前内容，绕过缓存重新拉首页。
  Future<void> refresh() {
    final q = query;
    if (q == null) return Future<void>.value();
    return load(q, refresh: true);
  }

  void _reset() {
    items = const [];
    offset = 0;
    hasMore = false;
    total = 0;
    loading = false;
    loadingMore = false;
    errorKind = null;
    loadMoreErrorKind = null;
    error = null;
    loadMoreError = null;
  }

  void _restore(_Snapshot<T> s) {
    items = s.items;
    offset = s.offset;
    hasMore = s.hasMore;
    total = s.total;
    errorKind = null;
    loadMoreErrorKind = null;
    error = null;
    loadMoreError = null;
  }

  void _save(String k) =>
      _cache[k] = _Snapshot(items, offset, hasMore, total);

  List<T> _dedupe(List<T> base, List<T> incoming) {
    final keyFn = dedupeKey;
    if (keyFn == null) return [...base, ...incoming];
    final seen = <String>{for (final e in base) keyFn(e)};
    final out = [...base];
    for (final e in incoming) {
      if (seen.add(keyFn(e))) out.add(e);
    }
    return out;
  }
}
