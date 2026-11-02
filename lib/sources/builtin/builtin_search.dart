import 'dart:async';

import '../../core/models/music.dart';
import '../../core/services/logger.dart';
import 'kg_sdk.dart';
import 'kw_sdk.dart';
import 'mg_sdk.dart';
import 'tx_sdk.dart';
import 'wy_sdk.dart';

/// 单个内置平台的搜索状态。
enum SourceSearchState { pending, loading, done, failed }

/// 一个源的搜索结果分组。
class SourceGroup {
  SourceGroup({
    required this.sourceId,
    required this.label,
    this.state = SourceSearchState.pending,
    List<MusicInfo>? songs,
    this.error,
    this.page = 1,
    this.hasMore = true,
    this.loadingMore = false,
    this.keyword = '',
  }) : songs = songs ?? <MusicInfo>[];

  final String sourceId;
  final String label; // 展示名（酷我 / QQ音乐 / 网易云 / 酷狗 / 咪咕）
  SourceSearchState state;
  List<MusicInfo> songs;
  String? error;

  /// 已加载到的页码（下一页 = page + 1）。
  int page;

  /// 是否还有下一页（返回空或不足一页即认为到底）。
  bool hasMore;

  /// 正在加载下一页。
  bool loadingMore;

  /// 该分组对应的关键词（加载更多时复用）。
  String keyword;

  bool get hasResults => songs.isNotEmpty;
  int get count => songs.length;

  /// 脚本源一次给全，不参与分页。
  bool get isScript => sourceId.startsWith('script:');

  /// 是否还能继续加载。
  bool get canLoadMore =>
      hasMore && !loadingMore && state == SourceSearchState.done && !isScript;

  SourceGroup copy() => SourceGroup(
        sourceId: sourceId,
        label: label,
        state: state,
        songs: List.of(songs),
        error: error,
        page: page,
        hasMore: hasMore,
        loadingMore: loadingMore,
        keyword: keyword,
      );
}

/// 内置平台聚合搜索。
///
/// 策略（对齐参考实现并做移动端优化）：
///  - 全部平台**并发**请求，谁先返回先展示（渐进式）
///  - **单源失败不影响其他源**（各自记录 error）
///  - 结果**按源分组**（便于跨源对比音质）
///  - 每组独立**分页**：滚到底加载下一页（见 [loadMore]）
class BuiltinSearch {
  BuiltinSearch._();

  /// 平台 → 展示名。
  static const labels = <String, String>{
    'kw': '酷我',
    'kg': '酷狗',
    'tx': 'QQ音乐',
    'wy': '网易云',
    'mg': '咪咕',
  };

  static const order = ['kw', 'tx', 'wy', 'kg', 'mg'];

  /// 每页条数（与各平台接口默认一致）。
  static const pageSize = 30;

  /// 并发搜索，逐源回调（用于渐进式 UI）。
  static Future<List<SourceGroup>> searchAll(
    String keyword, {
    int page = 1,
    int limit = pageSize,
    Set<String>? enabled,
    void Function(List<SourceGroup> groups)? onGroup,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final kw = keyword.trim();
    final groups = <SourceGroup>[
      for (final id in order)
        if (enabled == null || enabled.contains(id))
          SourceGroup(sourceId: id, label: labels[id] ?? id, keyword: kw),
    ];
    if (kw.isEmpty || groups.isEmpty) return groups;

    void emit() => onGroup?.call([for (final g in groups) g.copy()]);

    await Future.wait(groups.map((g) async {
      g.state = SourceSearchState.loading;
      emit();
      try {
        final list =
            await _searchOne(g.sourceId, kw, page, limit).timeout(timeout);
        g.songs = _rank(list, kw);
        g.state = SourceSearchState.done;
        g.hasMore = list.length >= limit;
      } catch (e) {
        g.state = SourceSearchState.failed;
        g.error = _short(e);
        AppLog.w('BuiltinSearch', '${g.label} 搜索失败: ${g.error}');
      }
      emit();
    }));

    return groups;
  }

  /// 加载某个源的下一页，就地追加到 [group]。返回追加条数（0 = 已到底）。
  static Future<int> loadMore(SourceGroup group) async {
    if (!group.canLoadMore) return 0;
    group.loadingMore = true;
    final next = group.page + 1;
    try {
      final list = await _searchOne(group.sourceId, group.keyword, next, pageSize)
          .timeout(const Duration(seconds: 20));
      if (list.isEmpty) {
        group.hasMore = false;
        return 0;
      }
      // 按 musicId 去重后追加（平台偶有跨页重复）
      final existing = {for (final s in group.songs) s.musicId};
      final fresh = [
        for (final s in list)
          if (existing.add(s.musicId)) s,
      ];
      group.songs = [...group.songs, ...fresh];
      group.page = next;
      // 不足一页通常意味着到底
      if (list.length < pageSize) group.hasMore = false;
      return fresh.length;
    } catch (e) {
      AppLog.w('BuiltinSearch', '${group.label} 第 $next 页加载失败: $e');
      group.hasMore = false;
      return 0;
    } finally {
      group.loadingMore = false;
    }
  }

  static Future<List<MusicInfo>> _searchOne(
      String sourceId, String keyword, int page, int limit) {
    switch (sourceId) {
      case 'kw':
        return KwSdk.search(keyword, page: page, limit: limit);
      case 'tx':
        return TxSdk.search(keyword, page: page, limit: limit);
      case 'wy':
        return WySdk.search(keyword, page: page, limit: limit);
      case 'kg':
        return KgSdk.search(keyword, page: page, limit: limit);
      case 'mg':
        return MgSdk.search(keyword, page: page, limit: limit);
      default:
        return Future.value(const []);
    }
  }

  /// 按关键词相似度简单排序（歌名命中 > 歌手命中）。
  static List<MusicInfo> _rank(List<MusicInfo> list, String keyword) {
    final k = keyword.toLowerCase();
    final scored = <MapEntry<int, MusicInfo>>[];
    for (var i = 0; i < list.length; i++) {
      final s = list[i];
      final title = s.title.toLowerCase();
      final artist = s.artist.toLowerCase();
      var score = 0;
      if (title == k) {
        score = 100;
      } else if (title.startsWith(k)) {
        score = 80;
      } else if (title.contains(k)) {
        score = 60;
      } else if (artist.contains(k)) {
        score = 40;
      }
      scored.add(MapEntry(score - i, s));
    }
    scored.sort((a, b) => b.key.compareTo(a.key));
    return [for (final e in scored) e.value];
  }

  /// 跨源弱去重：返回「同一首歌出现在多个源」的映射。
  /// 仅用于标注，不删除任何条目（各源音质与取链成功率不同）。
  static Map<String, List<String>> duplicates(List<SourceGroup> groups) {
    final seen = <String, List<String>>{};
    for (final g in groups) {
      for (final s in g.songs) {
        final owners = seen.putIfAbsent(_dupKey(s), () => []);
        if (!owners.contains(g.sourceId)) owners.add(g.sourceId);
      }
    }
    return {
      for (final e in seen.entries)
        if (e.value.length > 1) e.key: e.value,
    };
  }

  static String _dupKey(MusicInfo s) {
    final main = s.artist.split(RegExp(r'[ /、,&]')).first.trim().toLowerCase();
    return '${s.title.trim().toLowerCase()}|$main';
  }

  static String _short(Object e) {
    final s = e.toString().replaceAll('\n', ' ');
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }
}