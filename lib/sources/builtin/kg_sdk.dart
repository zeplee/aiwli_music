import '../../core/models/music.dart';
import '../../core/models/quality.dart';
import 'builtin_base.dart';

/// 酷狗（kg）内置搜索。
///
/// 接口 `songsearch.kugou.com/song_search_v2`（Web 版，无需签名）。
/// 算法与字段映射移植自 lx-music-desktop / CyShineMusic（Apache-2.0）。
class KgSdk {
  KgSdk._();

  static const sourceId = 'kg';

  static Future<List<MusicInfo>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async {
    final url = 'https://songsearch.kugou.com/song_search_v2'
        '?keyword=${Uri.encodeComponent(keyword)}'
        '&page=$page&pagesize=$limit&userid=0&clientver=&platform=WebFilter'
        '&filter=2&iscorrection=1&privilege_filter=0&area_code=1';

    final body = tryDecodeJson(await BuiltinHttp.getJson(url));
    if (body is! Map || body['error_code'] != 0) return const [];

    final lists = body['data']?['lists'] as List? ?? const [];
    final seen = <String>{};
    final out = <MusicInfo>[];

    for (final item in lists) {
      if (item is! Map) continue;
      // Grp 是「同曲不同版本」分组，摊平后去重
      final candidates = <Map>[
        item,
        ...((item['Grp'] as List?) ?? const []).whereType<Map>(),
      ];
      for (final raw in candidates) {
        final audioId = '${raw['Audioid'] ?? ''}';
        final hash = '${raw['FileHash'] ?? ''}';
        final key = '${audioId}_$hash';
        if (audioId.isEmpty || seen.contains(key)) continue;
        seen.add(key);

        final durNum = num.tryParse('${raw['Duration'] ?? 0}');
        out.add(buildSong(
          sourceId: sourceId,
          musicId: audioId, // 契约：musicId 用 Audioid；hash 由脚本自行解析
          title: '${raw['SongName'] ?? ''}',
          artist: joinSingers(raw['Singers']),
          album: '${raw['AlbumName'] ?? ''}',
          albumId: '${raw['AlbumID'] ?? ''}',
          duration: durNum == null ? null : Duration(seconds: durNum.round()),
          qualities: _qualitys(raw),
        ));
      }
    }
    return out;
  }

  /// 酷狗搜索结果的音质位：SQ(无损) / HQ(320k) / PQ(128k) 字段存在且非 0。
  static List<Quality> _qualitys(Map raw) {
    final out = <Quality>{Quality.standard};
    bool has(String k) {
      final v = '${raw[k] ?? '0'}';
      return v != '0' && v.isNotEmpty && v != 'null';
    }

    if (has('HQFileHash') || has('HQFileSize')) out.add(Quality.high);
    if (has('SQFileHash') || has('SQFileSize')) out.add(Quality.lossless);
    if (has('ResFileHash') || has('ResFileSize')) out.add(Quality.hires);
    return out.toList()..sort((a, b) => a.index.compareTo(b.index));
  }
}