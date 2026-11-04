import 'dart:convert';

import '../storage/settings_store.dart';
import 'safe_notifier.dart';

/// 歌单条目。resolvedPath 非空时直接播放（本地文件 / 直链 URL），
/// 否则按 sourceId+musicId 走脚本取链。
class PlaylistEntry {
  const PlaylistEntry({
    required this.sourceId,
    required this.musicId,
    required this.title,
    required this.artist,
    this.album,
    this.durationMs,
    this.resolvedPath,
    this.rawJson,
    this.picUrl,
  });

  factory PlaylistEntry.fromJson(Map<Object?, Object?> m) => PlaylistEntry(
        sourceId: m['sourceId']?.toString() ?? '',
        musicId: m['musicId']?.toString() ?? '',
        title: m['title']?.toString() ?? '未知标题',
        artist: m['artist']?.toString() ?? '未知歌手',
        album: m['album'] as String?,
        picUrl: m['picUrl'] as String?,
        durationMs: (m['durationMs'] as num?)?.toInt(),
        resolvedPath: m['resolvedPath'] as String?,
        rawJson: m['rawJson'] as String?,
      );

  /// 音源返回的原始对象（JSON 序列化存储）。
  /// kg 等平台取链需要 FileHash，通用字段装不下——丢失即无法播放。
  final String? rawJson;

  Map<Object?, Object?>? get raw {
    final j = rawJson;
    if (j == null || j.isEmpty) return null;
    try {
      return jsonDecode(j) as Map<Object?, Object?>;
    } catch (_) {
      return null;
    }
  }

  final String sourceId;
  final String musicId;
  final String title;
  final String artist;
  final String? album;

  /// 封面 URL（各平台 CDN 直链）。歌单列表/收藏区块展示用。
  final String? picUrl;
  final int? durationMs;
  final String? resolvedPath;

  Map<String, Object?> toJson() => {
        'sourceId': sourceId,
        'musicId': musicId,
        'title': title,
        'artist': artist,
        if (album != null) 'album': album,
        if (picUrl != null) 'picUrl': picUrl,
        if (durationMs != null) 'durationMs': durationMs,
        if (resolvedPath != null) 'resolvedPath': resolvedPath,
        if (rawJson != null) 'rawJson': rawJson,
      };
}

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.createdAtMs,
    this.entries = const [],
    this.system = false,
  });
  final String id;
  final String name;
  final int createdAtMs;
  final List<PlaylistEntry> entries;

  /// 系统歌单：自动创建、置顶、不可删除/改名。
  /// 目前只有「我的收藏」一个（取代原先独立的 favorites 存储）。
  final bool system;

  Playlist copyWith({String? name, List<PlaylistEntry>? entries}) => Playlist(
        id: id,
        name: name ?? this.name,
        createdAtMs: createdAtMs,
        entries: entries ?? this.entries,
        system: system,
      );

  factory Playlist.fromJson(Map<Object?, Object?> m) => Playlist(
        id: '${m['id'] ?? ''}',
        name: '${m['name'] ?? ''}',
        createdAtMs: (m['createdAtMs'] as num?)?.toInt() ?? 0,
        system: m['system'] == true,
        entries: ((m['entries'] as List?) ?? const [])
            .map((e) => PlaylistEntry.fromJson(e as Map))
            .toList(),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'createdAtMs': createdAtMs,
          'entries': entries.map((e) => e.toJson()).toList(),
        if (system) 'system': true,
      };
}

/// 本地歌单：新建 / 重命名 / 删除 / 增删条目 / 排序 / M3U 导入。
class PlaylistService extends SafeNotifier {
  PlaylistService(this._store);
  final SettingsStore _store;

  static const _file = 'playlists.json';

  /// 「我的收藏」系统歌单 id（取代原先独立的 favorites.json）。
  static const favoritesId = 'sys_favorites';

  List<Playlist> playlists = [];

  /// 系统歌单永远排在最前，其余按创建时间。
  List<Playlist> get sorted => [
        for (final p in playlists)
          if (p.system) p,
        for (final p in playlists)
          if (!p.system) p,
      ];

  Playlist? get favorites =>
      playlists.where((p) => p.id == favoritesId).firstOrNull;

  Future<void> load() async {
    final m = await _store.load(_file);
    playlists = ((m['playlists'] as List?) ?? const [])
        .map((e) => Playlist.fromJson(e as Map))
        .toList();
    _ensureSystemPlaylists();
    notifyListeners();
  }

  /// 保证「我的收藏」存在（老用户升级后自动补建）。
  void _ensureSystemPlaylists() {
    if (playlists.any((p) => p.id == favoritesId)) return;
    playlists = [
      Playlist(
        id: favoritesId,
        name: '我的收藏',
        createdAtMs: 0,
        system: true,
      ),
      ...playlists,
    ];
    unawaitedPersist();
  }

  Future<void> _persist() async {
    await _store.flush(_file, {
      'playlists': playlists.map((p) => p.toJson()).toList(),
    });
  }

  Playlist create(String name) {
    final p = Playlist(
      id: 'pl_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? '新建歌单' : name.trim(),
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    playlists = [...playlists, p];
    unawaitedPersist();
    return p;
  }

  void delete(String id) {
    // 系统歌单不可删除（收藏入口常驻）
    if (playlists.any((p) => p.id == id && p.system)) return;
    playlists = playlists.where((p) => p.id != id).toList();
    unawaitedPersist();
  }

  void rename(String id, String name) {
    if (playlists.any((p) => p.id == id && p.system)) return;
    playlists = [
      for (final p in playlists)
        if (p.id == id) p.copyWith(name: name.trim()) else p
    ];
    unawaitedPersist();
  }

  /// 收藏：有则移出，无则加入「我的收藏」。返回操作后是否在收藏中。
  bool toggleFavorite(PlaylistEntry entry) {
    final fav = favorites;
    final key = '${entry.sourceId}/${entry.musicId}';
    final existing = fav?.entries
            .indexWhere((e) => '${e.sourceId}/${e.musicId}' == key) ??
        -1;
    if (existing >= 0) {
      removeEntry(favoritesId, existing);
      return false;
    }
    addEntries(favoritesId, [entry]);
    return true;
  }

  bool isFavorite(String sourceId, String musicId) {
    final key = '$sourceId/$musicId';
    return favorites?.entries
            .any((e) => '${e.sourceId}/${e.musicId}' == key) ??
        false;
  }

  /// 把旧 favorites.json 的条目一次性并入「我的收藏」（迁移用，按 key 去重）。
  Future<int> mergeIntoFavorites(List<PlaylistEntry> entries) async {
    final fav = favorites;
    if (fav == null) return 0;
    final existing = {
      for (final e in fav.entries) '${e.sourceId}/${e.musicId}',
    };
    final fresh = [
      for (final e in entries)
        if (existing.add('${e.sourceId}/${e.musicId}')) e,
    ];
    if (fresh.isEmpty) return 0;
    addEntries(favoritesId, fresh);
    return fresh.length;
  }

  void addEntries(String id, List<PlaylistEntry> entries) {
    playlists = [
      for (final p in playlists)
        if (p.id == id)
          p.copyWith(entries: [...p.entries, ...entries])
        else
          p
    ];
    unawaitedPersist();
  }

  void removeEntry(String id, int index) {
    playlists = [
      for (final p in playlists)
        if (p.id == id)
          p.copyWith(
              entries: [...p.entries]..removeAt(index.clamp(0, p.entries.length - 1)))
        else
          p
    ];
    unawaitedPersist();
  }

  /// 替换指定条目（自动匹配用）。
  void replaceEntry(String id, int index, PlaylistEntry entry) {
    playlists = [
      for (final p in playlists)
        if (p.id == id && index < p.entries.length)
          p.copyWith(entries: [...p.entries]..[index] = entry)
        else
          p
    ];
    unawaitedPersist();
  }

  void move(String id, int from, int to) {
    playlists = [
      for (final p in playlists)
        if (p.id == id) p.copyWith(entries: _reordered(p.entries, from, to)) else p
    ];
    unawaitedPersist();
  }

  static List<PlaylistEntry> _reordered(List<PlaylistEntry> src, int from, int to) {
    final list = [...src];
    final e = list.removeAt(from.clamp(0, list.length - 1));
    list.insert(to.clamp(0, list.length), e);
    return list;
  }

  /// M3U/M3U8 解析。支持 #EXTINF 头（时长/歌手 - 标题）与本地路径/URL。
  /// 返回导入条数（新建歌单在 [newName] 中返回）。
  Playlist? importM3u(String name, String content) {
    final entries = <PlaylistEntry>[];
    String? artist;
    String? title;
    int? durationMs;
    for (final raw in content.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXTINF:')) {
        final body = line.substring(8);
        final comma = body.indexOf(',');
        final sec =
            comma > 0 ? int.tryParse(body.substring(0, comma).trim()) : null;
        durationMs = sec != null && sec > 0 ? sec * 1000 : null;
        final meta = comma > 0 ? body.substring(comma + 1).trim() : '';
        final dash = meta.indexOf(' - ');
        if (dash > 0) {
          artist = meta.substring(0, dash).trim();
          title = meta.substring(dash + 3).trim();
        } else {
          artist = null;
          title = meta.isEmpty ? null : meta;
        }
        continue;
      }
      if (line.startsWith('#')) continue;
      final isUrl = line.startsWith('http://') || line.startsWith('https://');
      final fileName = line.split(RegExp(r'[\\/]')).last;
      final cleanTitle = (title ?? fileName).replaceAll(RegExp(r'\.[a-zA-Z0-9]{2,4}$'), '');
      entries.add(PlaylistEntry(
        sourceId: isUrl ? 'url' : 'local',
        musicId: line,
        title: cleanTitle,
        artist: artist ?? '未知歌手',
        durationMs: durationMs != null ? durationMs * 1000 : null,
        resolvedPath: line,
      ));
      artist = null;
      title = null;
      durationMs = null;
    }
    if (entries.isEmpty) return null;
    final p = create(name);
    addEntries(p.id, entries);
    return playlists.firstWhere((e) => e.id == p.id);
  }

  void unawaitedPersist() {
    // 不 await：UI 立即反馈，持久化异步落盘
    _persist();
  }
}
