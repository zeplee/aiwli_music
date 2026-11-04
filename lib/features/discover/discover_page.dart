import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/ui/cover_image.dart';
import '../../../core/models/music.dart';
import '../../../player/player_core.dart';
import '../library/playlist_pages.dart';
import '../player/player_page.dart';
import 'board_songs_page.dart';

/// 发现页：顶部搜索 → 每日推荐 Hero → 排行榜横滑（脚本能力驱动）→
/// 今日热门（飙升榜）→ 继续聆听 → 快速播放 → 音源状态。
class DiscoverPage extends ConsumerWidget {
  const DiscoverPage({this.onOpenSearch, super.key});

  final VoidCallback? onOpenSearch;

  static const List<PlayerItem> _demo = [
    PlayerItem(
        title: 'Demo · C 和弦',
        artist: 'Aiwli 内置',
        sourceId: 'local',
        musicId: 'demo_c',
        album: 'Aiwli Demo',
        resolvedUrl: 'asset:///assets/audio/demo_c.wav',
        duration: Duration(seconds: 30)),
    PlayerItem(
        title: 'Demo · G 和弦',
        artist: 'Aiwli 内置',
        sourceId: 'local',
        musicId: 'demo_g',
        album: 'Aiwli Demo',
        resolvedUrl: 'asset:///assets/audio/demo_g.wav',
        duration: Duration(seconds: 30)),
    PlayerItem(
        title: 'Demo · Am 和弦',
        artist: 'Aiwli 内置',
        sourceId: 'local',
        musicId: 'demo_am',
        album: 'Aiwli Demo',
        resolvedUrl: 'asset:///assets/audio/demo_am.wav',
        duration: Duration(seconds: 30)),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final core = ref.watch(playerCoreProvider);
    final playlists = ref.watch(playlistsProvider).sorted;
    // 「继续聆听」用真实播放历史（之前只显示当前一首，形同虚设）
    final history = ref.watch(playHistoryProvider).items;
    final recent = [
      for (final h in history.take(10))
        PlayerItem(
          title: h.title,
          artist: h.artist,
          sourceId: h.sourceId,
          musicId: h.musicId,
          album: h.album,
          artUri: (h.picUrl == null || h.picUrl!.isEmpty)
              ? null
              : Uri.tryParse(h.picUrl!),
          duration:
              h.durationMs == null ? null : Duration(milliseconds: h.durationMs!),
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('发现')),
      body: ListView(children: [
        // —— 顶部搜索栏 ——
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: InkWell(
            key: const ValueKey('discover_search_bar'),
            borderRadius: BorderRadius.circular(12),
            onTap: onOpenSearch,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(Icons.search,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant),
                const SizedBox(width: 8),
                Text('搜索歌曲 / 歌手',
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant)),
              ]),
            ),
          ),
        ),
        // —— 每日推荐 Hero ——
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: _HeroCard(
            onPlay: () {
              core.setQueue(_demo, index: 0);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('已开始播放演示曲'),
                  duration: Duration(seconds: 1)));
            },
          ),
        ),
        // —— 排行榜（脚本驱动：导入的音源声明 boardList/boardSongs 才显示，零内置源）——
        if (ref.watch(sourceRegistryProvider).activeRuntime != null)
          FutureBuilder<List<MusicBoard>>(
            future: ref
                .read(sourceRegistryProvider)
                .activeRuntime!
                .boardListFromScript()
                .then((b) => b ?? const <MusicBoard>[]),
            builder: (context, snap) {
              final boards = snap.data;
              if (boards == null || boards.isEmpty) return const SizedBox.shrink();
              return Column(children: [
                const _SectionHeader('排行榜'),
                SizedBox(
                  height: 150,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: boards.length,
                    itemBuilder: (context, i) {
                      final board = boards[i];
                      final gradients = const [
                        [Color(0xFF5B8DEF), Color(0xFF8B5CF6)],
                        [Color(0xFFE57373), Color(0xFF8B5CF6)],
                        [Color(0xFF26A69A), Color(0xFF5B8DEF)],
                        [Color(0xFF8B5CF6), Color(0xFFE0A3C8)],
                      ];
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => BoardSongsPage(
                                bangId: board.id, boardName: board.name))),
                        child: Container(
                          width: 128,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: gradients[i % gradients.length],
                            ),
                          ),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Icon(Icons.trending_up, color: Colors.white),
                                Text(board.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold)),
                              ]),
                        ),
                      );
                    },
                  ),
                ),
                // —— 今日热门（脚本首榜 Top10）——
                const _SectionHeader('今日热门'),
                _HotSongsSection(
                    boardId: boards.first.id, boardName: boards.first.name),
              ]);
            },
          ),
        // —— 我的歌单 ——
        // 「收藏」概念已移除（对齐 lx / 栖弦：只有歌单）。这里展示歌单入口，
        // 系统歌单（原收藏）仍是其中之一，但不再用爱心图标表达。
        if (playlists.isNotEmpty) ...[
          const _SectionHeader('我的歌单'),
          for (final p in playlists.take(3))
            ListTile(
              leading: CoverImage(
                url: p.entries.isNotEmpty ? p.entries.first.picUrl : null,
                size: 44,
                icon: Icons.queue_music,
              ),
              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${p.entries.length} 首'),
              trailing: Icon(Icons.chevron_right,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => PlaylistDetailPage(playlistId: p.id))),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  // 音乐库 Tab 里有完整歌单管理
                  Navigator.of(context).maybePop();
                },
                child: const Text('全部歌单 ›', style: TextStyle(fontSize: 12)),
              ),
            ),
          ),
        ],
        // —— 继续聆听 ——
        if (recent.isNotEmpty) ...[
          const _SectionHeader('继续聆听'),
          SizedBox(
            height: 148,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: recent.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final item = recent[i];
                return _RecentCard(
                  title: item.title,
                  artist: item.artist,
                  onTap: () {
                    core.setQueue(recent, index: i);
                    Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const PlayerPage()));
                  },
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 24),
      ]),
    );
  }

}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      );
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.onPlay});
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5B8DEF), Color(0xFF8B5CF6), Color(0xFFE0A3C8)],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text('每日推荐 · 为你精选',
              style: TextStyle(color: Colors.white, fontSize: 11)),
        ),
        const SizedBox(height: 10),
        const Text('开始今天的聆听',
            style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: onPlay,
          icon: const Icon(Icons.play_arrow, size: 20),
          label: const Text('立即播放'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF5B5FEF),
          ),
        ),
      ]),
    );
  }
}

/// 今日热门：脚本首榜 Top10（零内置源，能力由导入脚本声明）。
class _HotSongsSection extends ConsumerWidget {
  const _HotSongsSection({required this.boardId, required this.boardName});
  final String boardId;
  final String boardName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lx = ref.watch(sourceRegistryProvider).activeRuntime;
    if (lx == null) return const SizedBox.shrink();
    return FutureBuilder<List<MusicInfo>?>(
      future: lx.boardSongsFromScript(boardId, limit: 10),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('榜单加载失败（音源网络波动）',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12)),
          );
        }
        final songs = snap.data ?? const <MusicInfo>[];
        return Column(children: [
          for (var i = 0; i < songs.length; i++)
            ListTile(
              leading: SizedBox(
                width: 26,
                child: Text('${i + 1}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: i < 3
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold)),
              ),
              title: Text(songs[i].title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(songs[i].artist,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                final core = ref.read(playerCoreProvider);
                final items = [
                  for (final m in songs)
                    PlayerItem(
                        title: m.title,
                        artist: m.artist,
                        sourceId: m.sourceId,
                        musicId: m.musicId,
                        artUri: m.album?.picUrl == null ||
                                m.album!.picUrl!.isEmpty
                            ? null
                            : Uri.tryParse(m.album!.picUrl!),
                        raw: m.raw),
                ];
                core.setQueue(items, index: i);
                Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const PlayerPage()));
              },
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => BoardSongsPage(
                      bangId: boardId, boardName: boardName))),
              icon: const Icon(Icons.list, size: 18),
              label: const Text('查看完整榜单'),
            ),
          ),
        ]);
      },
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard(
      {required this.title, required this.artist, required this.onTap});
  final String title;
  final String artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 132,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: const LinearGradient(
                colors: [Color(0xFF5B8DEF), Color(0xFF8B5CF6)],
              ),
            ),
            child: const Icon(Icons.music_note, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13)),
          Text(artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: scheme.onSurfaceVariant, fontSize: 11)),
        ]),
      ),
    );
  }
}

