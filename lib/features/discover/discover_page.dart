import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../core/models/music.dart';
import 'daily_recommend.dart';
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
        // —— 每日推荐（真实曲目：多歌手种子 → 各平台取曲 → 去重混排）——
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: _DailyRecommendCard(
            onPlayAll: (songs) {
              if (songs.isEmpty) return;
              core.setQueue([
                for (final m in songs)
                  PlayerItem(
                    title: m.title,
                    artist: m.artist,
                    sourceId: m.sourceId,
                    musicId: m.musicId,
                    album: m.album?.name,
                    artUri: (m.album?.picUrl == null ||
                            m.album!.picUrl!.isEmpty)
                        ? null
                        : Uri.tryParse(m.album!.picUrl!),
                    duration: m.duration,
                    raw: m.raw,
                  ),
              ], index: 0);
              Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const PlayerPage()));
            },
          ),
        ),
        // —— 排行榜（脚本驱动：导入的音源声明 boardList/boardSongs 才显示）——
        // key 绑定源 id：切换音源时重建 FutureBuilder，重新拉取该源的榜单
        if (ref.watch(sourceRegistryProvider).activeRuntime != null)
          FutureBuilder<List<MusicBoard>>(
            key: ValueKey('boards_${_effectiveSourceId()}'),
            future: () async {
              // 用选中源（_effectiveSourceId），而不是固定的 activeRuntime，
              // 否则切换音源后排行榜不跟着变。
              final reg = ref.read(sourceRegistryProvider);
              final id = _effectiveSourceId();
              final lx = id == null ? null : reg.runtimeOf(id);
              if (lx == null) return const <MusicBoard>[];
              return await lx.boardListFromScript() ?? const <MusicBoard>[];
            }(),
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
                    sourceId: _effectiveSourceId(),
                    boardId: boards.first.id,
                    boardName: boards.first.name),
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

/// 每日推荐卡片：真实曲目（多歌手种子 → 各平台取曲 → 去重混排）。
///
/// 此前这里播放的是内置 demo 和弦音（asset:///assets/audio/demo_c.wav），
/// 是明确的假功能。内置五平台没有官方"每日推荐"接口，
/// 因此用种子歌手构造真实可播列表。
class _DailyRecommendCard extends StatefulWidget {
  const _DailyRecommendCard({required this.onPlayAll});
  final void Function(List<MusicInfo> songs) onPlayAll;

  @override
  State<_DailyRecommendCard> createState() => _DailyRecommendCardState();
}

class _DailyRecommendCardState extends State<_DailyRecommendCard> {
  List<MusicInfo>? _songs;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final songs = await DailyRecommend.fetchOrOverride();
    if (!mounted) return;
    setState(() {
      _songs = songs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final songs = _songs ?? const <MusicInfo>[];

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
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
            child: Text(
              _loading
                  ? '每日推荐 · 正在挑选'
                  : (songs.isEmpty
                      ? '每日推荐 · 暂无数据'
                      : '每日推荐 · ${songs.length} 首'),
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
          const SizedBox(height: 10),

          // 推荐内容预览：显示前 3 首真实曲目（而不是空泛口号）
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('正在从各平台挑选今天的歌…',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            )
          else if (songs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('暂时拿不到推荐',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('音源可能不可用，稍后重试',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12)),
              ]),
            )
          else ...[
            for (final m in songs.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  const Icon(Icons.music_note, size: 13, color: Colors.white70),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${m.title} · ${m.artist}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12.5),
                    ),
                  ),
                ]),
              ),
          ],

          const SizedBox(height: 12),
          Row(children: [
            FilledButton.icon(
              onPressed: songs.isEmpty ? null : () => widget.onPlayAll(songs),
              icon: const Icon(Icons.play_arrow, size: 20),
              label: Text(songs.isEmpty ? '暂不可播' : '播放全部'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF5B5FEF),
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(width: 10),
            if (songs.isNotEmpty)
              TextButton.icon(
                onPressed: _load,
                icon: Icon(Icons.refresh,
                    size: 16, color: Colors.white.withValues(alpha: 0.9)),
                label: Text('换一批',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 12)),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// 今日热门：脚本首榜 Top10（零内置源，能力由导入脚本声明）。
class _HotSongsSection extends ConsumerWidget {
  const _HotSongsSection({
    required this.sourceId,
    required this.boardId,
    required this.boardName,
  });
  final String? sourceId;
  final String boardId;
  final String boardName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reg = ref.watch(sourceRegistryProvider);
    final lx = sourceId == null ? null : reg.runtimeOf(sourceId!);
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
