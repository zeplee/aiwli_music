import '../../core/services/logger.dart';
import 'builtin_base.dart';

/// 一条评论。
class CommentItem {
  const CommentItem({
    required this.user,
    required this.content,
    this.likedCount = 0,
    this.time,
  });
  final String user;
  final String content;
  final int likedCount;
  final String? time;
}

/// 内置评论获取：网易云为主（公开接口），失败返回空列表。
class CommentSdk {
  CommentSdk._();

  static Future<List<CommentItem>> fetch({
    required String sourceId,
    required String musicId,
    String title = '',
    String artist = '',
    int limit = 30,
  }) async {
    // ① 网易曲目：直接用 id
    final wyId = musicId.replaceFirst(RegExp(r'^wy_'), '');
    if (sourceId == 'wy' || wyId != musicId) {
      final r = await _wyHot(wyId, limit);
      if (r.isNotEmpty) return r;
    }
    // ② 其他平台：按「歌名+歌手」在网易搜索，拿网易自己的 id 再取评论
    //    （各平台 id 空间不同，直接借用会拿到别的歌的评论）
    if (title.isNotEmpty) {
      final id = await _wySearchId(title, artist);
      if (id != null) {
        final r = await _wyHot(id, limit);
        if (r.isNotEmpty) return r;
      }
    }
    return const [];
  }

  /// 在网易搜索匹配曲目，返回其 id。
  static Future<String?> _wySearchId(String title, String artist) async {
    try {
      final q = '$title $artist'.trim();
      final raw = await BuiltinHttp.getRaw(
        'https://music.163.com/api/search/get'
        '?s=${Uri.encodeComponent(q)}&type=1&limit=3',
        headers: const {
          'Referer': 'https://music.163.com/',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 Chrome/126.0 Safari/537.36',
        },
      );
      final body = tryDecodeJson(raw);
      if (body is! Map) return null;
      final songs = (body['result'] as Map?)?['songs'];
      if (songs is! List || songs.isEmpty) return null;
      for (final s in songs) {
        if (s is! Map) continue;
        final name = '${s['name'] ?? ''}';
        if (_similar(name, title)) {
          final id = '${s['id']}';
          AppLog.i('CommentSdk', '跨平台匹配评论「$title - $artist」→ wy:$id');
          return id;
        }
      }
      final id = '${(songs.first as Map)['id']}';
      return id.isEmpty ? null : id;
    } catch (_) {
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

  /// 网易云热评（旧版公开接口，无需 eapi 加密）。
  static Future<List<CommentItem>> _wyHot(String id, int limit) async {
    try {
      final raw = await BuiltinHttp.getRaw(
        'https://music.163.com/api/v1/resource/comments/R_SO_4_$id'
        '?limit=$limit&offset=0',
        headers: const {
          'Referer': 'https://music.163.com/',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      );
      final body = tryDecodeJson(raw);
      if (body is! Map) return const [];
      final list = body['hotComments'] ?? body['comments'];
      if (list is! List) return const [];
      final out = <CommentItem>[];
      for (final e in list) {
        if (e is! Map) continue;
        final user = e['user'];
        final nickname = user is Map ? '${user['nickname'] ?? '匿名'}' : '匿名';
        final content = '${e['content'] ?? ''}'.trim();
        if (content.isEmpty) continue;
        final ts = e['time'];
        out.add(CommentItem(
          user: nickname,
          content: content,
          likedCount: (e['likedCount'] as num?)?.toInt() ?? 0,
          time: ts is num
              ? DateTime.fromMillisecondsSinceEpoch(ts.toInt())
                  .toString()
                  .substring(0, 16)
              : null,
        ));
      }
      AppLog.i('CommentSdk', '网易热评命中 id=$id 条数=${out.length}');
      return out;
    } catch (e) {
      AppLog.w('CommentSdk', '网易热评失败 id=$id: $e');
      return const [];
    }
  }
}
