import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../../app_providers.dart';
import '../../core/services/playlists.dart';
import '../../core/ui/cover_image.dart';
import '../../player/player_core.dart';
import '../player/player_page.dart';
import 'playlist_pages.dart';

/// 本地曲库排序维度（对齐参考工程 lx 的 MusicSortModal / 栖弦 SongSortMode）。
enum SongSort { title, artist, album, duration, added }

extension on SongSort {
  String get label => switch (this) {
        SongSort.title => '歌曲名',
        SongSort.artist => '歌手',
        SongSort.album => '专辑',
        SongSort.duration => '时长',
        SongSort.added => '添加时间',
      };

  IconData get icon => switch (this) {
        SongSort.title => Icons.sort_by_alpha,
        SongSort.artist => Icons.person_outline,
        SongSort.album => Icons.album_outlined,
        SongSort.duration => Icons.timer_outlined,
        SongSort.added => Icons.schedule,
      };
}

/// 曲库：我收藏的东西。三个 Tab 分层展示，避免三个列表堆在一屏里。
///
///   · 歌单 —— 我的歌单（可删除/移动/文件夹分组）
///   · 最近 —— 最近播放（横向卡片改为纵向列表，更好点）
///   · 本机 —— 本机歌曲（搜索/排序/批量/删除）

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage>
    with SingleTickerProviderStateMixin {
  final _audioQuery = OnAudioQuery();

  late final TabController _tabs =
      TabController(length: 3, vsync: this);
  List<SongModel>? _songs;
  String? _error;

  /// albumId → 封面字节缓存（queryArtwork 是平台调用，必须缓存）。
  final Map<int, Uint8List?> _artCache = {};

  // —— 搜索 ——
  bool _searchMode = false;
  String _query = '';
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  // —— 排序（持久化）——
  SongSort _sort = SongSort.title;
  bool _ascending = true;

  // —— 批量选择 ——
  bool _batchMode = false;
  final Set<int> _selected = {};

  /// 用户从曲库移除的本机歌曲 id（只影响展示，不删文件）。
  final Set<int> _hiddenSongs = {};

  @override
  void initState() {
    super.initState();
    _restoreSortPrefs();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _restoreSortPrefs() async {
    final s = ref.read(appSettingsProvider);
    final sortName = s.songSort;
    final asc = s.songSortAscending;
    if (mounted) {
      setState(() {
        _sort = SongSort.values.firstWhere((v) => v.name == sortName,
            orElse: () => SongSort.title);
        _ascending = asc;
      });
    }
  }

  Future<void> _persistSort() =>
      ref.read(appSettingsProvider).setSongSort(_sort.name, _ascending);

  Future<void> _load() async {
    try {
      final ok = await _audioQuery.checkAndRequest();
      if (!ok) {
        if (!mounted) return;
        setState(() => _error = '需要「音乐和音频」权限才能扫描本地曲库');
        return;
      }
      final songs = await _audioQuery.querySongs();
      if (!mounted) return;
      setState(() {
        _songs = songs;
        _error = null;
      });
      _loadArtwork(songs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '扫描失败: $e');
    }
  }

  /// 按 albumId 批量取专辑封面（同一专辑只取一次）。
  Future<void> _loadArtwork(List<SongModel> songs) async {
    final ids = <int>{
      for (final s in songs)
        if ((s.albumId ?? 0) > 0) s.albumId!,
    };
    for (final id in ids) {
      if (_artCache.containsKey(id)) continue;
      _artCache[id] = null; // 占位，避免并发重复请求
      try {
        final bytes = await _audioQuery.queryArtwork(
          id,
          ArtworkType.ALBUM,
          size: 300,
          format: ArtworkFormat.JPEG,
        );
        if (!mounted) return;
        setState(() => _artCache[id] = bytes);
      } catch (_) {
        // 无封面属正常，保持 null（走渐变占位）
      }
    }
  }

  Uint8List? _artOf(SongModel s) {
    final id = s.albumId ?? 0;
    return id > 0 ? _artCache[id] : null;
  }

  /// 搜索 + 排序后的可见列表（先按目录白名单过滤）。
  List<SongModel> get _visible {
    final all = _songs ?? const <SongModel>[];
    final dirs = ref.read(appSettingsProvider).localMusicDirs;
    var list = (_hiddenSongs.isEmpty
        ? all
        : [
            for (final s in all)
              if (!_hiddenSongs.contains(s.id)) s,
          ])
        .where((s) =>
            dirs.isEmpty || dirs.any((d) => s.data.startsWith(d)))
        .toList();
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = [
        for (final s in all)
          if (s.title.toLowerCase().contains(q) ||
              (s.artist ?? '').toLowerCase().contains(q) ||
              (s.album ?? '').toLowerCase().contains(q))
            s,
      ];
    }
    final sorted = [...list];
    int cmp(SongModel a, SongModel b) => switch (_sort) {
          SongSort.title =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          SongSort.artist =>
            (a.artist ?? '').toLowerCase().compareTo((b.artist ?? '').toLowerCase()),
          SongSort.album =>
            (a.album ?? '').toLowerCase().compareTo((b.album ?? '').toLowerCase()),
          SongSort.duration =>
            (a.duration ?? 0).compareTo(b.duration ?? 0),
          SongSort.added => (a.dateAdded ?? 0).compareTo(b.dateAdded ?? 0),
        };
    sorted.sort(_ascending ? cmp : (a, b) => cmp(b, a));
    return sorted;
  }

  /// 转成歌单条目（不含 resolvedUrl：歌单按 sourceId+musicId 走取链）。
  PlaylistEntry _toEntry(SongModel s) => PlaylistEntry(
        sourceId: 'local',
        musicId: '${s.id}',
        title: s.title,
        artist: s.artist ?? '未知歌手',
        album: s.album,
        durationMs: s.duration ?? 0,
        resolvedPath: s.data.isEmpty ? null : 'file://${s.data}',
      );

  PlayerItem _toItem(SongModel s, {bool withUrl = true}) => PlayerItem(
        title: s.title,
        artist: s.artist ?? '未知歌手',
        sourceId: 'local',
        musicId: '${s.id}',
        resolvedUrl: withUrl ? 'file://${s.data}' : null,
        album: s.album,
        duration: Duration(milliseconds: s.duration ?? 0),
        artBytes: _artOf(s),
      );

  void _play(List<SongModel> songs, int index) {
    final items = [
      for (final s in songs)
        if (s.data.isNotEmpty) _toItem(s),
    ];
    if (items.isEmpty) return;
    ref.read(playerCoreProvider).setQueue(items, index: index);
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const PlayerPage()));
  }

  void _toggleSelect(int id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
      if (_selected.isEmpty) _batchMode = false;
    });
  }

  void _exitBatch() => setState(() {
        _batchMode = false;
        _selected.clear();
      });

  Future<void> _batchAddToPlaylist() async {
    final songs = [
      for (final s in _visible)
        if (_selected.contains(s.id)) s,
    ];
    if (songs.isEmpty) return;
    final playlists = ref.read(playlistsProvider);
    final target = await showModalBottomSheet<Playlist>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text('添加 ${songs.length} 首到歌单',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final p in playlists.sorted)
            ListTile(
              leading: Icon(
                  p.system ? Icons.star_outline : Icons.queue_music,
                  size: 20),
              title: Text(p.name),
              subtitle: Text('${p.entries.length} 首'),
              onTap: () => Navigator.of(context).pop(p),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (target == null) return;
    playlists.addEntries(target.id, [for (final s in songs) _toEntry(s)]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已添加 ${songs.length} 首到「${target.name}」'),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
    _exitBatch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _searchMode
            ? TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索歌曲 / 歌手 / 专辑',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _query = v),
              )
            : const Text('曲库'),
        actions: [
          if (_batchMode) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('已选 ${_selected.length}'),
              ),
            ),
            IconButton(
              tooltip: '添加到歌单',
              onPressed: _selected.isEmpty ? null : _batchAddToPlaylist,
              icon: const Icon(Icons.playlist_add),
            ),
            IconButton(
              tooltip: '取消',
              onPressed: _exitBatch,
              icon: const Icon(Icons.close),
            ),
          ] else ...[
            IconButton(
              tooltip: '搜索',
              onPressed: () {
                setState(() => _searchMode = !_searchMode);
                if (!_searchMode) {
                  _searchController.clear();
                  setState(() => _query = '');
                }
              },
              icon: Icon(_searchMode ? Icons.close : Icons.search),
            ),
            IconButton(
              tooltip: '排序',
              onPressed: _showSortSheet,
              icon: const Icon(Icons.sort),
            ),
            IconButton(
              tooltip: '扫描目录',
              onPressed: _showDirSheet,
              icon: const Icon(Icons.folder_open),
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  /// 扫描目录设置：只显示指定目录下的歌曲（参考栖弦 directory_picker_tile）。
  Future<void> _showDirSheet() async {
    final settings = ref.read(appSettingsProvider);
    final scheme = Theme.of(context).colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          final dirs = settings.localMusicDirs;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Text('扫描目录',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  if (dirs.isNotEmpty)
                    TextButton(
                      onPressed: () async {
                        await ref
                            .read(appSettingsProvider)
                            .setLocalMusicDirs(const []);
                        await _load();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      child: const Text('扫描全部', style: TextStyle(fontSize: 12)),
                    ),
                ]),
                const SizedBox(height: 4),
                Text(
                  dirs.isEmpty
                      ? '当前扫描全部目录'
                      : '当前只显示 ${dirs.length} 个目录下的歌曲',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                for (final d in dirs)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder, size: 18),
                    title: Text(
                      d.split('/').where((x) => x.isNotEmpty).lastOrNull ?? d,
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(d,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () async {
                        final next = [...dirs]..remove(d);
                        await ref
                            .read(appSettingsProvider)
                            .setLocalMusicDirs(next);
                        await _load();
                        if (context.mounted) setSheet(() {});
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () async {
                    // Android 上选目录：用 file_selector 的目录选择
                    final dir = await getDirectoryPath();
                    if (dir == null) return;
                    await ref
                        .read(appSettingsProvider)
                        .setLocalMusicDirs([...dirs, dir]);
                    await _load();
                    if (context.mounted) setSheet(() {});
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加目录'),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showSortSheet() async {
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text('歌曲排序',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final mode in SongSort.values)
              ListTile(
                leading: Icon(mode.icon, size: 21),
                title: Text(mode.label),
                selected: mode == _sort,
                selectedTileColor:
                    scheme.secondaryContainer.withValues(alpha: 0.6),
                trailing: mode == _sort
                    ? Icon(Icons.check_rounded, color: scheme.onSecondaryContainer)
                    : null,
                onTap: () {
                  setState(() => _sort = mode);
                  setSheet(() {});
                  _persistSort();
                },
              ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('升序')),
                      ButtonSegment(value: false, label: Text('降序')),
                    ],
                    selected: {_ascending},
                    onSelectionChanged: (v) {
                      setState(() => _ascending = v.first);
                      setSheet(() {});
                      _persistSort();
                    },
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  Widget _buildBody() {
    // 注意：不能在本机歌曲未就绪时**整页**转圈——
    // 那样歌单和最近播放也看不到（真机确认过：_songs==null 时
    // 连 Tab 都不渲染）。加载/错误状态只落在「本机」Tab 内部。
    final scheme = Theme.of(context).colorScheme;
    final visible = _visible;
    final core = ref.watch(playerCoreProvider);
    final current = core.current;

    return Column(children: [
      // 三个 Tab 分层：歌单 / 最近 / 本机
      // 之前把「歌单纵向列表 + 继续聆听横向卡片 + 本机歌曲纵向列表」
      // 全堆在一个滚动视图里，层级混乱且不好定位。
      TabBar(
        controller: _tabs,
        tabs: const [
          Tab(text: '歌单'),
          Tab(text: '最近'),
          Tab(text: '本机'),
        ],
        labelColor: Theme.of(context).colorScheme.primary,
        unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
        indicatorSize: TabBarIndicatorSize.label,
      ),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          children: [
            _buildPlaylistsTab(scheme),
            _buildRecentTab(scheme),
            _buildLocalTab(scheme, visible, current),
          ],
        ),
      ),
    ]);
  }

  /// 歌单 Tab：纵向列表（可删除 / 移动 / 文件夹分组）
  Widget _buildPlaylistsTab(ColorScheme scheme) {
    final playlists = ref.watch(playlistsProvider);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          PlaylistsStrip(),
          if (playlists.playlists.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('还没有歌单。新建一个，或从 lx/M3U 导入。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }

  /// 最近 Tab：纵向列表（比原来的横向卡片好点、信息更全）
  Widget _buildRecentTab(ColorScheme scheme) {
    final recent = ref.watch(playHistoryProvider).items;
    if (recent.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.history, size: 36, color: scheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('还没有播放记录',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: recent.length,
      itemBuilder: (context, i) {
        final h = recent[i];
        return ListTile(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: scheme.surfaceContainerHighest,
            ),
            child: Icon(Icons.music_note,
                size: 20, color: scheme.onSurfaceVariant),
          ),
          title: Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(h.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11)),
          trailing: IconButton(
            tooltip: '从记录中移除',
            icon: Icon(Icons.close, size: 16, color: scheme.outline),
            onPressed: () =>
                ref.read(playHistoryProvider).remove(h.sourceId, h.musicId),
          ),
          onTap: () {
            final items = [
              for (final x in recent)
                PlayerItem(
                  title: x.title,
                  artist: x.artist,
                  sourceId: x.sourceId,
                  musicId: x.musicId,
                  album: x.album,
                  artUri: (x.picUrl == null || x.picUrl!.isEmpty)
                      ? null
                      : Uri.tryParse(x.picUrl!),
                  duration: x.durationMs == null
                      ? null
                      : Duration(milliseconds: x.durationMs!),
                ),
            ];
            ref.read(playerCoreProvider).setQueue(items, index: i);
            Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PlayerPage()));
          },
        );
      },
    );
  }

  /// 本机 Tab：本机歌曲（搜索 / 排序 / 批量 / 删除）
  Widget _buildLocalTab(
      ColorScheme scheme, List<SongModel> visible, PlayerItem? current) {
    // 本机专属状态：扫描中 / 权限或扫描失败 / 空列表
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.folder_off_outlined,
                size: 36, color: scheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试扫描'),
            ),
          ]),
        ),
      );
    }
    if (_songs == null) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('正在扫描本机音乐…', style: TextStyle(fontSize: 12)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: visible.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(children: [
                Text(
                  _query.isNotEmpty
                      ? '搜索结果（${visible.length}）'
                      : '本机歌曲（${visible.length}）',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                Text('${_sort.label}${_ascending ? ' ↑' : ' ↓'}',
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
              ]),
            );
          }
          final s = visible[i - 1];
          final playing =
              current?.sourceId == 'local' && current?.musicId == '${s.id}';
          final selected = _selected.contains(s.id);

          return Dismissible(
            key: ValueKey('song_${s.id}'),
            direction: _batchMode
                ? DismissDirection.none
                : DismissDirection.endToStart,
            background: Container(
              color: scheme.errorContainer,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
            ),
            // 从曲库隐藏（不删物理文件），二次确认
            confirmDismiss: (_) => _confirmHideSong(s),
            child: ListTile(
              selected: selected,
              selectedTileColor:
                  scheme.secondaryContainer.withValues(alpha: 0.5),
              leading: _batchMode
                  ? Checkbox(
                      value: selected,
                      onChanged: (_) => _toggleSelect(s.id),
                    )
                  : CoverImage(bytes: _artOf(s), size: 44, radius: 6),
              title: Row(children: [
                if (playing) ...[
                  Icon(Icons.graphic_eq, size: 14, color: scheme.primary),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: playing
                          ? TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600)
                          : null),
                ),
              ]),
              subtitle: Text(
                  '${s.artist ?? '未知歌手'} · ${_fmt(Duration(milliseconds: s.duration ?? 0))}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              trailing: _batchMode
                  ? null
                  : IconButton(
                      icon: Icon(Icons.play_circle_outline,
                          size: 22, color: scheme.primary),
                      tooltip: '播放',
                      onPressed: () {
                        if (s.data.isEmpty) return;
                        _play(visible, i - 1);
                      },
                    ),
              onTap: () {
                if (_batchMode) {
                  _toggleSelect(s.id);
                } else if (s.data.isNotEmpty) {
                  _play(visible, i - 1);
                }
              },
              onLongPress: () {
                setState(() {
                  _batchMode = true;
                  _selected.add(s.id);
                });
              },
            ),
          );
        },
      ),
    );
  }

  /// 从曲库隐藏一首本机歌曲（不删物理文件），二次确认。
  Future<bool> _confirmHideSong(SongModel s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从曲库移除？'),
        content: Text('「${s.title}」将不再显示在曲库中（不会删除手机里的文件）。\n'
            '如需彻底删除，请在系统文件管理器中操作。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('移除')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _hiddenSongs.add(s.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('已从曲库移除'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return true;
    }
    return false;
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$sec';
  }
}


