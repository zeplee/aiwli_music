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
  });

  factory PlaylistEntry.fromJson(Map<Object?, Object?> m) => PlaylistEntry(
        sourceId: '${m['sourceId'] ?? ''}',
        musicId: '${m['musicId'] ?? ''}',
        title: '${m['title'] ?? ''}',
        artist: '${m['artist'] ?? ''}',
        album: m['album'] as String?,
        durationMs: (m['durationMs'] as num?)?.toInt(),
        resolvedPath: m['resolvedPath'] as String?,
      );

  final String sourceId;
  final String musicId;
  final String title;
  final String artist;
  final String? album;
  final int? durationMs;
  final String? resolvedPath;

  Map<String, Object?> toJson() => {
        'sourceId': sourceId,
        'musicId': musicId,
        'title': title,
        'artist': artist,
        if (album != null) 'album': album,
        if (durationMs != null) 'durationMs': durationMs,
        if (resolvedPath != null) 'resolvedPath': resolvedPath,
      };
}

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.createdAtMs,
    this.entries = const [],
  });
  final String id;
  final String name;
  final int createdAtMs;
  final List<PlaylistEntry> entries;

  Playlist copyWith({String? name, List<PlaylistEntry>? entries}) => Playlist(
        id: id,
        name: name ?? this.name,
        createdAtMs: createdAtMs,
        entries: entries ?? this.entries,
      );

  factory Playlist.fromJson(Map<Object?, Object?> m) => Playlist(
        id: '${m['id'] ?? ''}',
        name: '${m['name'] ?? ''}',
        createdAtMs: (m['createdAtMs'] as num?)?.toInt() ?? 0,
        entries: ((m['entries'] as List?) ?? const [])
            .map((e) => PlaylistEntry.fromJson(e as Map))
            .toList(),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'createdAtMs': createdAtMs,
        'entries': entries.map((e) => e.toJson()).toList(),
      };
}

/// 本地歌单：新建 / 重命名 / 删除 / 增删条目 / 排序 / M3U 导入。
class PlaylistService extends SafeNotifier {
  PlaylistService(this._store);
  final SettingsStore _store;

  static const _file = 'playlists.json';
  List<Playlist> playlists = [];

  Future<void> load() async {
    final m = await _store.load(_file);
    playlists = ((m['playlists'] as List?) ?? const [])
        .map((e) => Playlist.fromJson(e as Map))
        .toList();
    notifyListeners();
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
    playlists = playlists.where((p) => p.id != id).toList();
    unawaitedPersist();
  }

  void rename(String id, String name) {
    playlists = [
      for (final p in playlists)
        if (p.id == id) p.copyWith(name: name.trim()) else p
    ];
    unawaitedPersist();
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
