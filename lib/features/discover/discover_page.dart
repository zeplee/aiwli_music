import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/models/music.dart';
import '../../../player/player_core.dart';
import '../player/player_page.dart';
import 'board_songs_page.dart';

/// 发现页：顶部搜索 → 每日推荐 Hero → 排行榜横滑（脚本能力驱动）→
/// 今日热门（飙升榜）→ 继续聆听 → 快速播放 → 音源状态。
class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({this.onOpenSearch, super.key});

  final VoidCallback? onOpenSearch;

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  /// 发现页当前查看的音源。
  /// 榜单只由 lx 脚本提供（内置五平台 SDK 都没有榜单接口），
  /// 所以按"已安装的源"切换——对齐 lx 的 base-selection
  /// 与栖弦的 DiscoverySourceSelector。
  String? _selectedSourceId;

  /// 当前生效的源：优先用户选择，否则回落活跃源。
  String? _effectiveSourceId() {
    final reg = ref.watch(sourceRegistryProvider);
    if (_selectedSourceId != null &&
        reg.installed.any((s) => s.id == _selectedSourceId)) {
      return _selectedSourceId;
    }
    return reg.activeId;
  }

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
  Widget build(BuildContext context) {
    final core = ref.watch(playerCoreProvider);



    return Scaffold(
      appBar: AppBar(title: const Text('发现')),
      body: ListView(children: [
        // —— 顶部搜索栏 ——
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: InkWell(
            key: const ValueKey('discover_search_bar'),
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onOpenSearch,
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
        // —— 音源切换（榜单由脚本提供，多源时可切）——
        if ((ref.watch(sourceRegistryProvider).installed.where((s) => s.enabled).length) > 1)
          _SourceSelector(
            selectedId: _effectiveSourceId(),
            onSelect: (id) => setState(() => _selectedSourceId = id),
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
        // —— 排行榜（脚本驱动：导入的音源声明 boardList/boardSongs 才显示）——
        // key 绑定源 id：切换音源时重建 FutureBuilder，重新拉取该源的榜单
        if (ref.watch(sourceRegistryProvider).activeRuntime != null)
          FutureBuilder<List<MusicBoard>>(
            key: ValueKey('boards_${_effectiveSourceId()}'),
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
        // 注：「我的歌单」与「继续聆听」已移到「曲库」Tab。
        // 发现页职责 = 纯推荐（每日推荐 / 排行榜 / 今日热门），
        // 避免推荐流里混入"我自己的内容"。
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

/// 音源分段选择器（对齐栖弦 DiscoverySourceSelector 的胶囊样式）。
/// 横向可滚动，左侧滑块跟随选中项；源多时不挤压布局。
class _SourceSelector extends ConsumerWidget {
  const _SourceSelector({required this.selectedId, required this.onSelect});
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final installed = ref
        .watch(sourceRegistryProvider)
        .installed
        .where((s) => s.enabled)
        .toList();
    if (installed.length < 2) return const SizedBox.shrink();

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: installed.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final s = installed[i];
          final active = s.id == selectedId;
          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onSelect(s.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: active
                    ? scheme.secondaryContainer
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active
                      ? scheme.secondary.withValues(alpha: 0.5)
                      : Colors.transparent,
                ),
              ),
              child: Text(
                s.name,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  color: active
                      ? scheme.onSecondaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
