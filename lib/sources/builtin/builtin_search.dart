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
  }) : songs = songs ?? <MusicInfo>[];

  final String sourceId;
  final String label; // 展示名（酷我 / QQ音乐 / 网易云）
  SourceSearchState state;
  List<MusicInfo> songs;
  String? error;

  bool get hasResults => songs.isNotEmpty;
  int get count => songs.length;
}

/// 内置平台聚合搜索。
///
/// 与 lx-music / 同类实现一致的策略：
///  - 全部平台**并发**请求，谁先返回先展示（渐进式）
///  - **单源失败不影响其他源**（各自记录 error）
///  - 结果**按源分组**（比单列表更利于跨源对比音质）
///  - 组内按关键词相似度排序
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

  /// 并发搜索，逐源回调（用于渐进式 UI）。
  ///
  /// [onGroup] 每完成一个源就回调一次，传当前全部分组快照。
  /// 返回最终分组列表。
  static Future<List<SourceGroup>> searchAll(
    String keyword, {
    int page = 1,
    int limit = 30,
    Set<String>? enabled,
    void Function(List<SourceGroup> groups)? onGroup,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final kw = keyword.trim();
    final groups = <SourceGroup>[
      for (final id in order)
        if (enabled == null || enabled.contains(id))
          SourceGroup(sourceId: id, label: labels[id] ?? id),
    ];
    if (kw.isEmpty || groups.isEmpty) return groups;

    void emit() => onGroup?.call([
          for (final g in groups)
            SourceGroup(
              sourceId: g.sourceId,
              label: g.label,
              state: g.state,
              songs: List.of(g.songs),
              error: g.error,
            ),
        ]);

    await Future.wait(groups.map((g) async {
      g.state = SourceSearchState.loading;
      emit();
      try {
        final list = await _searchOne(g.sourceId, kw, page, limit).timeout(timeout);
        g.songs = _rank(list, kw);
        g.state = SourceSearchState.done;
      } catch (e) {
        g.state = SourceSearchState.failed;
        g.error = _short(e);
        AppLog.w('BuiltinSearch', '${g.label} 搜索失败: ${g.error}');
      }
      emit();
    }));

    return groups;
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

  /// 跨源弱去重：同「歌名 + 主歌手」的后出现者合并到首个分组之后。
  ///
  /// 注意：**不删除**后出现的条目，只在 UI 层标注"其他源也有"，
  /// 因为不同源的可用音质与取链成功率不同，用户需要保留选择权。
  static Map<String, List<String>> duplicates(List<SourceGroup> groups) {
    final seen = <String, List<String>>{};
    for (final g in groups) {
      for (final s in g.songs) {
        final key = _dupKey(s);
        final owners = seen.putIfAbsent(key, () => []);
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