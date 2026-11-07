import '../../core/services/playlists.dart';

/// 歌单内歌曲搜索（参考 CyShineMusic 的 playlist_search.dart）。
///
/// 设计要点（对齐参考实现）：
///   · 空白分隔多关键词，**全部命中**才算匹配（AND，不是 OR）
///     —— 输入「周杰伦 晴天」应精确定位，而不是把含任一词的都列出来
///   · 匹配歌名 / 歌手 / 专辑 / 本地文件名四个字段
///   · 大小写不敏感
///
/// 为什么是纯函数：这样能脱离 UI 单测，也能被"批量操作"等其他
/// 场景复用（如全选当前搜索结果）。
List<({int index, PlaylistEntry entry})> filterEntriesByQuery(
  List<PlaylistEntry> entries,
  String query,
) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList(growable: false);

  if (terms.isEmpty) {
    return [
      for (var i = 0; i < entries.length; i++) (index: i, entry: entries[i]),
    ];
  }

  final out = <({int index, PlaylistEntry entry})>[];
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    // 本地曲目额外用文件名参与匹配（标题往往和文件名不同）
    // 不用 package:path —— 它只是传递依赖，直接 import 会触发
    // depend_on_referenced_packages。这里只需去目录 + 去扩展名。
    final raw = e.resolvedPath ?? '';
    final name = raw.split('/').last.split(r'\\').last;
    final fileName =
        name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
    final haystack = [e.title, e.artist, e.album ?? '', fileName]
        .join('\n')
        .toLowerCase();
    if (terms.every(haystack.contains)) {
      out.add((index: i, entry: e));
    }
  }
  return out;
}