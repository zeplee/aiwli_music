import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../core/models/music.dart';
import '../../sources/builtin/board_songs.dart';
import '../../sources/builtin/builtin_boards.dart';
import 'daily_recommend.dart';
import '../../../player/player_core.dart';
import '../player/player_page.dart';

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

  /// 榜单当前查看的平台（内置榜单，与脚本源选择独立）。
  String _boardSource = 'kw';

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
        // —— 排行榜：**内置五平台**（不依赖 lx 脚本）——
        //
        // 之前完全依赖脚本 boardList，脚本后端一失效榜单就整块消失
        // （用户遇到的 sayqz 域名 NXDOMAIN 就是这种情况）。
        // 现在用各平台官方榜单接口，脚本只作为额外补充。
        const _SectionHeader('排行榜'),
        _BuiltinBoardRow(
          selectedSource: _boardSource,
          onSelect: (v) => setState(() => _boardSource = v),
        ),
        _BuiltinHotSongs(
          sourceId: _boardSource,
          board: BuiltinBoards.catalog[_boardSource]!.first,
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

    // 高度必须 >= 48：胶囊自身内边距让它只有 31dp 高，
    // 外层若再限制在 42，可点区就更小（实测难命中）。
    return SizedBox(
      height: 48,
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

/// 榜单平台切换（内置五平台）。
class _BuiltinBoardRow extends StatelessWidget {
  const _BuiltinBoardRow({required this.selectedSource, required this.onSelect});
  final String selectedSource;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ids = BuiltinBoards.catalog.keys.toList();
    // 同音源胶囊：容器高度要给足，否则胶囊自身 29dp 的可点区
    // 会被 40 的容器进一步压缩（实测点击经常落空）。
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: ids.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final id = ids[i];
          final active = id == selectedSource;
          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => onSelect(id),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: active
                    ? scheme.secondaryContainer
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: Text(
                  BuiltinBoards.labels[id] ?? id,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    color: active
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 内置榜单的曲目列表（真实可播，不依赖脚本）。
class _BuiltinHotSongs extends ConsumerStatefulWidget {
  const _BuiltinHotSongs({required this.sourceId, required this.board});
  final String sourceId;
  final MusicBoard board;

  @override
  ConsumerState<_BuiltinHotSongs> createState() => _BuiltinHotSongsState();
}

class _BuiltinHotSongsState extends ConsumerState<_BuiltinHotSongs> {
  List<MusicInfo>? _songs;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _BuiltinHotSongs old) {
    super.didUpdateWidget(old);
    if (old.sourceId != widget.sourceId || old.board.id != widget.board.id) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _songs = null;
    });
    final songs =
        await BoardSongs.fetch(widget.sourceId, widget.board.id, limit: 20);
    if (!mounted) return;
    setState(() {
      _songs = songs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final songs = _songs ?? const <MusicInfo>[];
    if (songs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text('榜单暂时取不到（平台接口波动）',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      );
    }
    return Column(children: [
      for (var i = 0; i < songs.length && i < 10; i++)
        ListTile(
          dense: true,
          leading: SizedBox(
            width: 24,
            child: Text('${i + 1}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: i < 3 ? scheme.primary : scheme.onSurfaceVariant)),
          ),
          title: Text(songs[i].title,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(songs[i].artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11)),
          trailing: Icon(Icons.play_arrow, size: 18, color: scheme.primary),
          onTap: () {
            final items = [
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
            ];
            ref.read(playerCoreProvider).setQueue(items, index: i);
            Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const PlayerPage()));
          },
        ),
    ]);
  }
}
