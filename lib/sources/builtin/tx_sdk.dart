import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../core/models/music.dart';
import '../../core/models/quality.dart';
import 'builtin_base.dart';
import 'crypto_util.dart';

/// QQ 音乐（tx）内置搜索。
///
/// 请求体走 `musics.fcg` 私有接口，需 zzcSign 签名（sha1 + 异或混淆 + base64）。
/// 算法移植自 lx-music-desktop / CyShineMusic（Apache-2.0）。
class TxSdk {
  TxSdk._();

  static const sourceId = 'tx';

  static const _part1 = [23, 14, 6, 36, 16, 40, 7, 19];
  static const _part2 = [16, 1, 32, 12, 19, 27, 8, 5];
  static const _scramble = [
    89, 39, 179, 150, 218, 82, 58, 252, 177, 52, //
    186, 123, 120, 64, 242, 133, 143, 161, 121, 179,
  ];

  /// zzcSign: sha1(body) -> XOR scramble -> base64 stripped -> zzc{part1}{b64}{part2}
  static String _zzcSign(String text) {
    final hash = CryptoUtil.sha1Hex(text);
    String pick(List<int> idx) =>
        idx.map((i) => i < hash.length ? hash[i] : '').join();
    final scrambled = Uint8List(_scramble.length);
    for (var i = 0; i < _scramble.length; i++) {
      final pair = hash.substring(i * 2, i * 2 + 2);
      scrambled[i] = _scramble[i] ^ int.parse(pair, radix: 16);
    }
    final b64 = base64.encode(scrambled).replaceAll(RegExp(r'[\\/+=]'), '');
    return 'zzc${pick(_part1)}$b64${pick(_part2)}'.toLowerCase();
  }

  static Map<String, dynamic> _body(String keyword, int page, int limit) => {
        'comm': {
          'ct': '11',
          'cv': '14090508',
          'v': '14090508',
          'tmeAppID': 'qqmusic',
          'phonetype': 'EBG-AN10',
          'deviceScore': '553.47',
          'devicelevel': '50',
          'newdevicelevel': '20',
          'rom': 'HuaWei/EMOTION/EmotionUI_14.2.0',
          'os_ver': '12',
          'OpenUDID': '0',
          'OpenUDID2': '0',
          'QIMEI36': '0',
          'udid': '0',
          'chid': '0',
          'aid': '0',
          'oaid': '0',
          'taid': '0',
          'tid': '0',
          'wid': '0',
          'uid': '0',
          'sid': '0',
          'modeSwitch': '6',
          'teenMode': '0',
          'ui_mode': '2',
          'nettype': '1020',
          'v4ip': '',
        },
        'req': {
          'module': 'music.search.SearchCgiService',
          'method': 'DoSearchForQQMusicMobile',
          'param': {
            'search_type': 0,
            'searchid': Random().nextInt(1 << 32).toString(),
            'query': keyword,
            'page_num': page,
            'num_per_page': limit,
            'highlight': 0,
            'nqc_flag': 0,
            'multi_zhida': 0,
            'cat': 2,
            'grp': 1,
            'sin': 0,
            'sem': 0,
          },
        },
      };

  /// 搜索。失败按指数退避重试（接口偶发返回 code!=0）。
  static Future<List<MusicInfo>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async {
    final data = await _request(keyword, page, limit);
    if (data == null) return const [];
    final rawList = (data['item_song'] ?? data['song']?['list'] ?? const [])
        as List;
    final out = <MusicInfo>[];
    for (final item in rawList) {
      if (item is! Map) continue;
      final file = item['file'];
      if (file is! Map) continue;
      final mid = '${item['mid'] ?? ''}';
      if (mid.isEmpty) continue;
      final album = item['album'];
      final albumMid = album is Map ? '${album['mid'] ?? ''}' : '';
      final interval = num.tryParse('${item['interval'] ?? 0}');
      out.add(buildSong(
        sourceId: sourceId,
        musicId: mid,
        title: '${item['title'] ?? item['name'] ?? ''}',
        artist: joinSingers(item['singer']),
        album: album is Map ? '${album['name'] ?? ''}' : '',
        albumId: albumMid,
        picUrl: albumMid.isEmpty
            ? null
            : 'https://y.gtimg.cn/music/photo_new/T002R300x300M000$albumMid.jpg',
        duration: interval == null
            ? null
            : Duration(seconds: interval.round()),
        qualities: _qualitys(file),
      ));
    }
    return out;
  }

  /// QQ 的音质从 file 字段推断（size_hires/size_flac/size_320mp3 等）。
  static List<Quality> _qualitys(Map file) {
    final out = <Quality>{Quality.standard};
    if ('${file['size_320mp3'] ?? ''}' != '' && '${file['size_320mp3']}' != '0') {
      out.add(Quality.high);
    }
    if ('${file['size_flac'] ?? ''}' != '' && '${file['size_flac']}' != '0') {
      out.add(Quality.lossless);
    }
    if ('${file['size_hires'] ?? ''}' != '' && '${file['size_hires']}' != '0') {
      out.add(Quality.hires);
    }
    return out.toList()..sort((a, b) => a.index.compareTo(b.index));
  }

  static Future<Map?> _request(
    String keyword,
    int page,
    int limit, [
    int retry = 0,
  ]) async {
    final body = _body(keyword, page, limit);
    final json = jsonEncode(body);
    final sign = _zzcSign(json);
    try {
      final raw = await BuiltinHttp.getRaw(
        'https://u.y.qq.com/cgi-bin/musics.fcg?sign=$sign',
        method: 'POST',
        body: json,
        headers: const {
          'User-Agent': 'QQMusic 14090508(android 12)',
          'Content-Type': 'application/json',
        },
      );
      final decoded = tryDecodeJson(raw);
      if (decoded is Map) {
        final req = decoded['req'];
        final ok = decoded['code'] == 0 && req is Map && req['code'] == 0;
        if (ok) {
          final data = (req['data'] as Map).cast<String, dynamic>();
          final inner = data['body'];
          return inner is Map ? inner.cast<String, dynamic>() : data;
        }
      }
    } catch (_) {}
    if (retry < 3) {
      await Future<void>.delayed(Duration(milliseconds: 250 * (retry + 1)));
      return _request(keyword, page, limit, retry + 1);
    }
    return null;
  }
}