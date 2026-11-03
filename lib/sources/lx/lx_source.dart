
import '../../core/models/music.dart';
import '../../core/models/quality.dart';
import '../../core/models/quality_rank.dart';
import '../runtime/runtime_host.dart';

/// lx 音源：全部能力由用户导入的脚本提供（musicUrl / lyric / pic / musicSearch /
/// boardList / boardSongs），壳内零内置源（合规约定：壳不分发任何音源）。
/// 脚本未声明的能力返回 null，调用方负责隐藏对应 UI。
class LxSource {
  LxSource({
    required this.id,
    required this.name,
    required this.script,
    this.musicFree = false,
  }) {
    _runtime = LxRuntime(id, script, musicFree: musicFree);
  }

  final String id;
  final String name;
  final String script;

  /// true = MusicFree 插件（CommonJS），经适配层跑在同一个 QuickJS 宿里。
  final bool musicFree;
  late final LxRuntime _runtime;

  bool enabled = true;
  Set<String> _actions = {'musicUrl'};
  bool _inited = false;

  Set<String> get actions => _actions;
  bool get ready => _inited && enabled;

  /// 等待脚本 inited 并记录能力（actions 来自脚本声明的 sources）。
  Future<bool> waitInited({Duration timeout = const Duration(seconds: 8)}) async {
    if (_inited) return true;
    final payload = await _runtime.initedFuture(timeout: timeout);
    if (payload == null) return false;
    final sources = (payload['sources'] as Map?) ?? const {};
    final first = sources.values.isNotEmpty
        ? (sources.values.first as Map).cast<Object?, Object?>()
        : null;
    final acts = ((first?['actions'] as List?) ?? const ['musicUrl']).cast<String>();
    _actions = acts.toSet();
    // 记录脚本声明的平台标识（kw/tx/wy/kg/mg…），用于「内置平台曲目
    // 借用脚本取链」时判断该脚本能否处理某平台。
    _platforms = {for (final k in sources.keys) k.toString()};
    // 解析每个平台声明的音质（lx 脚本规范里 sources[platform] 可带
    // 平台级 qualitys；MusicFree 插件没有这个概念，走空集合＝不限制）。
    _qualitiesByPlatform = {};
    for (final e in sources.entries) {
      final m = (e.value as Map?)?.cast<Object?, Object?>();
      final raw = m?['qualitys'] ?? m?['qualities'];
      final set = <Quality>{};
      if (raw is List) {
        for (final q in raw) {
          final parsed = q is Map
              ? QualityCode.fromCode('${q['type'] ?? ''}')
              : QualityCode.fromCode('$q');
          if (parsed != null) set.add(parsed);
        }
      }
      if (set.isNotEmpty) _qualitiesByPlatform[e.key.toString()] = set;
    }
    _inited = true;
    return true;
  }

  /// 平台 → 该平台支持的音质（脚本未声明时为空，表示不限制）。
  Map<String, Set<Quality>> _qualitiesByPlatform = {};

  /// 本源所有平台支持音质的并集；空集合表示脚本未声明（不做筛选）。
  Set<Quality> get declaredQualities {
    if (_qualitiesByPlatform.isEmpty) return const {};
    return {
      for (final s in _qualitiesByPlatform.values) ...s,
    };
  }

  /// 脚本 inited 时声明的平台标识集合。
  Set<String> _platforms = {};
  Set<String> get platforms => _platforms;

  /// 该脚本是否能处理指定平台（如内置搜索得到的 'kw'/'tx'）。
  bool supportsPlatform(String platform) =>
      _platforms.contains(platform) && _actions.contains('musicUrl');

  /// 搜索：脚本声明 musicSearch 能力则走脚本，否则返回 null（无内置源回退）。
  Future<List<MusicInfo>?> searchFromScript(String keyword, {int page = 1}) async {
    await waitInited();
    if (!_actions.contains('musicSearch')) return null;
    final r = await _runtime.dispatch({
      'source': id,
      'action': 'musicSearch',
      'info': {'text': keyword, 'word': keyword, 'page': page, 'limit': 30},
    });
    if (!r.ok) throw Exception('脚本搜索失败: ${r.error ?? '空结果'}');
    return parseScriptSongs(r.result, sourceId: id);
  }

  /// 榜单列表：脚本声明 boardList 能力才提供，否则 null（发现页隐藏板块）。
  Future<List<MusicBoard>?> boardListFromScript() async {
    await waitInited();
    if (!_actions.contains('boardList')) return null;
    final r = await _runtime.dispatch(
        {'source': id, 'action': 'boardList', 'info': const {}});
    if (!r.ok) throw Exception('榜单获取失败: ${r.error ?? '空结果'}');
    final List list = r.result is List
        ? r.result as List
        : (r.result is Map ? ((r.result as Map)['boards'] as List?) ?? const [] : const []);
    final out = <MusicBoard>[];
    for (final item in list) {
      if (item is! Map) continue;
      final m = item.cast<Object?, Object?>();
      final bid = '${m['id'] ?? m['bangId'] ?? m['boardId'] ?? ''}';
      final name = '${m['name'] ?? m['title'] ?? ''}';
      if (bid.isEmpty || name.isEmpty) continue;
      out.add(MusicBoard(id: bid, name: name));
    }
    return out;
  }

  /// 榜单歌曲：脚本声明 boardSongs 能力才提供，否则 null。
  Future<List<MusicInfo>?> boardSongsFromScript(String boardId,
      {int page = 1, int limit = 30}) async {
    await waitInited();
    if (!_actions.contains('boardSongs')) return null;
    final r = await _runtime.dispatch({
      'source': id,
      'action': 'boardSongs',
      'info': {'id': boardId, 'bangId': boardId, 'page': page, 'limit': limit},
    });
    if (!r.ok) throw Exception('榜单歌曲获取失败: ${r.error ?? '空结果'}');
    return parseScriptSongs(r.result, sourceId: id);
  }

  /// 取播放链接。quality: 128k/320k/flac/...
  ///
  /// [platform] 用于「内置平台搜索结果借用脚本取链」的场景：曲目的
  /// sourceId 是平台名（kw/tx/wy/kg/mg），而脚本需要的是它自己声明的平台
  /// 标识。不传则用本源 id。
  Future<String> getMusicUrl(
    MusicInfo song,
    Quality quality, {
    String? platform,
  }) async {
    await waitInited();
    final q = switch (quality) {
      Quality.standard => '128k',
      Quality.high => '320k',
      Quality.superQuality => '320k',
      Quality.lossless => 'flac',
      Quality.hires => 'flac24bit',
    };
    final r = await _runtime.dispatch({
      'source': platform ?? id,
      'action': 'musicUrl',
      'info': {
        'musicInfo': _musicInfoForScript(song),
        'type': q,
        'quality': q,
      },
    });
    if (r.ok && r.result is String && (r.result as String).isNotEmpty) {
      return r.result as String;
    }
    throw Exception('取链失败: ${r.error ?? '空结果'}');
  }

  /// 歌词：脚本若声明 lyric 能力则走脚本，否则返回 null（调用方回退内置源）。
  Future<String?> getLyricFromScript(MusicInfo song) async {
    if (!_actions.contains('lyric')) return null;
    await waitInited();
    final r = await _runtime.dispatch({
      'source': id,
      'action': 'lyric',
      'info': {'musicInfo': _musicInfoForScript(song)},
    });
    if (r.ok && r.result is Map) {
      final m = (r.result as Map).cast<Object?, Object?>();
      return m['lyric'] as String?;
    }
    return null;
  }

  /// 封面：脚本 pic 能力或回退。
  Future<Uri?> getCoverFromScript(MusicInfo song) async {
    if (!_actions.contains('pic')) return null;
    await waitInited();
    final r = await _runtime.dispatch({
      'source': id,
      'action': 'pic',
      'info': {'musicInfo': _musicInfoForScript(song)},
    });
    if (r.ok && r.result is String && (r.result as String).isNotEmpty) {
      return Uri.parse(r.result as String);
    }
    return null;
  }

  /// 传给脚本/插件的 musicInfo。
  ///
  /// 若曲目带原始对象（搜索阶段从源返回的完整 map），**以它为基底**再补齐
  /// 通用字段——MusicFree 插件取链读的就是 play_path_64 / qualitys /
  /// musicId 这些私有键，只给通用字段会导致「插件未返回播放地址」。
  Map<String, Object?> _musicInfoForScript(MusicInfo song) {
    final base = <String, Object?>{};
    final raw = song.raw;
    if (raw != null) {
      for (final e in raw.entries) {
        base['${e.key}'] = e.value;
      }
    }
    // 通用字段兜底（不覆盖已有值）
    base.putIfAbsent('songmid', () => song.musicId);
    base.putIfAbsent('hash', () => song.musicId);
    base.putIfAbsent('id', () => song.musicId);
    base.putIfAbsent('musicId', () => song.musicId);
    base.putIfAbsent('title', () => song.title);
    base.putIfAbsent('name', () => song.title);
    base.putIfAbsent('singer', () => song.artist);
    base.putIfAbsent('artist', () => song.artist);
    base.putIfAbsent('albumName', () => song.album?.name ?? '');
    base.putIfAbsent('albumId', () => song.album?.id ?? '');
    base.putIfAbsent('interval',
        () => song.duration?.inSeconds.toString() ?? '00:00');
    base.putIfAbsent('source', () => song.sourceId);
    return base;
  }

  Future<void> dispose() => _runtime.dispose();
}

/// 解析脚本头部注释的 @name / @version / @author。
class LxManifestParser {
  static ({String name, String version, String author}) parse(String script) {
    String name = '未命名源';
    String version = '';
    String author = '';
    final head = script.length > 4000 ? script.substring(0, 4000) : script;
    for (final line in head.split('\n')) {
      final nameM = RegExp(r'@name\s+(.+)').firstMatch(line);
      final verM = RegExp(r'@version\s+(.+)').firstMatch(line);
      final authorM = RegExp(r'@author\s+(.+)').firstMatch(line);
      if (nameM != null) name = nameM.group(1)!.trim();
      if (verM != null) version = verM.group(1)!.trim();
      if (authorM != null) author = authorM.group(1)!.trim();
    }
    return (name: name, version: version, author: author);
  }
}

/// 宽容解析脚本返回的歌曲列表：兼容 lx 生态常见字段名
/// （songmid/musicId/id、name/title、singer/artist、albumName/album、interval/秒数）。
List<MusicInfo> parseScriptSongs(Object? result, {required String sourceId}) {
  final List list = result is List
      ? result
      : (result is Map ? ((result)['songs'] as List?) ?? const [] : const []);
  final out = <MusicInfo>[];
  for (final item in list) {
    if (item is! Map) continue;
    final m = item.cast<Object?, Object?>();
    final songmid = '${m['songmid'] ?? m['musicId'] ?? m['id'] ?? ''}';
    if (songmid.isEmpty) continue;
    final title = '${m['name'] ?? m['title'] ?? m['songName'] ?? '未知标题'}';
    final artist = '${m['singer'] ?? m['artist'] ?? '未知歌手'}';
    final albumName = m['albumName'] ?? m['album'];
    Duration? duration;
    final interval = m['interval'];
    final secs = interval is int ? interval : int.tryParse('$interval');
    if (secs != null && secs > 0) duration = Duration(seconds: secs);
    out.add(MusicInfo(
      sourceId: sourceId,
      musicId: songmid,
      title: title,
      artist: artist,
      album: albumName == null ? null : Album(name: '$albumName', id: ''),
      duration: duration,
      // 原样保留音源返回对象：MusicFree 插件取链需要 play_path_64/
      // qualitys/musicId 等私有字段，通用模型装不下
      raw: m,
    ));
  }
  return out;
}
