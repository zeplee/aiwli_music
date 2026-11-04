import 'dart:convert';

import '../storage/settings_store.dart';
import 'logger.dart';
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

/// copyWith 用哨兵区分「参数未传」与「显式置为 null」。
const Object _unset = Object();

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.createdAtMs,
    this.entries = const [],
    this.system = false,
    this.folder,
  });
  final String id;
  final String name;
  final int createdAtMs;
  final List<PlaylistEntry> entries;

  /// 系统歌单：自动创建、置顶、不可删除/改名。
  /// 目前只有「我的收藏」一个（取代原先独立的 favorites 存储）。
  final bool system;

  /// 所属文件夹名（null = 未分组，直接显示在顶层）。
  /// 用途：按人/场景分组，例如「李泽鹏」文件夹下放他的收藏与歌单。
  final String? folder;

  Playlist copyWith({
    String? name,
    List<PlaylistEntry>? entries,
    Object? folder = _unset,
  }) =>
      Playlist(
        id: id,
        name: name ?? this.name,
        createdAtMs: createdAtMs,
        entries: entries ?? this.entries,
        system: system,
        // 用哨兵区分「不改」与「置空」
        folder: identical(folder, _unset) ? this.folder : folder as String?,
      );

  factory Playlist.fromJson(Map<Object?, Object?> m) => Playlist(
        id: '${m['id'] ?? ''}',
        name: '${m['name'] ?? ''}',
        createdAtMs: (m['createdAtMs'] as num?)?.toInt() ?? 0,
        system: m['system'] == true,
        folder: m['folder'] as String?,
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
        if (folder != null) 'folder': folder,
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

  /// 兼容旧数据的全局收藏（无文件夹归属）。
  Playlist? get favorites =>
      playlists.where((p) => p.id == favoritesId).firstOrNull;

  /// 某人（某文件夹）自己的「我的收藏」歌单。
  ///
  /// 多用户共用场景：每人一个文件夹，文件夹内各有一份「我的收藏」，
  /// 收藏按钮操作的是"当前文件夹"的那一份。
  Playlist? favoritesIn(String? folder) => playlists
      .where((p) =>
          p.name == '我的收藏' &&
          (folder == null ? p.folder == null : p.folder == folder))
      .firstOrNull;

  /// 把已有歌单升级为某个文件夹的「我的收藏」：
  /// 改名为「我的收藏」、标记 system、归入该文件夹。
  /// 用于「人名歌单 → 该人的收藏」这种迁移。
  void markAsSystem(String id, {String? folder}) {
    playlists = [
      for (final p in playlists)
        if (p.id == id)
          Playlist(
            id: p.id,
            name: '我的收藏',
            createdAtMs: p.createdAtMs,
            entries: p.entries,
            system: true,
            folder: folder ?? p.folder,
          )
        else
          p
    ];
    unawaitedPersist();
  }

  /// 为指定文件夹创建其专属「我的收藏」（幂等）。
  Playlist ensureFavoritesIn(String? folder) {
    final existing = favoritesIn(folder);
    if (existing != null) return existing;
    final p = Playlist(
      id: folder == null
          ? favoritesId
          : 'fav_${folder.hashCode.toRadixString(16)}_${DateTime.now().microsecondsSinceEpoch}',
      name: '我的收藏',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      system: true,
      folder: folder,
    );
    playlists = [...playlists, p];
    unawaitedPersist();
    return p;
  }

  Future<void> load() async {
    final m = await _store.load(_file);
    playlists = ((m['playlists'] as List?) ?? const [])
        .map((e) => Playlist.fromJson(e as Map))
        .toList();
    _ensureSystemPlaylists();
    notifyListeners();
  }

  /// 保证顶层「我的收藏」存在（老用户升级后自动补建）。
  ///
  /// 多用户共用场景：收藏可以分散在各文件夹里（每人一份）。
  /// 只要**任何地方**已存在「我的收藏」，就不再补建全局那份，
  /// 否则删掉的全局收藏会在下次启动时又冒出来占第一位。
  void _ensureSystemPlaylists() {
    // 任何位置（顶层或某文件夹）已有「我的收藏」→ 不再补建顶层那份。
    // 多用户场景的关键：删掉的顶层收藏不能在下次启动复活。
    if (playlists.any((p) => p.name == '我的收藏')) return;

    // 完全没有收藏 → 补一份顶层收藏，保证有收藏入口（新用户/老用户升级）。
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

  /// 收尾清理：已有某文件夹的收藏时，删除顶层全局收藏。
  ///
  /// 与 _ensureSystemPlaylists 配套：补建逻辑只在"完全没有收藏"时生效，
  /// 但迁移过程中会先补建再合并，所以必须再清一次。
  /// 幂等、每次 load 后调用都安全。
  void dropTopLevelFavoritesIfFoldered() {
    final folderedFavs = <Playlist>[
      for (final p in playlists)
        if (p.name == '我的收藏' && p.folder != null) p,
    ];
    if (folderedFavs.isEmpty) return;

    final topLevelFavs = <Playlist>[
      for (final p in playlists)
        if (p.name == '我的收藏' && p.folder == null) p,
    ];

    for (final g in topLevelFavs) {
      // 有内容先并入某个文件夹收藏，避免丢歌
      final movedCount = g.entries.length;
      if (movedCount > 0) {
        final target = folderedFavs.first;
        addEntries(target.id, g.entries);
        final t = byId(target.id);
        final allIn = t != null &&
            g.entries.every((e) => t.entries.any(
                (x) => x.sourceId == e.sourceId && x.musicId == e.musicId));
        if (!allIn) continue; // 没搬全就保留，不冒险
      }
      delete(g.id);
      AppLog.i('Migrate', '已清掉顶层收藏（$movedCount 首已转移到文件夹收藏）');
    }
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

  // ————————————————— 文件夹 —————————————————

  /// 所有文件夹名（去重、按首次出现顺序）。
  List<String> get folders {
    final seen = <String>[];
    for (final p in playlists) {
      final f = p.folder;
      if (f != null && f.trim().isNotEmpty && !seen.contains(f)) seen.add(f);
    }
    return seen;
  }

  /// 分组视图：folder -> 该文件夹下的歌单；null 键 = 顶层未分组。
  Map<String?, List<Playlist>> get grouped {
    final map = <String?, List<Playlist>>{};
    for (final p in sorted) {
      map.putIfAbsent(p.folder, () => []).add(p);
    }
    return map;
  }

  Playlist? byId(String id) =>
      playlists.where((p) => p.id == id).firstOrNull;

  void setFolder(String playlistId, String? folder) {
    final f = (folder == null || folder.trim().isEmpty) ? null : folder.trim();
    playlists = [
      for (final p in playlists)
        if (p.id == playlistId) p.copyWith(folder: f) else p
    ];
    unawaitedPersist();
  }

  /// 新建文件夹（空文件夹也要能存在，所以用一个占位歌单承载）。
  /// 已存在则忽略。
  String ensureFolder(String name) {
    final n = name.trim();
    if (n.isEmpty) return n;
    if (folders.contains(n)) return n;
    // 用空歌单占位：让 folders 能列出它，用户可后续往里放歌单
    final placeholder = Playlist(
      id: 'pl_${DateTime.now().microsecondsSinceEpoch}_holder',
      name: '（空文件夹）',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      folder: n,
    );
    playlists = [...playlists, placeholder];
    unawaitedPersist();
    return n;
  }

  /// 删除文件夹：其下歌单回到顶层（不删歌单本身）。
  void removeFolder(String name) {
    playlists = [
      for (final p in playlists)
        if (p.folder == name) p.copyWith(folder: null) else p
    ];
    // 顺带清掉空占位
    playlists = [
      for (final p in playlists)
        if (!(p.folder == null &&
            p.name == '（空文件夹）' &&
            p.entries.isEmpty))
          p
    ];
    unawaitedPersist();
  }

  /// 收藏：有则移出，无则加入「我的收藏」。返回操作后是否在收藏中。
  /// 收藏/取消收藏。[folder] 指定操作哪一份收藏（null = 顶层/全局收藏）。
  bool toggleFavorite(PlaylistEntry entry, {String? folder}) {
    final fav = favoritesIn(folder) ??
        // 该文件夹还没有收藏歌单时自动建一份
        ensureFavoritesIn(folder);
    final key = '${entry.sourceId}/${entry.musicId}';
    final existing =
        fav.entries.indexWhere((e) => '${e.sourceId}/${e.musicId}' == key);
    if (existing >= 0) {
      removeEntry(fav.id, existing);
      return false;
    }
    addEntries(fav.id, [entry]);
    return true;
  }

  /// 是否已收藏（任一文件夹的收藏里存在即视为已收藏，用于按钮状态）。
  bool isFavorite(String sourceId, String musicId, {String? folder}) {
    final key = '$sourceId/$musicId';
    if (folder != null) {
      return favoritesIn(folder)
              ?.entries
              .any((e) => '${e.sourceId}/${e.musicId}' == key) ??
          false;
    }
    // folder == null：检查所有收藏歌单（含各用户的）
    return playlists
        .where((p) => p.name == '我的收藏')
        .any((p) => p.entries.any((e) => '${e.sourceId}/${e.musicId}' == key));
  }

  /// 把旧 favorites.json 的条目一次性并入「我的收藏」（迁移用，按 key 去重）。
  Future<int> mergeIntoFavorites(List<PlaylistEntry> entries,
      {String? folder}) async {
    final fav = favoritesIn(folder);
    if (fav == null) return 0;
    final existing = {
      for (final e in fav.entries) '${e.sourceId}/${e.musicId}',
    };
    final fresh = [
      for (final e in entries)
        if (existing.add('${e.sourceId}/${e.musicId}')) e,
    ];
    if (fresh.isEmpty) return 0;
    addEntries(fav.id, fresh);
    return fresh.length;
  }

  void addEntries(String id, List<PlaylistEntry> entries) {
    playlists = [
      for (final p in playlists)
        if (p.id == id)
          p.copyWith(entries: _appendUnique(p.entries, entries))
        else
          p
    ];
    unawaitedPersist();
  }

  /// 追加条目并去重：同一 sourceId+musicId 视为同一首歌（真重复），
  /// 已存在则跳过，避免同一歌单里出现两条相同曲目。
  static List<PlaylistEntry> _appendUnique(
      List<PlaylistEntry> base, List<PlaylistEntry> add) {
    final seen = {for (final e in base) '${e.sourceId}/${e.musicId}'};
    final out = [...base];
    for (final e in add) {
      if (e.musicId.isEmpty) continue;
      if (seen.add('${e.sourceId}/${e.musicId}')) out.add(e);
    }
    return out;
  }

  /// 批量移除指定索引（一次写盘，避免 N 次 IO）。
  void removeEntries(String id, Set<int> indices) {
    if (indices.isEmpty) return;
    playlists = [
      for (final p in playlists)
        if (p.id == id)
          p.copyWith(entries: [
            for (var i = 0; i < p.entries.length; i++)
              if (!indices.contains(i)) p.entries[i],
          ])
        else
          p
    ];
    unawaitedPersist();
  }

  /// 批量移动到另一歌单：一次写盘，保证两端一致。
  /// 返回实际移动条数（目标已有同曲则跳过，不产生重复）。
  int moveEntries(String fromId, String toId, Set<int> indices) {
    if (indices.isEmpty || fromId == toId) return 0;
    final from = byId(fromId);
    final to = byId(toId);
    if (from == null || to == null) return 0;

    final moving = <PlaylistEntry>[
      for (var i = 0; i < from.entries.length; i++)
        if (indices.contains(i)) from.entries[i],
    ];
    if (moving.isEmpty) return 0;

    final merged = _appendUnique(to.entries, moving);
    final addedCount = merged.length - to.entries.length;

    playlists = [
      for (final p in playlists)
        if (p.id == fromId)
          p.copyWith(entries: [
            for (var i = 0; i < p.entries.length; i++)
              if (!indices.contains(i)) p.entries[i],
          ])
        else if (p.id == toId)
          p.copyWith(entries: merged)
        else
          p
    ];
    unawaitedPersist();
    return addedCount;
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
