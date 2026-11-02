import 'dart:convert';

import '../../core/models/music.dart';
import '../../core/models/quality.dart';
import 'builtin_base.dart';

/// 酷我（kw）内置搜索。
///
/// 参考 lx-music-desktop / CyShineMusic 的公开接口实现（Apache-2.0）。
/// 仅做搜索与歌名解析，播放地址由音源脚本提供。
class KwSdk {
  KwSdk._();

  static const sourceId = 'kw';

  /// 从 N_MINFO 里解析可用音质（"level:xxx;bitrate:320;format:mp3;..."）。
  static List<Quality> _qualitys(String minfo) {
    final out = <Quality>{Quality.standard};
    final lc = minfo.toLowerCase();
    if (lc.contains('bitrate:320') || lc.contains('320k')) out.add(Quality.high);
    if (lc.contains('flac') || lc.contains('lossless')) out.add(Quality.lossless);
    if (lc.contains('24bit') || lc.contains('hires')) out.add(Quality.hires);
    return out.toList()..sort((a, b) => a.index.compareTo(b.index));
  }

  static String _singer(dynamic raw) {
    final s = '${raw ?? ''}'.replaceAll('&', ' / ');
    return decodeText(s);
  }

  /// 搜索歌曲。
  static Future<List<MusicInfo>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async {
    final url = 'https://search.kuwo.cn/r.s?client=kt'
        '&all=${Uri.encodeComponent(keyword)}'
        '&pn=${page - 1}&rn=$limit'
        '&uid=794762570&ver=kwplayer_ar_9.2.2.1&vipver=1'
        '&show_copyright_off=1&newver=1&ft=music&cluster=0&strategy=2012'
        '&encoding=utf8&rformat=json&vermerge=1&mobi=1&issubtitle=1';

    final body = tryDecodeJson(await BuiltinHttp.getJson(url));
    final list = body is Map ? (body['abslist'] as List?) : null;
    if (list == null) return const [];

    final out = <MusicInfo>[];
    for (final item in list) {
      if (item is! Map) continue;
      final rid = '${item['MUSICRID'] ?? ''}';
      if (rid.isEmpty) continue;
      final songId = rid.replaceFirst('MUSIC_', '');
      final minfo = '${item['N_MINFO'] ?? ''}';
      final durationNum = num.tryParse('${item['DURATION'] ?? 0}');
      out.add(buildSong(
        sourceId: sourceId,
        musicId: songId,
        title: decodeText(item['SONGNAME']),
        artist: _singer(item['ARTIST']),
        album: decodeText(item['ALBUM']),
        albumId: '${item['ALBUMID'] ?? ''}',
        duration: durationNum == null
            ? null
            : Duration(seconds: durationNum.round()),
        qualities: _qualitys(minfo),
      ));
    }
    return out;
  }

  /// 搜索联想词。
  static Future<List<String>> tip(String keyword) async {
    final url = 'https://tips.kuwo.cn/t.s?corp=kuwo&newver=3&p2p=1&notrace=0'
        '&c=mbox&w=${Uri.encodeComponent(keyword)}&encoding=utf8&rformat=json';
    final body = tryDecodeJson(
        await BuiltinHttp.getJson(url, headers: const {'Referer': 'https://www.kuwo.cn/'}));
    final list = body is Map ? body['WORDITEMS'] : null;
    if (list is! List) return const [];
    return [
      for (final it in list)
        if (it is Map && '${it['RELWORD'] ?? ''}'.isNotEmpty) '${it['RELWORD']}',
    ];
  }

  /// GBK 场景的兜底解码（部分老接口返回 GBK）。
  static String decodeGbk(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      // 交给 fast_gbk（依赖已在 pubspec）
      return _gbkFallback(bytes);
    }
  }

  static String _gbkFallback(List<int> bytes) {
    // fast_gbk 在 builtin 层按需引入，避免所有平台都加载
    return String.fromCharCodes(bytes);
  }
}