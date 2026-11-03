import '../../core/models/music.dart';
import '../../core/models/quality.dart';
import 'builtin_base.dart';
import 'crypto_util.dart';

/// 咪咕（mg）内置搜索。
///
/// 接口 `jadeite.migu.cn/music_search/v3/search/searchAll`，需 sign 头
/// （md5(keyword + 固定盐 + deviceId + timestamp)）。
/// 算法移植自 lx-music-desktop / CyShineMusic（Apache-2.0）。
class MgSdk {
  MgSdk._();

  static const sourceId = 'mg';

  static const _deviceId = '963B7AA0D21511ED807EE5846EC87D20';
  static const _signatureMd5 = '6cdc72a439cef99a3418d2a78aa28c73';

  static Map<String, String> _headers(String time, String keyword) {
    final sign = CryptoUtil.md5Hex(
      '$keyword${_signatureMd5}yyapp2d16148780a1dcc7408e06336b98cfd50'
      '$_deviceId$time',
    );
    return {
      'uiVersion': 'A_music_3.6.1',
      'deviceId': _deviceId,
      'timestamp': time,
      'sign': sign,
      'channel': '0146921',
      'User-Agent': 'Mozilla/5.0 (Linux; Android 11.0.0) '
          'AppleWebKit/534.30 Mobile Safari/534.30',
    };
  }

  static const _switch = '{"song":1,"album":0,"singer":0,"tagSong":1,'
      '"mvSong":0,"bestShow":1,"songlist":0,"lyricSong":0}';

  static Future<List<MusicInfo>> search(
    String keyword, {
    int page = 1,
    int limit = 20,
  }) async {
    final time = DateTime.now().millisecondsSinceEpoch.toString();
    final url = 'https://jadeite.migu.cn/music_search/v3/search/searchAll'
        '?isCorrect=0&isCopyright=1'
        '&searchSwitch=${Uri.encodeComponent(_switch)}'
        '&pageSize=$limit&text=${Uri.encodeComponent(keyword)}'
        '&pageNo=$page&sort=0&sid=USS';

    final body =
        tryDecodeJson(await BuiltinHttp.getJson(url, headers: _headers(time, keyword)));
    if (body is! Map || body['code'] != '000000') return const [];

    final result = body['songResultData'] as Map? ?? const {};
    final seen = <String>{};
    final out = <MusicInfo>[];

    for (final group in (result['resultList'] as List?) ?? const []) {
      if (group is! List) continue;
      for (final data in group) {
        if (data is! Map) continue;
        final songId = '${data['songId'] ?? ''}';
        final copyrightId = '${data['copyrightId'] ?? ''}';
        if (songId.isEmpty || copyrightId.isEmpty) continue;
        if (!seen.add(copyrightId)) continue;

        final durNum = num.tryParse('${data['duration'] ?? 0}');
        final pics = data['img3'] ?? data['img2'] ?? data['img1'] ?? '';
        out.add(buildSong(
          sourceId: sourceId,
          musicId: songId,
          title: '${data['name'] ?? ''}',
          artist: joinSingers(data['singerList']),
          album: '${data['album'] ?? ''}',
          albumId: '${data['albumId'] ?? ''}',
          picUrl: '$pics'.isEmpty ? null : '$pics',
          duration: durNum == null ? null : Duration(seconds: durNum.round()),
          qualities: _qualitys(data),
        ));
      }
    }
    return out;
  }

  /// 咪咕音质位：PQ(128k) / HQ(320k) / SQ(无损) / ZQ24(24bit)。
  static List<Quality> _qualitys(Map data) {
    final out = <Quality>{Quality.standard};
    final formats = (data['audioFormats'] as List?) ?? const [];
    for (final f in formats) {
      if (f is! Map) continue;
      switch ('${f['formatType'] ?? ''}') {
        case 'HQ':
          out.add(Quality.high);
        case 'SQ':
          out.add(Quality.lossless);
        case 'ZQ24':
          out.add(Quality.hires);
      }
    }
    return out.toList()..sort((a, b) => a.index.compareTo(b.index));
  }
}