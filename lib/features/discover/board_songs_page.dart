import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/models/music.dart';
import '../../../player/player_core.dart';
import '../player/player_page.dart';

/// 榜单详情页：榜单歌曲列表，点击即播（脚本取链）。
class BoardSongsPage extends ConsumerStatefulWidget {
  const BoardSongsPage({required this.bangId, required this.boardName, super.key});

  final String bangId;
  final String boardName;

  @override
  ConsumerState<BoardSongsPage> createState() => _BoardSongsPageState();
}

class _BoardSongsPageState extends ConsumerState<BoardSongsPage> {
  List<MusicInfo>? _songs;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final lx = ref.read(sourceRegistryProvider).activeRuntime;
      if (lx == null) throw Exception('未启用音源：请先在「我的 → 音源管理」导入并启用');
      final songs = await lx.boardSongsFromScript(widget.bangId) ??
          (throw Exception('当前音源不支持榜单（需脚本声明 boardSongs 能力）'));
      if (!mounted) return;
      setState(() => _songs = songs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '榜单加载失败: $e');
    }
  }

  void _playAll(List<MusicInfo> songs, int index) {
    final core = ref.read(playerCoreProvider);
    final items = [
      for (final m in songs)
        PlayerItem(
          title: m.title,
          artist: m.artist,
          sourceId: m.sourceId,
          musicId: m.musicId,
          duration: m.duration,
        ),
    ];
    core.setQueue(items, index: index);
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const PlayerPage()));
  }

  @override
  Widget build(BuildContext context) {
    final songs = _songs;
    return Scaffold(
      appBar: AppBar(title: Text(widget.boardName)),
      body: songs == null
          ? (_error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.error))),
                    FilledButton(onPressed: _load, child: const Text('重试')),
                  ]))
              : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: () async => _load(),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: songs.length,
                itemBuilder: (context, i) {
                  final m = songs[i];
                  return ListTile(
                    leading: SizedBox(
                      width: 28,
                      child: Text('${i + 1}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: i < 3
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                    ),
                    title: Text(m.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(m.artist,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(
                          Icons.download_for_offline_outlined),
                      tooltip: '下载',
                      onPressed: () async {
                        final messenger =
                            ScaffoldMessenger.of(context);
                        unawaited(ref
                            .read(downloadManagerProvider)
                            .start(PlayerItem(
                              title: m.title,
                              artist: m.artist,
                              sourceId: m.sourceId,
                              musicId: m.musicId,
                            )));
                        messenger.showSnackBar(SnackBar(
                            content: Text('已加入下载：${m.title}'),
                            duration: const Duration(seconds: 1)));
                      },
                    ),
                    onTap: () => _playAll(songs, i),
                  );
                },
              ),
            ),
    );
  }
}
