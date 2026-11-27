import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../app_providers.dart';
import '../../core/models/music.dart';
import '../../core/ui/cover_source.dart';
import '../../sources/builtin/board_songs.dart';
import '../../sources/builtin/builtin_boards.dart';
import '../../sources/builtin/catalog_sdk.dart';
import 'featured_playlists.dart';
import 'platform_dropdown.dart';
import 'playlist_catalog.dart';
import 'glass_tap.dart';
import 'online_playlist_page.dart';
import 'daily_recommend.dart';
import '../../../player/player_core.dart';
import '../player/player_page.dart';
import '../mine/source_manage_page.dart';

/// 发现页：液态玻璃质感的推荐流。
///
/// 结构（对齐栖弦 DiscoveryContent，但保留我们的内置榜单优势）：
///   • 玻璃搜索栏 + 无脚本提示
///   • 「每日推荐」玻璃卡片（曲目预览 + 播放全部 + 换一批）
///   • 「排行榜」平台切换 + Top 榜单列表
///   • 「精选歌单」分类切换 + 瀑布流网格 —— 新增
///   • 下拉刷新 —— 新增
///   • 滚动位置记忆 / 加载更多 —— 新增
///
/// 关于背景：玻璃必须折射"身后"的内容。纯色背景下玻璃看起来是平的，
/// 所以外层 GlassScaffold 传一张与封面同色系的渐变作为 background，
/// 玻璃卡片才有真实的折射与边缘高光。
class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({this.onOpenSearch, super.key});

  final VoidCallback? onOpenSearch;

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  /// 榜单当前查看的平台（内置榜单，与脚本源选择独立）。
  String _boardSource = 'kw';

  /// 刷新计数器：递增即触发所有子块重新取数。
  int _refreshTick = 0;

  bool _canPlay() => ref
      .read(sourceRegistryProvider)
      .enabledRuntimes
      .any((r) => r.actions.contains('musicUrl'));

  void _blockPlayAndExplain() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('还没有可用的音源脚本，无法取到播放地址'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      action: SnackBarAction(
        label: '去导入',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const SourceManagePage())),
      ),
    ));
  }

  /// 统一的"播放一组歌曲"，集中处理取链能力检查，避免每个列表各写一遍。
  void _playAll(List<MusicInfo> songs, {int index = 0}) {
    if (songs.isEmpty) return;
    if (!_canPlay()) {
      _blockPlayAndExplain();
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

  Future<void> _refresh() async {
    setState(() => _refreshTick++);
    // 给子块时间发起请求，让下拉动画不会"瞬时结束"。
    await Future<void>.delayed(const Duration(milliseconds: 650));
  }

  /// 玻璃需要一张背景：用主色系的深色渐变，避免纯色下玻璃失去折射。
  Widget _background(ColorScheme scheme) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                  scheme.primary.withValues(alpha: 0.22), scheme.surface),
              Color.alphaBlend(
                  scheme.tertiary.withValues(alpha: 0.14), scheme.surface),
              scheme.surface,
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final registry = ref.watch(sourceRegistryProvider);
    final canPlay =
        registry.enabledRuntimes.any((r) => r.actions.contains('musicUrl'));
    final enabledCount = registry.installed.where((s) => s.enabled).length;

    return GlassScaffold(
      background: _background(scheme),
      // edgeToEdge + 玻璃 AppBar：顶栏悬浮在内容上，滚动时内容从玻璃下穿过
      edgeToEdge: true,
      statusBarStyle: GlassStatusBarStyle.auto,
      // extendBody 默认 true 会让正文顶到玻璃 AppBar 下方（iOS 26 风格），
      // 实测会导致搜索栏和标题叠在一起（搜索栏 y=22-162、标题 y=112-189）。
      // 我们的正文是 ListView 自己整体上滑的，这里必须关掉，
      // 让正文精确排在 AppBar 下方。
      extendBody: false,
      appBar: const GlassAppBar(
        title: Text('发现'),
        centerTitle: false,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        edgeOffset: 64,
        child: CustomScrollView(
          key: const PageStorageKey<String>('discover-scroll'),
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverList.list(children: [
                // —— 玻璃搜索栏 ——
                _GlassSearchBar(onTap: widget.onOpenSearch),

                // —— 无可用脚本时的说明条 ——
                if (!canPlay) ...[
                  const SizedBox(height: 12),
                  _NoSourceNotice(enabledCount: enabledCount),
                ],

                // —— 每日推荐 ——
                const SizedBox(height: 16),
                _DailyRecommendCard(
                  key: ValueKey('daily-$_refreshTick'),
                  onPlayAll: (songs) => _playAll(songs),
                ),

                // —— 排行榜 ——
                const _SectionHeader('排行榜', subtitle: '各平台实时热榜'),
                _BuiltinBoardRow(
                  selectedSource: _boardSource,
                  onSelect: (v) => setState(() => _boardSource = v),
                ),
                const SizedBox(height: 8),
                _BuiltinHotSongs(
                  key: ValueKey('board-$_boardSource-$_refreshTick'),
                  sourceId: _boardSource,
                  board: BuiltinBoards.catalog[_boardSource]!.first,
                  onPlay: (songs, i) => _playAll(songs, index: i),
                ),

                // —— 精选歌单（新增）——
                const _SectionHeader('精选歌单', subtitle: '按平台分类浏览'),
                _FeaturedPlaylists(
                  key: ValueKey('featured-$_refreshTick'),
                  initialSource: _boardSource,
                ),

                const SizedBox(height: 32),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// 玻璃搜索栏：点击进入搜索页。
class _GlassSearchBar extends StatelessWidget {
  const _GlassSearchBar({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '搜索歌曲或歌手',
      child: GlassContainer(
        shape: const LiquidRoundedSuperellipse(borderRadius: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: GlassTap(
          tapKey: const ValueKey('discover_search_bar'),
          borderRadius: 14,
          onTap: onTap,
          child: Row(children: [
            Icon(Icons.search, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Text(
              '搜索歌曲 / 歌手',
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            ),
          ]),
        ),
      ),
    );
  }
}

/// 无取链脚本时的说明条。内置接口能浏览，但播放需要脚本。
class _NoSourceNotice extends StatelessWidget {
  const _NoSourceNotice({required this.enabledCount});
  final int enabledCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassContainer(
      shape: const LiquidRoundedSuperellipse(borderRadius: 14),
      padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
      child: Row(children: [
        Icon(Icons.info_outline, size: 18, color: scheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            enabledCount == 0
                ? '榜单与推荐来自内置接口，可以浏览；播放需在「我的 › 音源管理」导入脚本。'
                : '已启用 $enabledCount 个音源，但都没有取链能力；播放需支持取链的脚本。',
            style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: scheme.onSurfaceVariant),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const SourceManagePage())),
          child: const Text('去导入', style: TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }
}

/// 区块标题。带副标题时上下留白更紧凑，避免两个标题挤在一起。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 24, 2, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: TextStyle(
                          fontSize: 11.5, color: scheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 每日推荐玻璃卡片。
///
/// 原来是一张写死的紫蓝渐变，与主题无关；现在改成玻璃材质 + 主题色，
/// 内容区仍是真实曲目（多歌手种子 → 各平台取曲 → 去重混排）。
class _DailyRecommendCard extends StatefulWidget {
  const _DailyRecommendCard({required this.onPlayAll, super.key});
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
    setState(() => _loading = true);
    final songs = await DailyRecommend.fetchOrOverride();
    if (!mounted) return;
    setState(() {
      _songs = songs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final songs = _songs ?? const <MusicInfo>[];

    return GlassContainer(
      shape: const LiquidRoundedSuperellipse(borderRadius: 20),
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withValues(alpha: 0.15),
            ),
            child: Icon(Icons.auto_awesome, size: 18, color: scheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('每日推荐',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                Text(
                  _loading
                      ? '正在挑选…'
                      : (songs.isEmpty
                          ? '暂时拿不到推荐'
                          : '${songs.length} 首 · 按你的口味混排'),
                  style: TextStyle(
                      fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (!_loading && songs.isNotEmpty)
            IconButton(
              tooltip: '换一批',
              onPressed: _load,
              icon: Icon(Icons.refresh, size: 18,
                  color: scheme.onSurfaceVariant),
            ),
        ]),

        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (songs.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('音源可能不可用，稍后下拉刷新重试',
                style: TextStyle(
                    fontSize: 12.5, color: scheme.onSurfaceVariant)),
          )
        else ...[
          const SizedBox(height: 12),
          for (final m in songs.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Icon(Icons.music_note,
                    size: 14, color: scheme.primary.withValues(alpha: 0.7)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${m.title} · ${m.artist}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 14),
          Row(children: [
            FilledButton.icon(
              onPressed: () => widget.onPlayAll(songs),
              icon: const Icon(Icons.play_arrow, size: 20),
              label: const Text('播放全部'),
            ),
            const Spacer(),
            Text(
              songs.isEmpty ? '' : '共 ${songs.length} 首',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ]),
        ],
      ]),
    );
  }
}

/// 音源分段选择器（多脚本时的源切换）。
class _BuiltinBoardRow extends StatelessWidget {
  const _BuiltinBoardRow({required this.selectedSource, required this.onSelect});
  final String selectedSource;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: PlatformDropdown(
        selected: selectedSource,
        platforms: BuiltinBoards.catalog.keys.toList(),
        onSelected: onSelect,
        hint: '选择榜单平台',
      ),
    );
  }
}

/// 内置榜单曲目列表（真实可播，不依赖脚本）。
///
/// 改进点：前 3 名用奖牌色序号；整行玻璃卡片化；加载用骨架屏代替
/// 居中转圈（转圈会把下面的版块顶下去，滚动时抖动明显）。
class _BuiltinHotSongs extends ConsumerStatefulWidget {
  const _BuiltinHotSongs({
    required this.sourceId,
    required this.board,
    required this.onPlay,
    super.key,
  });
  final String sourceId;
  final MusicBoard board;
  final void Function(List<MusicInfo> songs, int index) onPlay;

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
      // 骨架屏：占位高度与真实行一致，加载完成不再跳版。
      return Column(children: [
        for (var i = 0; i < 6; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
      ]);
    }

    final songs = _songs ?? const <MusicInfo>[];
    if (songs.isEmpty) {
      return GlassContainer(
        shape: const LiquidRoundedSuperellipse(borderRadius: 14),
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(Icons.cloud_off, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text('榜单暂时取不到（平台接口波动），下拉可重试',
                style: TextStyle(
                    fontSize: 12.5, color: scheme.onSurfaceVariant)),
          ),
        ]),
      );
    }

    return GlassContainer(
      shape: const LiquidRoundedSuperellipse(borderRadius: 18),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: [
        for (var i = 0; i < songs.length && i < 10; i++)
          _BoardRow(
            index: i,
            song: songs[i],
            onTap: () => widget.onPlay(songs, i),
          ),
      ]),
    );
  }
}

/// 榜单单行。前三名序号用金/银/铜，其余用次要色。
class _BoardRow extends StatelessWidget {
  const _BoardRow({required this.index, required this.song, required this.onTap});
  final int index;
  final MusicInfo song;
  final VoidCallback onTap;

  static const _medal = [Color(0xFFE6A23C), Color(0xFFA8B0BC), Color(0xFFC98A5B)];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rank = index + 1;
    final rankColor =
        index < 3 ? _medal[index] : scheme.onSurfaceVariant.withValues(alpha: 0.7);

    return GlassTap(
      borderRadius: 10,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(children: [
          SizedBox(
            width: 24,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: index < 3 ? 15 : 12.5,
                fontWeight: index < 3 ? FontWeight.w800 : FontWeight.w500,
                color: rankColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w500)),
                const SizedBox(height: 1),
                Text(song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Icon(Icons.play_arrow_rounded,
              size: 20, color: scheme.primary.withValues(alpha: 0.75)),
        ]),
      ),
    );
  }
}

/// 精选歌单：平台分类切换 + 2 列网格。
///
/// 这是相对栖弦补上的版块——我们之前只有榜单，没有"逛歌单"的入口。
/// 数据走 CatalogSdk.search(type: playlist)，五平台都有。
class _FeaturedPlaylists extends ConsumerStatefulWidget {
  const _FeaturedPlaylists({required this.initialSource, super.key});
  final String initialSource;

  @override
  ConsumerState<_FeaturedPlaylists> createState() => _FeaturedPlaylistsState();
}

class _FeaturedPlaylistsState extends ConsumerState<_FeaturedPlaylists> {
  /// 五家平台都有无需签名的公开「精选歌单浏览」接口
  /// （见 PlaylistCatalog），不再受关键词搜索能力限制。
  static const _supported = FeaturedPlaylists.supportedSources;

  late String _source =
      _supported.contains(widget.initialSource) ? widget.initialSource : 'wy';
  late String _category = PlaylistCatalog.categories[_source]!.first.id;
  List<CatalogHit>? _items;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _items = null;
    });
    final list = await FeaturedPlaylists.fetch(
      source: _source,
      categoryId: _category,
    );
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  void _select(String id) {
    if (id == _source) return;
    setState(() {
      _source = id;
      _category = PlaylistCatalog.categories[id]!.first.id;
    });
    _load();
  }

  void _selectCategory(String id) {
    if (id == _category) return;
    setState(() => _category = id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PlatformDropdown(
        selected: _source,
        platforms: _supported,
        onSelected: _select,
        hint: '选择歌单平台',
      ),
      if (PlaylistCatalog.categories[_source]!.length > 1) ...[
        const SizedBox(height: 8),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: PlaylistCatalog.categories[_source]!.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = PlaylistCatalog.categories[_source]![i];
              final active = c.id == _category;
              return GlassTap(
                borderRadius: 16,
                onTap: () => _selectCategory(c.id),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: active
                        ? scheme.primary.withValues(alpha: 0.16)
                        : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: active
                          ? scheme.primary.withValues(alpha: 0.4)
                          : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    c.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.bold : FontWeight.normal,
                      color: active
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
      const SizedBox(height: 10),
      if (_loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(child: CircularProgressIndicator()),
        )
      else if ((_items ?? const <CatalogHit>[]).isEmpty)
        GlassContainer(
          shape: const LiquidRoundedSuperellipse(borderRadius: 14),
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(Icons.library_music_outlined,
                size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text('这个平台的歌单接口暂时没有返回内容，换个平台试试',
                  style: TextStyle(
                      fontSize: 12.5, color: scheme.onSurfaceVariant)),
            ),
          ]),
        )
      else
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.02,
          ),
          itemCount: _items!.length,
          itemBuilder: (context, i) =>
              _PlaylistTile(hit: _items![i], source: _source),
        ),
    ]);
  }
}

/// 歌单卡片：封面 + 名称 + 副标题。
class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({required this.hit, required this.source});
  final CatalogHit hit;
  final String source;

  void _open(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => OnlinePlaylistPage(
        source: source,
        playlistId: hit.id,
        title: hit.title,
        coverUrl: hit.picUrl,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassTap(
      borderRadius: 14,
      onTap: () => _open(context),
      child: GlassContainer(
        shape: const LiquidRoundedSuperellipse(borderRadius: 14),
        padding: const EdgeInsets.all(10),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: (hit.picUrl == null || hit.picUrl!.isEmpty)
                  ? Container(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(Icons.queue_music,
                          size: 22, color: scheme.onSurfaceVariant),
                    )
                  : Image.network(
                      CoverSource.normalize(hit.picUrl, size: 300) ??
                          hit.picUrl!,
                      headers: CoverSource.headers(hit.picUrl),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, _, _) => Container(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(Icons.queue_music,
                            size: 22, color: scheme.onSurfaceVariant),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(hit.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600,
                  height: 1.25)),
          if (hit.subtitle.isNotEmpty)
            Text(hit.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10.5, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}