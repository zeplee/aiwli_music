import '../../core/services/logger.dart';
import 'builtin_base.dart';

/// 内置歌词获取：多平台直连（不依赖音源脚本）。
///
/// 优先级：酷我（有逐字 krc 但此处先取 lrc）→ 网易（含翻译/罗马音）→ QQ。
/// 全部失败返回 null，上层显示"暂无歌词"。
class LyricSdk {
  LyricSdk._();

  /// 取歌词。返回 lrc 文本 + 可选翻译/罗马音。
  static Future<LrcResult?> fetch({
    required String sourceId,
    required String musicId,
  }) async {
    // 酷我 id 形如 kw_123 / 纯数字
    final kwId = musicId.replaceFirst(RegExp(r'^kw_'), '');
    final wyId = musicId.replaceFirst(RegExp(r'^wy_'), '');
    final txMid = musicId.replaceFirst(RegExp(r'^tx_'), '');

    if (sourceId == 'wy' || wyId != musicId) {
      final r = await _fromWy(wyId);
      if (r != null) return r;
    }
    if (sourceId == 'kw' || kwId != musicId) {
      final r = await _fromKw(kwId);
      if (r != null) return r;
    }
    if (sourceId == 'tx' || txMid != musicId) {
      final r = await _fromTx(txMid);
      if (r != null) return r;
    }
    return null;
  }

  /// 酷我：lrclist / 逐字 krc。公开接口。
  static Future<LrcResult?> _fromKw(String id) async {
    try {
      final raw = await BuiltinHttp.getJson(
        'https://m.kuwo.cn/newh5/singles/songinfoandlrc?musicId=$id',
        headers: const {'Referer': 'https://m.kuwo.cn/'},
      );
      final body = tryDecodeJson(raw);
      if (body is! Map) return null;
      final list = body['data']?['lrclist'];
      if (list is! List || list.isEmpty) return null;
      final buf = StringBuffer();
      for (final e in list) {
        if (e is! Map) continue;
        final t = num.tryParse('${e['time'] ?? ''}');
        final text = '${e['lineLyric'] ?? ''}';
        if (t == null || text.isEmpty) continue;
        final sec = t;
        final m = (sec ~/ 60).toString().padLeft(2, '0');
        final s = (sec % 60).toStringAsFixed(2).padLeft(5, '0');
        buf.writeln('[$m:$s]$text');
      }
      final lrc = buf.toString();
      if (lrc.trim().isEmpty) return null;
      AppLog.i('LyricSdk', '酷我歌词命中 id=$id');
      return LrcResult(lrc);
    } catch (_) {
      return null;
    }
  }

  /// 网易：eapi 歌词（含翻译 tlyric / 罗马音 romalrc）。
  static Future<LrcResult?> _fromWy(String id) async {
    try {
      final raw = await BuiltinHttp.getJson(
        'https://music.163.com/api/song/lyric?id=$id&lv=1&kv=1&tv=1&rv=1',
        headers: const {
          'Referer': 'https://music.163.com/',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      );
      final body = tryDecodeJson(raw);
      if (body is! Map) return null;
      final lrc = body['lrc']?['lyric'] as String?;
      if (lrc == null || lrc.trim().isEmpty) return null;
      final tlyric = body['tlyric']?['lyric'] as String?;
      final romalrc = body['romalrc']?['lyric'] as String?;
      AppLog.i('LyricSdk',
          '网易歌词命中 id=$id 长度=${lrc.length} 翻译=${tlyric?.length ?? 0} 罗马音=${romalrc?.length ?? 0}');
      return LrcResult(lrc, translation: tlyric, roman: romalrc);
    } catch (_) {
      return null;
    }
  }

  /// QQ 音乐：fcg 歌词接口（base64 返回）。
  static Future<LrcResult?> _fromTx(String mid) async {
    try {
      final raw = await BuiltinHttp.getJson(
        'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg'
        '?songmid=$mid&format=json&nobase64=0&g_tk=5381',
        headers: const {'Referer': 'https://y.qq.com/'},
      );
      var body = tryDecodeJson(raw);
      if (body is! Map) return null;
      final lrc = body['lyric'] as String?;
      if (lrc == null || lrc.isEmpty) return null;
      final decoded = _maybeBase64(lrc);
      if (decoded.trim().isEmpty) return null;
      AppLog.i('LyricSdk', 'QQ歌词命中 mid=$mid');
      return LrcResult(decoded);
    } catch (_) {
      return null;
    }
  }

  static String _maybeBase64(String s) {
    if (s.contains('[')) return s; // 已是明文 lrc
    try {
      return utf8DecodeBase64(s);
    } catch (_) {
      return s;
    }
  }
}

/// 歌词结果：原文 + 可选翻译 / 罗马音。
class LrcResult {
  const LrcResult(this.lyric, {this.translation, this.roman});
  final String lyric;
  final String? translation;
  final String? roman;
}
