import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../../player/models.dart';
import '../../player/player_core.dart';
import '../../app_providers.dart';
import '../player/player_page.dart';

final _audioQuery = OnAudioQuery();

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  List<SongModel>? _songs;
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '扫描失败: $e');
    }
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
            leading: const _ArtTile(icon: Icons.music_note),
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
                  ),
              ];
              _play(items, i);
            },
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

class _ArtTile extends StatelessWidget {
  const _ArtTile({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5B8DEF), Color(0xFF8B5CF6)],
        ),
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}
