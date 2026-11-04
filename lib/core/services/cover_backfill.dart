import '../../sources/builtin/builtin_search.dart';
import 'logger.dart';

/// 旧数据封面回填。
///
/// 历史遗留：早期收藏/历史在写入时不带 picUrl，导致列表全是占位渐变块。
/// 这里按「歌名 + 歌手」回源方搜索，命中同名同歌手时补上封面地址。
/// 只做一次性补齐，不覆盖已有封面；失败静默（网络/源不可用属正常）。
class CoverBackfill {
  /// 返回 {key: picUrl}，key 为 'sourceId/musicId'。
  static Future<Map<String, String>> resolve(
    List<({String sourceId, String musicId, String title, String artist})> items, {
    int maxItems = 40,
  }) async {
    final out = <String, String>{};
    if (items.isEmpty) return out;

    // 按源分组，减少搜索次数：同一个源的歌用一次关键词搜索批量匹配
    final bySource = <String, List<({String musicId, String title, String artist})>>{};
    for (final it in items.take(maxItems)) {
      // 记录源，用于回填上游按源分组
      bySource.putIfAbsent(
          it.sourceId,
          () => []).add(
          (musicId: it.musicId, title: it.title, artist: it.artist));
    }

    for (final entry in bySource.entries) {
      final sourceId = entry.key;
      if (sourceId == 'local' || sourceId == 'url') continue;
      for (final it in entry.value) {
        try {
          final groups = await BuiltinSearch.searchAll(
            '${it.title} ${it.artist}',
            enabled: {sourceId},
            limit: 5,
          );
          for (final g in groups) {
            for (final m in g.songs) {
              final pic = m.album?.picUrl;
              if (pic == null || pic.isEmpty) continue;
              if (!_sameSong(it.title, m.title)) continue;
              out['$sourceId/${it.musicId}'] = pic;
              break;
            }
          }
        } catch (e) {
          AppLog.w('CoverBackfill', '回填失败 ${it.title}: $e');
        }
      }
    }
    AppLog.i('CoverBackfill', '回填完成：${out.length}/${items.length} 命中封面');
    return out;
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\-_·,，、&()（）\[\]【】:：]'), '');

  static bool _sameSong(String a, String b) {
    final x = _norm(a);
    final y = _norm(b);
    if (x.isEmpty || y.isEmpty) return false;
    return x == y || x.contains(y) || y.contains(x);
  }
}
