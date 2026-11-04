import 'dart:convert';
import 'dart:typed_data';

import '../../core/models/music.dart';
import '../../core/models/quality.dart';
import 'builtin_base.dart';
import 'crypto_util.dart';

/// 网易云音乐（wy）内置搜索。
///
/// 走 eapi 加密：`AES-128-ECB( path-36cd479b6b5-json-36cd479b6b5-md5 )`，
/// 参数以 hex 大写提交。算法移植自 lx-music-desktop / CyShineMusic（Apache-2.0）。
class WySdk {
  WySdk._();

  static const sourceId = 'wy';

  static final Uint8List _eapiKey =
      Uint8List.fromList(utf8.encode('e82ckenh8dichen8'));

  static const _ua =
      'NeteaseMusic/9.1.40.250128161425(9001040);Dalvik/2.1.0 '
      '(Linux; U; Android 14)';

  /// eapi 加密：path + 分隔符 + body + 分隔符 + md5，整体 AES-ECB。
  static Map<String, String> _eapi(String path, Object payload) {
    final text = payload is String ? payload : jsonEncode(payload);
    final message = 'nobody${path}use${text}md5forencrypt';
    final digest = CryptoUtil.md5Hex(message);
    final data = '$path-36cd479b6b5-$text-36cd479b6b5-$digest';
    final encrypted = CryptoUtil.aesEncryptEcbPkcs7(
      Uint8List.fromList(utf8.encode(data)),
      _eapiKey,
    );
    return {
      'params': CryptoUtil.bytesToHex(encrypted, upper: true),
      'appver': '9.1.40',
      'os': 'android',
    };
  }

  /// 搜索歌曲。
  static Future<List<MusicInfo>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async {
    const path = '/api/search/song/list/page';
    final form = _eapi(path, {
      'keyword': keyword,
      'needCorrect': '1',
      'channel': 'typing',
      'offset': limit * (page - 1),
      'scene': 'normal',
      'total': page == 1,
      'limit': limit,
    });

    final raw = await BuiltinHttp.getRaw(
      'https://interface.music.163.com/eapi/batch',
      method: 'POST',
      body: Uri(queryParameters: form).query,
      headers: {
        'User-Agent': _ua,
        'Content-Type': 'application/x-www-form-urlencoded',
        'origin': 'https://music.163.com',
      },
    );

    final body = tryDecodeJson(raw);
    if (body is! Map) return const [];
    final code = body['code'];
    if (code != 200 && code != 2000) return const [];

    final resources = (body['data']?['resources'] as List?) ?? const [];
    final out = <MusicInfo>[];
    for (final r in resources) {
      if (r is! Map) continue;
      final item = r['baseInfo']?['simpleSongData'];
      if (item is! Map) continue;
      final id = '${item['id'] ?? ''}';
      if (id.isEmpty) continue;
      // eapi 不同接口把专辑放在 album / al 下，字段名也可能是 picId / picUrl
      final album = item['album'] ?? item['al'];
      final durMs = num.tryParse('${item['duration'] ?? 0}');
      // 搜索接口的 album 往往只有 picId（无 picUrl），
      // 网易封面 CDN 规则：https://p{n}.music.126.net/{picId}?param=300y300
      var pic = album is Map ? '${album['picUrl'] ?? ''}' : '';
      if (pic.isEmpty && album is Map) {
        final picId = '${album['picId'] ?? ''}';
        // 注意必须有 .jpg 后缀，否则 CDN 返回 404
        if (picId.isNotEmpty && picId != '0') {
          pic = 'https://p1.music.126.net/$picId.jpg';
        }
      }
      out.add(buildSong(
        sourceId: sourceId,
        musicId: id,
        title: '${item['name'] ?? ''}',
        artist: _singers(item['ar'] ?? item['artists']),
        album: album is Map ? '${album['name'] ?? ''}' : '',
        albumId: album is Map ? '${album['id'] ?? ''}' : '',
        picUrl: pic.isEmpty ? null : '$pic?param=300y300',
        duration: durMs == null ? null : Duration(milliseconds: durMs.round()),
        qualities: _qualitys(item),
      ));
    }
    return out;
  }

  static String _singers(dynamic list) {
    if (list is! List) return '未知歌手';
    final names = <String>[
      for (final a in list)
        if (a is Map && '${a['name'] ?? ''}'.isNotEmpty) '${a['name']}',
    ];
    return names.isEmpty ? '未知歌手' : names.join(' / ');
  }

  /// 网易的音质位：hr(Hi-Res) / sq(无损) / h(320k) / m(192k) / l(128k)。
  static List<Quality> _qualitys(Map item) {
    final out = <Quality>{Quality.standard};
    final lvl = '${item['privilege']?['maxBrLevel'] ?? item['maxBrLevel'] ?? ''}';
    if (lvl.contains('hires') || lvl == 'hr') out.add(Quality.hires);
    if (lvl.contains('lossless') || lvl == 'sq' || lvl == 'lossless') {
      out.add(Quality.lossless);
    }
    if (lvl == 'h' || lvl.contains('exhigh')) out.add(Quality.high);
    return out.toList()..sort((a, b) => a.index.compareTo(b.index));
  }
}