import '../../core/services/comment_paging.dart';
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

/// 内置评论获取：网易云为主（公开接口）。
///
/// [fetchPage] 是分页版本，供 CommentService/CommentPaging 使用；
/// [fetch] 保留给旧调用点，只返回第一页的 items。
class CommentSdk {
  CommentSdk._();

  static Future<List<CommentItem>> fetch({
    required String sourceId,
    required String musicId,
    String title = '',
    String artist = '',
    int limit = 30,
  }) async {
    try {
      final page = await fetchPage(
        sourceId: sourceId,
        musicId: musicId,
        title: title,
        artist: artist,
        limit: limit,
      );
      return page.items;
    } on CommentFetchException catch (e) {
      AppLog.w('CommentSdk', '评论获取失败（旧入口降级为空）: ${e.message}');
      return const <CommentItem>[];
    }
  }

  /// 分页取评论。热评只在首页并入且与普通评论去重；后续页只取普通评论，
  /// 避免热评反复出现。读取响应的 total/more 计算 hasMore。
  static Future<CommentPageResult<CommentItem>> fetchPage({
    required String sourceId,
    required String musicId,
    String title = '',
    String artist = '',
    int limit = 30,
    int offset = 0,
  }) async {
    // ① 网易曲目：直接用 id
    final wyId = musicId.replaceFirst(RegExp(r'^wy_'), '');
    if (sourceId == 'wy' || wyId != musicId) {
      final r = await _wyHot(wyId, limit, offset);
      if (r.items.isNotEmpty) return r;
    }
    // ② 其他平台：按「歌名+歌手」在网易搜索，拿网易自己的 id 再取评论
    if (title.isNotEmpty) {
      final id = await _wySearchId(title, artist);
      if (id != null) {
        final r = await _wyHot(id, limit, offset);
        if (r.items.isNotEmpty) return r;
      }
    }
    return CommentPageResult<CommentItem>(
      items: const <CommentItem>[],
      nextOffset: offset,
    );
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
    } catch (e) {
      AppLog.w('CommentSdk', '跨平台匹配评论失败「$title」: $e');
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
  static Future<CommentPageResult<CommentItem>> _wyHot(
      String id, int limit, int offset) async {
    try {
      final raw = await BuiltinHttp.getRaw(
        'https://music.163.com/api/v1/resource/comments/R_SO_4_$id'
        '?limit=$limit&offset=$offset',
        headers: const {
          'Referer': 'https://music.163.com/',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      );
      final body = tryDecodeJson(raw);
      if (body is! Map) {
        throw const CommentFetchException(
            CommentErrorKind.parse, '评论数据解析失败');
      }
      // 首页把热评并入普通评论并去重；后续页只用普通评论，
      // 否则热评会在每一页重复出现。
      final normal = body['comments'];
      final hot = offset == 0 ? body['hotComments'] : null;
      final all = <dynamic>[
        if (hot is List) ...hot,
        if (normal is List) ...normal,
      ];
      final out = <CommentItem>[];
      final seen = <String>{};
      for (final e in all) {
        if (e is! Map) continue;
        final user = e['user'];
        final nickname = user is Map ? '${user['nickname'] ?? '匿名'}' : '匿名';
        final content = '${e['content'] ?? ''}'.trim();
        if (content.isEmpty) continue;
        final ts = e['time'];
        final dedupe = '$nickname|$content|$ts';
        if (!seen.add(dedupe)) continue;
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
      final total = (body['total'] as num?)?.toInt() ?? 0;
      final more = body['more'] == true;
      // 服务端 offset 是「普通评论」的游标，热评不占游标。
      final nextOffset = offset + (normal is List ? normal.length : 0);
      final hasMore = more || (total > 0 && nextOffset < total);
      AppLog.i('CommentSdk',
          '评论 id=$id offset=$offset 条数=${out.length} total=$total hasMore=$hasMore');
      return CommentPageResult<CommentItem>(
        items: out,
        hasMore: hasMore && nextOffset > offset,
        total: total,
        nextOffset: nextOffset,
      );
    } catch (e) {
      AppLog.w('CommentSdk', '评论请求失败 id=$id offset=$offset: $e');
      if (e is CommentFetchException) rethrow;
      throw const CommentFetchException(
          CommentErrorKind.network, '评论加载失败，请检查网络后重试');
    }
  }
}
