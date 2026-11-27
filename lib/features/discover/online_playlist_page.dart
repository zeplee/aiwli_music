import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../app_providers.dart';
import '../../core/models/music.dart';
import '../../core/services/playlists.dart';
import '../../sources/builtin/catalog_sdk.dart';
import '../../../player/player_core.dart';
import '../player/player_page.dart';
import 'playlist_selection.dart';

/// 在线歌单详情。
///
/// 之前「精选歌单」的卡片是死的——点了没反应，用户不知道是没做好还是加载失败。
/// 这里补上展开：点进去看到真实曲目，可以整单播放或单曲播放。
///
/// 平台差异是真实存在的：只有网易提供免签名的歌单曲目接口，
/// 酷我需要额外签名。所以酷我进来会明确提示"暂不支持展开"，
/// 而不是转圈后一片空白。
class OnlinePlaylistPage extends ConsumerStatefulWidget {
  const OnlinePlaylistPage({
    required this.source,
    required this.playlistId,
    required this.title,
    this.coverUrl,
    super.key,
  });

  final String source;
  final String playlistId;
  final String title;
  final String? coverUrl;

  @override
  ConsumerState<OnlinePlaylistPage> createState() => _OnlinePlaylistPageState();
}

class _OnlinePlaylistPageState extends ConsumerState<OnlinePlaylistPage> {
  List<MusicInfo>? _songs;
  bool _loading = true;
  String _query = '';
  final PlaylistSelection _selection = PlaylistSelection();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final songs = await CatalogSdk.playlistSongs(
      source: widget.source,
      playlistId: widget.playlistId,
      limit: 200,
    );
    if (!mounted) return;
    setState(() {
      _songs = songs;
      _loading = false;
    });
  }

  bool _canPlay() => ref
      .read(sourceRegistryProvider)
      .enabledRuntimes
      .any((r) => r.actions.contains('musicUrl'));

  void _playAll(List<MusicInfo> songs, {int index = 0}) {
    if (songs.isEmpty) return;
    if (!_canPlay()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('还没有可用的音源脚本，无法取到播放地址'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    ref.read(playerCoreProvider).setQueue([
      for (final m in songs)
        PlayerItem(
          title: m.title,
          artist: m.artist,
          sourceId: m.sourceId,
          musicId: m.musicId,
          album: m.album?.name,
          artUri: (m.album?.picUrl == null || m.album!.picUrl!.isEmpty)
              ? null
              : Uri.tryParse(m.album!.picUrl!),
          duration: m.duration,
          raw: m.raw,
        ),
    ], index: index);
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const PlayerPage()));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = _songs ?? const <MusicInfo>[];
    final songs = filterPlaylistSongs(all, _query);

    return GlassScaffold(
      edgeToEdge: true,
      statusBarStyle: GlassStatusBarStyle.auto,
      extendBody: false,
      background: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                  scheme.primary.withValues(alpha: 0.20), scheme.surface),
              scheme.surface,
            ],
          ),
        ),
      ),
      appBar: GlassAppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : all.isEmpty
              ? _EmptyHint(source: widget.source, onRetry: _load)
              : Column(children: [
                  _headerCard(songs, all),
                  if (_selection.active) _batchBar(songs),
                  Expanded(
                    child: songs.isEmpty
                        ? const Center(child: Text('没有匹配的曲目'))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: songs.length,
                            itemBuilder: (context, i) {
                              final m = songs[i];
                              final selected =
                                  _selection.selected.contains(i);
                              return Row(children: [
                                if (_selection.active)
                                  Checkbox(
                                    value: selected,
                                    onChanged: (_) =>
                                        setState(() => _selection.toggle(i)),
                                  ),
                                Expanded(
                                  child: _SongRow(
                                    index: i + 1,
                                    song: m,
                                    onTap: _selection.active
                                        ? () =>
                                            setState(() => _selection.toggle(i))
                                        : () => _playAll(songs, index: i),
                                    onLongPress: () => setState(() {
                                      _selection.enter();
                                      _selection.toggle(i);
                                    }),
                                  ),
                                ),
                              ]);
                            },
                          ),
                  ),
                ]),
    );
  }

  Widget _headerCard(List<MusicInfo> songs, List<MusicInfo> all) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: GlassContainer(
        shape: const LiquidRoundedSuperellipse(borderRadius: 16),
        padding: const EdgeInsets.all(12),
        // GlassContainer 不是 Material 祖先，里面的 IconButton/FilledButton
        // 内部用 InkWell，不包一层会抛 No Material widget found。
        child: Material(
          type: MaterialType.transparency,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${songs.length} 首',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            IconButton(
              tooltip: '随机播放',
              icon: const Icon(Icons.shuffle, size: 18),
              onPressed: songs.isEmpty
                  ? null
                  : () {
                      final shuffled = [...songs]..shuffle(math.Random());
                      _playAll(shuffled);
                    },
            ),
            IconButton(
              tooltip: '收藏整张歌单到本地',
              icon: const Icon(Icons.favorite_border, size: 18),
              onPressed: all.isEmpty ? null : () => _collectAll(all),
            ),
            FilledButton.icon(
              onPressed: songs.isEmpty ? null : () => _playAll(songs),
              icon: const Icon(Icons.play_arrow, size: 20),
              label: const Text('播放全部'),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            onChanged: (v) => setState(() {
              _query = v;
              _selection.exit();
            }),
            decoration: const InputDecoration(
              hintText: '在歌单内搜索歌名 / 歌手',
              prefixIcon: Icon(Icons.search, size: 18),
              border: OutlineInputBorder(),
            ),
          ),
          ]),
        ),
      ),
    );
  }

  Widget _batchBar(List<MusicInfo> songs) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      child: Row(children: [
        IconButton(
          tooltip: '退出多选',
          icon: const Icon(Icons.close),
          onPressed: () => setState(() => _selection.exit()),
        ),
        Text('已选 ${_selection.count} 首',
            style: const TextStyle(fontSize: 12)),
        const Spacer(),
        TextButton(
          onPressed: () =>
              setState(() => _selection.selectAll(songs.length)),
          child: const Text('全选'),
        ),
        IconButton(
          tooltip: '播放选中',
          icon: const Icon(Icons.play_arrow),
          onPressed: _selection.isEmpty
              ? null
              : () {
                  final picked = [
                    for (final i in _selection.selected)
                      if (i < songs.length) songs[i],
                  ];
                  _playAll(picked);
                  setState(() => _selection.exit());
                },
        ),
        IconButton(
          tooltip: '批量下载',
          icon: const Icon(Icons.download_for_offline_outlined),
          onPressed: _selection.isEmpty
              ? null
              : () {
                  final manager = ref.read(downloadManagerProvider);
                  for (final i in _selection.selected) {
                    if (i < songs.length) {
                      unawaited(manager.start(_toItem(songs[i])));
                    }
                  }
                  setState(() => _selection.exit());
                },
        ),
        IconButton(
          tooltip: '加入歌单',
          icon: const Icon(Icons.playlist_add),
          onPressed: _selection.isEmpty
              ? null
              : () {
                  final entries = [
                    for (final i in _selection.selected)
                      if (i < songs.length) _toItem(songs[i]).toEntry(),
                  ];
                  _addToNewPlaylist(entries);
                },
        ),
      ]),
    );
  }

  PlayerItem _toItem(MusicInfo m) => PlayerItem(
        title: m.title,
        artist: m.artist,
        sourceId: m.sourceId,
        musicId: m.musicId,
        album: m.album?.name,
        artUri: (m.album?.picUrl == null || m.album!.picUrl!.isEmpty)
            ? null
            : Uri.tryParse(m.album!.picUrl!),
        duration: m.duration,
        raw: m.raw,
      );

  void _addToNewPlaylist(List<PlaylistEntry> entries) {
    if (entries.isEmpty) return;
    final svc = ref.read(playlistsProvider);
    final p = svc.create(widget.title);
    svc.addEntries(p.id, entries);
    setState(() => _selection.exit());
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已把 ${entries.length} 首加入新歌单')));
  }

  void _collectAll(List<MusicInfo> all) {
    _addToNewPlaylist([for (final m in all) _toItem(m).toEntry()]);
  }
}

/// 空态：区分"平台不支持展开"与"接口暂时没返回"，避免同一句废话。
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.source, required this.onRetry});
  final String source;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unsupported = source != 'wy';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: GlassContainer(
          shape: const LiquidRoundedSuperellipse(borderRadius: 18),
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(unsupported ? Icons.lock_outline : Icons.inbox_outlined,
                size: 30, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              unsupported ? '这个平台暂不支持展开歌单' : '这个歌单暂时没有曲目',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              unsupported
                  ? '目前只有网易云提供免签名的歌单曲目接口。'
                      '换到网易云分类，或直接在搜索里找歌。'
                  : '接口可能波动，稍后重试。',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (!unsupported) ...[
              const SizedBox(height: 14),
              OutlinedButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ]),
        ),
      ),
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({
    required this.index,
    required this.song,
    required this.onTap,
    this.onLongPress,
  });
  final int index;
  final MusicInfo song;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Row(children: [
            SizedBox(
              width: 26,
              child: Text('$index',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5)),
                  if (song.artist.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            Icon(Icons.play_arrow_rounded,
                size: 19, color: scheme.primary.withValues(alpha: 0.7)),
          ]),
        ),
      ),
    );
  }
}