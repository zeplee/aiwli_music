import '../../core/services/logger.dart';
import 'builtin_base.dart';

/// 内置歌词获取。
///
/// 关键设计：**不能直接拿曲目 id 跨平台查歌词**——各平台 id 空间不同
/// （酷我 142997 在网易是另一首歌）。正确做法是把「歌名 + 歌手」发到
/// 目标平台的搜索接口，拿到该平台自己的 id，再取歌词。
class LyricSdk {
  LyricSdk._();

  static const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 Chrome/126.0 Safari/537.36';

  /// 取歌词。[title]/[artist] 用于跨平台匹配。
  static Future<LrcResult?> fetch({
    required String sourceId,
    required String musicId,
    required String title,
    required String artist,
  }) async {
    // ① 曲目所属平台的官方 id 直查（同平台 id 空间一致，最准）
    final direct = await _direct(sourceId, musicId);
    if (direct != null) return direct;

    // ② 跨平台：搜歌名+歌手 → 拿该平台 id → 取歌词
    return _viaSearch(title, artist);
  }

  static Future<LrcResult?> _direct(String sourceId, String musicId) async {
    final id = musicId.replaceFirst(RegExp(r'^(kw|wy|tx|kg|mg)_'), '').trim();
    // 空 id / "0" 是无效曲目：直查会命中占位歌词（实测 id=0 返回 14 字符
    // 的垃圾文案），反而挡住后面的跨平台搜索兜底。
    if (id.isEmpty || id == '0' || int.tryParse(id) == 0) return null;
    switch (sourceId) {
      case 'wy':
        return _wyLyric(id);
      case 'tx':
        return _txLyric(id);
      case 'kw':
        return _kwLyric(id);
      default:
        return null;
    }
  }

  /// 跨平台兜底：网易搜索（接口稳定、返回翻译/罗马音）。
  static Future<LrcResult?> _viaSearch(String title, String artist) async {
    final q = '$title $artist'.trim();
    if (q.isEmpty) return null;
    try {
      final raw = await BuiltinHttp.getRaw(
        'https://music.163.com/api/search/get'
        '?s=${Uri.encodeComponent(q)}&type=1&limit=3',
        headers: const {'Referer': 'https://music.163.com/', 'User-Agent': _ua},
      );
      final body = tryDecodeJson(raw);
      if (body is! Map) return null;
      final songs = (body['result'] as Map?)?['songs'];
      if (songs is! List || songs.isEmpty) return null;

      String? pick;
      for (final s in songs) {
        if (s is! Map) continue;
        final name = '${s['name'] ?? ''}';
        final singers = [
          for (final a in (s['artists'] as List? ?? const []))
            if (a is Map) '${a['name'] ?? ''}',
        ].join('/');
        if (!_similar(name, title)) continue;
        if (artist.isNotEmpty && !_similar(singers, artist)) continue;
        pick = '${s['id']}';
        break;
      }
      pick ??= '${(songs.first as Map)['id']}';
      if (pick.isEmpty) return null;
      AppLog.i('LyricSdk', '跨平台匹配「$title - $artist」→ wy:$pick');
      return await _wyLyric(pick);
    } catch (e) {
      AppLog.w('LyricSdk', '跨平台歌词搜索失败: $e');
      return null;
    }
  }

  /// 网易：含翻译 tlyric / 罗马音 romalrc。
  static Future<LrcResult?> _wyLyric(String id) async {
    try {
      final raw = await BuiltinHttp.getRaw(
        'https://music.163.com/api/song/lyric?id=$id&lv=-1&kv=-1&tv=-1&rv=-1',
        headers: const {'Referer': 'https://music.163.com/', 'User-Agent': _ua},
      );
      final body = tryDecodeJson(raw);
      if (body is! Map) return null;
      final lrc = (body['lrc'] as Map?)?['lyric'] as String?;
      if (lrc == null || lrc.trim().isEmpty) return null;
      // 网易对无歌词曲目会返回很短的占位内容（实测 id=0 只有 14 字符）。
      // 少于 40 字符基本不可能是一首歌的完整歌词，视为无效。
      if (lrc.trim().length < 40) {
        AppLog.i('LyricSdk', '网易 id=$id 歌词过短(${lrc.trim().length})，视为无歌词');
        return null;
      }
      final tl = (body['tlyric'] as Map?)?['lyric'] as String?;
      final ro = (body['romalrc'] as Map?)?['lyric'] as String?;
      AppLog.i('LyricSdk',
          '网易歌词命中 id=$id len=${lrc.length} 译=${tl?.length ?? 0} 罗=${ro?.length ?? 0}');
      return LrcResult(lrc, translation: tl, roman: ro);
    } catch (e) {
      AppLog.w('LyricSdk', '网易歌词失败 id=$id: $e');
      return null;
    }
  }

  /// 酷我：mobile 接口（常 301，失败交给跨平台兜底）。
  static Future<LrcResult?> _kwLyric(String id) async {
    try {
      final raw = await BuiltinHttp.getRaw(
        'https://m.kuwo.cn/newh5/singles/songinfoandlrc?musicId=$id',
        headers: const {
          'Referer': 'https://m.kuwo.cn/',
          'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like '
              'Mac OS X) AppleWebKit/605.1.15',
        },
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
        final m = (t ~/ 60).toString().padLeft(2, '0');
        final s = (t % 60).toStringAsFixed(2).padLeft(5, '0');
        buf.writeln('[$m:$s]$text');
      }
      final lrc = buf.toString();
      if (lrc.trim().isEmpty) return null;
      AppLog.i('LyricSdk', '酷我歌词命中 id=$id');
      return LrcResult(lrc);
    } catch (e) {
      AppLog.w('LyricSdk', '酷我歌词失败 id=$id: $e');
      return null;
    }
  }

  /// QQ：base64 返回。
  static Future<LrcResult?> _txLyric(String mid) async {
    try {
      final raw = await BuiltinHttp.getRaw(
        'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg'
        '?songmid=$mid&format=json&nobase64=0&g_tk=5381',
        headers: const {'Referer': 'https://y.qq.com/', 'User-Agent': _ua},
      );
      final body = tryDecodeJson(raw);
      if (body is! Map) return null;
      final lrc = body['lyric'] as String?;
      if (lrc == null || lrc.isEmpty) return null;
      final decoded = lrc.contains('[') ? lrc : utf8DecodeBase64(lrc);
      if (decoded.trim().isEmpty) return null;
      final tl = body['trans'] as String?;
      AppLog.i('LyricSdk', 'QQ歌词命中 mid=$mid');
      return LrcResult(
        decoded,
        translation: (tl == null || tl.isEmpty)
            ? null
            : (tl.contains('[') ? tl : utf8DecodeBase64(tl)),
      );
    } catch (e) {
      AppLog.w('LyricSdk', 'QQ歌词失败 mid=$mid: $e');
      return null;
    }
  }

  static bool _similar(String a, String b) {
    String norm(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\-_·,，、&()（）\[\]【】]'), '');
    final x = norm(a);
    final y = norm(b);
    if (x.isEmpty || y.isEmpty) return false;
    return x.contains(y) || y.contains(x);
  }
}

/// 歌词结果：原文 + 可选翻译 / 罗马音。
class LrcResult {
  const LrcResult(this.lyric, {this.translation, this.roman});
  final String lyric;
  final String? translation;
  final String? roman;
}