import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../../core/services/playlists.dart';
import '../../player/models.dart';
import '../../player/player_core.dart';
import '../../core/ui/cover_image.dart';
import '../../app_providers.dart';
import '../player/player_page.dart';
import 'playlist_pages.dart';

final _audioQuery = OnAudioQuery();

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  List<SongModel>? _songs;

  /// albumId → 封面字节缓存。queryArtwork 是平台调用，
  /// 必须缓存，否则列表滚动会反复解码。
  final Map<int, Uint8List?> _artCache = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

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
      setState(() => _songs = songs);
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

  void _play(List<PlayerItem> items, int index) {
    ref.read(playerCoreProvider).setQueue(items, index: index);
    Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const PlayerPage()));
  }

  @override
  Widget build(BuildContext context) {
    final core = ref.watch(playerCoreProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Aiwli Music')),
      body: _buildBody(),
      bottomNavigationBar: ValueListenableBuilder<PlayerUiState>(
        valueListenable: core.state,
        builder: (context, s, _) {
          if (s.title.isEmpty) return const SizedBox.shrink();
          return SafeArea(
            child: ListTile(
              tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                  '${s.artist} · ${_fmt(s.position)} / ${_fmt(s.duration ?? Duration.zero)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    onPressed: () =>
                        s.playing ? core.pause() : core.play(),
                    icon: Icon(s.playing ? Icons.pause : Icons.play_arrow)),
                IconButton(
                    onPressed: core.next,
                    icon: const Icon(Icons.skip_next)),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('重试')),
        ]),
      );
    }
    if (_songs == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final songs = _songs!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: PlaylistsStrip(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('本机歌曲（${songs.length}）',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ),
        if (songs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('本机没有扫描到音频文件。把 mp3/flac 放进「音乐」目录后下拉重试。'),
          ),
        for (var i = 0; i < songs.length; i++)
          ListTile(
            leading: CoverImage(
              bytes: _artOf(songs[i]),
              size: 44,
              radius: 6,
            ),
            title: Text(songs[i].title,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
                '${songs[i].artist} · ${_fmt(Duration(milliseconds: songs[i].duration ?? 0))}',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () {
              final path = songs[i].data;
              if (path.isEmpty) return;
              final items = [
                for (var j = 0; j < songs.length; j++)
                  PlayerItem(
                    title: songs[j].title,
                    artist: songs[j].artist ?? '未知歌手',
                    sourceId: 'local',
                    musicId: '${songs[j].id}',
                    resolvedUrl: 'file://${songs[j].data}',
                    duration: Duration(milliseconds: songs[j].duration ?? 0),
                    artBytes: _artOf(songs[j]),
                  ),
              ];
              _play(items, i);
            },
            trailing: IconButton(
              icon: Icon(Icons.play_circle_outline,
                  size: 22, color: Theme.of(context).colorScheme.primary),
              tooltip: '播放',
              onPressed: () {
                final path = songs[i].data;
                if (path.isEmpty) return;
                _play([
                  PlayerItem(
                    title: songs[i].title,
                    artist: songs[i].artist ?? '未知歌手',
                    sourceId: 'local',
                    musicId: '${songs[i].id}',
                    resolvedUrl: 'file://${songs[i].data}',
                    artBytes: _artOf(songs[i]),
                    duration:
                        Duration(milliseconds: songs[i].duration ?? 0),
                  ),
                ], 0);
              },
            ),
            onLongPress: () => showAddToPlaylistSheet(
              context,
              ref,
              PlaylistEntry(
                sourceId: 'local',
                musicId: '${songs[i].id}',
                title: songs[i].title,
                artist: songs[i].artist ?? '未知歌手',
                durationMs: songs[i].duration,
                resolvedPath: 'file://${songs[i].data}',
              ),
            ),
          ),
        const SizedBox(height: 8),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }
}

