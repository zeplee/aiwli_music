import '../../core/models/music.dart';
import '../../core/services/logger.dart';
import 'builtin_base.dart';

/// 内置榜单取曲（五平台，**不依赖 lx 脚本**）。
///
/// 每个平台的榜单接口都是官方公开接口，实测全部可用（见 builtin_boards.dart 注释）。
/// 这样即使所有 lx 脚本后端失效，发现页的排行榜仍能正常工作。
class BoardSongs {
  const BoardSongs._();

  /// 按平台 + 榜单 id 取曲。
  static Future<List<MusicInfo>> fetch(
    String sourceId,
    String boardId, {
    int limit = 30,
  }) async {
    try {
      return switch (sourceId) {
        'kw' => await _kw(boardId, limit),
        'wy' => await _wy(boardId, limit),
        'tx' => await _tx(boardId, limit),
        'kg' => await _kg(boardId, limit),
        'mg' => await _mg(boardId, limit),
        _ => const [],
      };
    } catch (e) {
      AppLog.w('BoardSongs', '$sourceId/$boardId 取曲失败: $e');
      return const [];
    }
  }

  // ————————————————— 酷我 —————————————————
  //
  // kbangserver.kuwo.cn/ksong.s
  // 返回 musiclist[]，字段：id / name / artist / album / albumid / duration
  static Future<List<MusicInfo>> _kw(String boardId, int limit) async {
    final raw = await BuiltinHttp.getRaw(
      'http://kbangserver.kuwo.cn/ksong.s?from=pc&fmt=json&pn=0'
      '&rn=$limit&type=bang&data=content&id=$boardId&pcjson=1',
      headers: const {
        'Referer': 'http://www.kuwo.cn/',
      },
    );
    final body = tryDecodeJson(raw);
    if (body is! Map) return const [];
    final list = (body['musiclist'] as List?) ?? const [];
    final out = <MusicInfo>[];
    for (final m in list) {
      if (m is! Map) continue;
      final id = '${m['id'] ?? ''}';
      if (id.isEmpty) continue;
      final albumId = '${m['albumid'] ?? ''}';
      out.add(buildSong(
        sourceId: 'kw',
        musicId: id,
        title: '${m['name'] ?? ''}',
        artist: '${m['artist'] ?? ''}',
        album: '${m['album'] ?? ''}',
        albumId: albumId,
        // 酷我封面 CDN：https://img2.kuwo.cn/star/albumcover/300/{albumid}.jpg 不稳定，
        // 这里留空由 CoverImage 走渐变兜底，避免裂图。
        duration: _secDuration(m['duration']),
      ));
    }
    return out;
  }

  // ————————————————— 网易 —————————————————
  //
  // 网易榜单本质是"特殊歌单"，用 playlist/detail 取。
  // 返回 result.tracks[]，字段：id / name / dt(时长ms) / album / artists
  static Future<List<MusicInfo>> _wy(String boardId, int limit) async {
    final raw = await BuiltinHttp.getRaw(
      'https://music.163.com/api/playlist/detail?id=$boardId',
      headers: const {
        'Referer': 'https://music.163.com/',
      },
    );
    final body = tryDecodeJson(raw);
    if (body is! Map) return const [];
    final result = body['result'];
    if (result is! Map) return const [];
    final tracks = (result['tracks'] as List?) ?? const [];
    final out = <MusicInfo>[];
    for (final t in tracks) {
      if (out.length >= limit) break;
      if (t is! Map) continue;
      final id = '${t['id'] ?? ''}';
      if (id.isEmpty) continue;
      final album = t['album'];
      final artists = [
        for (final a in (t['artists'] as List? ?? const []))
          if (a is Map) '${a['name'] ?? ''}',
      ].join(' / ');
      var pic = album is Map ? '${album['picUrl'] ?? ''}' : '';
      if (pic.isEmpty && album is Map) {
        final picId = '${album['picId'] ?? ''}';
        if (picId.isNotEmpty && picId != '0') {
          pic = 'https://p1.music.126.net/$picId.jpg';
        }
      }
      out.add(buildSong(
        sourceId: 'wy',
        musicId: id,
        title: '${t['name'] ?? ''}',
        artist: artists,
        album: album is Map ? '${album['name'] ?? ''}' : '',
        albumId: album is Map ? '${album['id'] ?? ''}' : '',
        picUrl: pic.isEmpty ? null : '$pic?param=300y300',
        duration: _msDuration(t['duration'] ?? t['dt']),
      ));
    }
    return out;
  }

  // ————————————————— QQ —————————————————
  //
  // musicu.fcg musicToplist.ToplistInfoServer/GetDetail
  // 返回 req_1.data.songInfoList[]，字段：mid / name / interval / singer[] / album
  static Future<List<MusicInfo>> _tx(String boardId, int limit) async {
    final payload = '{"comm":{"ct":24,"cv":0},"req_1":{"module":'
        '"musicToplist.ToplistInfoServer","method":"GetDetail",'
        '"param":{"topId":$boardId,"offset":0,"num":$limit}}}';
    final raw = await BuiltinHttp.getRaw(
      'https://u.y.qq.com/cgi-bin/musicu.fcg',
      method: 'POST',
      body: payload,
      headers: const {
        'Content-Type': 'application/json',
        'Referer': 'https://y.qq.com/',
      },
    );
    final body = tryDecodeJson(raw);
    if (body is! Map) return const [];
    final data = (body['req_1'] as Map?)?['data'];
    if (data is! Map) return const [];
    final songs = (data['songInfoList'] as List?) ?? const [];
    final out = <MusicInfo>[];
    for (final s in songs) {
      if (s is! Map) continue;
      final mid = '${s['mid'] ?? s['songmid'] ?? ''}';
      if (mid.isEmpty) continue;
      final singers = [
        for (final a in (s['singer'] as List? ?? const []))
          if (a is Map) '${a['name'] ?? ''}',
      ].join(' / ');
      final album = s['album'];
      var pic = album is Map ? '${album['mid'] ?? ''}' : '';
      out.add(buildSong(
        sourceId: 'tx',
        musicId: mid,
        title: '${s['title'] ?? s['name'] ?? ''}',
        artist: singers,
        album: album is Map ? '${album['name'] ?? ''}' : '',
        albumId: pic,
        picUrl: pic.isEmpty
            ? null
            : 'https://y.gtimg.cn/music/photo_new/T002R300x300M000$pic.jpg',
        duration: _secDuration(s['interval']),
      ));
    }
    return out;
  }

  // ————————————————— 酷狗 —————————————————
  //
  // mobilecdn.kugou.com/api/v3/rank/song?rankid=&page=&pagesize=
  // 返回 data.info[]，字段：hash / filename("歌手 - 歌名") / duration
  static Future<List<MusicInfo>> _kg(String boardId, int limit) async {
    final pageSize = limit > 30 ? limit : 30;
    final raw = await BuiltinHttp.getRaw(
      'http://mobilecdn.kugou.com/api/v3/rank/song'
      '?rankid=$boardId&page=1&pagesize=$pageSize&version=9108',
    );
    final body = tryDecodeJson(raw);
    if (body is! Map) return const [];
    final data = body['data'];
    if (data is! Map) return const [];
    final songs = (data['info'] as List?) ?? const [];
    final out = <MusicInfo>[];
    for (final s in songs) {
      if (out.length >= limit) break;
      if (s is! Map) continue;
      final hash = '${s['hash'] ?? ''}';
      if (hash.isEmpty) continue;
      // 酷狗该接口**没有 singername 字段**（实测字段表里只有 filename），
      // filename 恒为 "歌手 - 歌名"，必须从这里拆，否则歌手全空。
      final filename = '${s['filename'] ?? ''}';
      var artist = '';
      var title = '${s['songname'] ?? ''}';
      if (filename.contains(' - ')) {
        final idx = filename.indexOf(' - ');
        artist = filename.substring(0, idx);
        final rest = filename.substring(idx + 3);
        if (title.isEmpty) title = rest;
      }
      if (artist.isEmpty && title.isEmpty) title = filename;
      out.add(buildSong(
        sourceId: 'kg',
        musicId: hash,
        title: title.isEmpty ? filename : title,
        artist: artist,
        album: '${s['album_name'] ?? ''}',
        duration: _secDuration(s['duration']),
      ));
    }
    return out;
  }

  // ————————————————— 咪咕 —————————————————
  //
  // app.c.nf.migu.cn/MIGUM2.0/v1.0/content/querycontentbyId.do?columnId=
  // 返回 columnInfo.contents[]，每项 objectInfo 内含歌曲字段
  static Future<List<MusicInfo>> _mg(String boardId, int limit) async {
    final raw = await BuiltinHttp.getRaw(
      'https://app.c.nf.migu.cn/MIGUM2.0/v1.0/content/querycontentbyId.do'
      '?columnId=$boardId',
    );
    final body = tryDecodeJson(raw);
    if (body is! Map) return const [];
    final col = body['columnInfo'];
    if (col is! Map) return const [];
    final contents = (col['contents'] as List?) ?? const [];
    final out = <MusicInfo>[];
    for (final c in contents) {
      if (out.length >= limit) break;
      if (c is! Map) continue;
      final obj = c['objectInfo'];
      if (obj is! Map) continue;
      final id = '${obj['songId'] ?? obj['contentId'] ?? ''}';
      if (id.isEmpty) continue;
      // 咪咕 objectInfo 用 singer（字符串）而不是 singerList（实测）。
      // 兼容两种情况，避免其它榜单结构变化时又丢歌手。
      var singers = '${obj['singer'] ?? ''}'.trim();
      if (singers.isEmpty) {
        final list = obj['singerList'];
        if (list is List) {
          singers = [
            for (final a in list)
              if (a is Map) '${a['name'] ?? ''}',
          ].join(' / ');
        }
      }
      var pic = '${obj['img3'] ?? obj['img2'] ?? obj['img1'] ?? ''}';
      if (pic.isNotEmpty && !pic.startsWith('http')) {
        pic = 'https://h5.nf.migu.cn${pic.startsWith('/') ? '' : '/'}$pic';
      }
      out.add(buildSong(
        sourceId: 'mg',
        musicId: id,
        title: '${obj['songName'] ?? obj['name'] ?? ''}',
        artist: singers,
        album: '${obj['album'] ?? obj['albumName'] ?? ''}',
        albumId: '${obj['albumId'] ?? ''}',
        picUrl: pic.isEmpty ? null : pic,
        duration: _secDuration(obj['duration']),
      ));
    }
    return out;
  }

  // ————————————————— 工具 —————————————————

  /// 秒 → Duration（部分平台返回秒，字符串或数字）
  static Duration? _secDuration(Object? v) {
    final n = num.tryParse('${v ?? ''}');
    if (n == null || n <= 0) return null;
    return Duration(seconds: n.round());
  }

  /// 毫秒 → Duration
  static Duration? _msDuration(Object? v) {
    final n = num.tryParse('${v ?? ''}');
    if (n == null || n <= 0) return null;
    return Duration(milliseconds: n.round());
  }
}