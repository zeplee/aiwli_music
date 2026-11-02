import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/models/music.dart';
import '../../../core/models/quality.dart';
import '../../../player/player_core.dart';
import '../../../sources/builtin/builtin_search.dart';
import '../../../sources/lx/lx_source.dart';
import '../../../sources/registry.dart';
import '../player/player_page.dart';

/// 搜索页：五平台并发聚合（酷我/QQ/网易/酷狗/咪咕）+ 脚本源补充。
///
/// 交互：结果**按源分组为顶部 Tab**（每个 Tab 显示源名与条数），
/// 避免长列表里分组头被滚走而分不清来源。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  List<SourceGroup> _groups = const [];
  bool _loading = false;
  String? _error;
  int _generation = 0;

  /// 当前选中的 Tab（默认「全部」）。
  int _tabIndex = 0;

  TabController? _tabs;

  /// 每个源分组的滚动控制器（用于滚到底自动加载下一页）。
  final Map<String, ScrollController> _scrollCtrls = {};

  ScrollController _ctrlFor(String key) => _scrollCtrls.putIfAbsent(key, () {
        final c = ScrollController();
        c.addListener(() => _maybeLoadMore(key));
        return c;
      });

  /// 滚动到接近底部时加载该源下一页。
  void _maybeLoadMore(String sourceId) {
    final c = _scrollCtrls[sourceId];
    if (c == null || !c.hasClients) return;
    if (c.position.maxScrollExtent - c.position.pixels > 320) return;

    // 「全部」Tab：并发续载所有可加载源
    if (sourceId == '__all__') {
      final targets =
          _groups.where((g) => g.canLoadMore && !g.loadingMore).toList();
      if (targets.isEmpty) return;
      unawaited(_loadMoreAll(targets));
      return;
    }

    final idx = _groups.indexWhere((g) => g.sourceId == sourceId);
    if (idx < 0) return;
    final g = _groups[idx];
    if (!g.canLoadMore) return;

    unawaited(_loadMore(idx));
  }

  /// 内容不足一屏时列表不可滚动 → 滚动监听永不触发。
  /// 这里在每帧后检查：若该源仍可加载且内容未填满视口，则主动续载。
  void _fillViewportIfNeeded() {
    for (final g in _groups) {
      if (!g.canLoadMore) continue;
      final c = _scrollCtrls[g.sourceId];
      if (c == null || !c.hasClients) continue;
      if (c.position.maxScrollExtent <= 1) {
        final idx = _groups.indexOf(g);
        if (idx >= 0 && !_filling.contains(g.sourceId)) {
          _filling.add(g.sourceId);
          unawaited(_loadMore(idx).whenComplete(() {
            _filling.remove(g.sourceId);
          }));
        }
        break;
      }
    }
  }

  /// 正在补屏的源，防止重复触发。
  final Set<String> _filling = {};

  Future<void> _loadMore(int idx) async {
    if (idx < 0 || idx >= _groups.length) return;
    final g = _groups[idx];
    if (!g.canLoadMore) return;

    setState(() => g.loadingMore = true);
    await BuiltinSearch.loadMore(g);
    if (!mounted) return;
    setState(() => g.loadingMore = false);
  }

  void _onTabChanged() {
    final i = _tabs?.index ?? 0;
    if (i != _tabIndex && mounted) setState(() => _tabIndex = i);
  }

  @override
  void dispose() {
    _tabs?.removeListener(_onTabChanged);
    for (final c in _scrollCtrls.values) {
      c.dispose();
    }
    _controller.dispose();
    _tabs?.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final kw = _controller.text.trim();
    if (kw.isEmpty) return;
    final gen = ++_generation;

    setState(() {
      _loading = true;
      _error = null;
      _groups = const [];
      _tabIndex = 0;
    });

    final builtinFuture = BuiltinSearch.searchAll(
      kw,
      onGroup: (groups) {
        if (!mounted || gen != _generation) return;
        setState(() => _groups = groups);
      },
    );
    // 脚本源并发进行，完成后即时追加（不必等内置源全部结束）
    List<SourceGroup> scriptGroups = const [];
    final scriptFuture = _searchScript(kw).then((g) {
      scriptGroups = g;
      if (mounted && gen == _generation && _groups.isNotEmpty) {
        setState(() => _groups = [..._groups, ...g]);
      }
      return g;
    });

    try {
      final builtin = await builtinFuture;
      if (!mounted || gen != _generation) return;
      setState(() => _groups = builtin);
      await scriptFuture;
      if (!mounted || gen != _generation) return;

      final all = [...builtin, ...scriptGroups];
      setState(() {
        _groups = all;
        _loading = false;
        if (all.every((g) => !g.hasResults) &&
            all.every((g) => g.state != SourceSearchState.failed)) {
          _error = '没有找到「$kw」相关歌曲';
        }
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = '搜索失败: $e';
        _loading = false;
      });
    }
  }

  /// 并发搜索所有「已启用且声明 musicSearch」的脚本/插件源。
  /// 每个源独立成组，单源失败不影响其他源。
  Future<List<SourceGroup>> _searchScript(String kw) async {
    final registry = ref.read(sourceRegistryProvider);
    final runtimes = registry.enabledRuntimes;
    if (runtimes.isEmpty) return const [];

    // 先并发探测能力（waitInited 内部有缓存，第二次调用立即返回）
    final capable = <LxSource>[];
    await Future.wait(runtimes.map((lx) async {
      try {
        await lx.waitInited();
        if (lx.actions.contains('musicSearch')) capable.add(lx);
      } catch (_) {}
    }));
    if (capable.isEmpty) return const [];

    // 并发搜索
    final groups = <SourceGroup>[];
    await Future.wait(capable.map((lx) async {
      final g = SourceGroup(
        sourceId: 'script:${lx.id}',
        label: lx.name,
        state: SourceSearchState.loading,
        keyword: kw,
      );
      try {
        final list = await lx
            .searchFromScript(kw)
            .timeout(const Duration(seconds: 20));
        g.songs = list ?? const [];
        g.state = SourceSearchState.done;
      } catch (e) {
        g.state = SourceSearchState.failed;
        g.error = e.toString().replaceAll('\n', ' ');
        if (g.error!.length > 60) g.error = '${g.error!.substring(0, 60)}…';
      }
      groups.add(g);
    }));
    return groups;
  }

  /// 「全部」Tab 的合并列表（按源顺序拼接，保留来源标签）。
  List<(SourceGroup, MusicInfo)> get _mergedAll {
    final out = <(SourceGroup, MusicInfo)>[];
    for (final g in _groups) {
      for (final s in g.songs) {
        out.add((g, s));
      }
    }
    return out;
  }

  void _playAll(List<MusicInfo> songs, int index) {
    final core = ref.read(playerCoreProvider);
    core.setQueue(
      [
        for (final m in songs)
          PlayerItem(
            title: m.title,
            artist: m.artist,
            sourceId: m.sourceId,
            musicId: m.musicId,
            duration: m.duration,
          ),
      ],
      index: index,
    );
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const PlayerPage()));
  }

  Future<void> _download(MusicInfo m) async {
    final messenger = ScaffoldMessenger.of(context);
    final manager = ref.read(downloadManagerProvider);
    await manager.start(PlayerItem(
      title: m.title,
      artist: m.artist,
      sourceId: m.sourceId,
      musicId: m.musicId,
    ));
    messenger.showSnackBar(SnackBar(
        content: Text('下载任务结束：${m.title}（详见下载页）'),
        duration: const Duration(seconds: 1)));
  }

  /// 结果总量（Tab 标题用）。
  int get _totalCount => _groups.fold(0, (sum, g) => sum + g.count);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final registry = ref.watch(sourceRegistryProvider);

    // 官方机制：MediaQuery.gestureSettings 会被 Scrollable 读取并注入拖拽识别器。
    // 把 touchSlop 抬到 40（默认约 18），斜向/快速纵向滚动时横向手势更难抢先。
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        gestureSettings: const DeviceGestureSettings(touchSlop: 40),
      ),
      child: _buildScaffold(scheme, registry),
    );
  }

  Widget _buildScaffold(ColorScheme scheme, SourceRegistry registry) {
    final tabCount = 1 + _groups.length;
    if (_tabs == null || _tabs!.length != tabCount) {
      final old = _tabs;
      final initial = _tabIndex.clamp(0, tabCount - 1);
      _tabs = TabController(
          length: tabCount, vsync: this, initialIndex: initial);
      _tabs!.addListener(_onTabChanged);
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fillViewportIfNeeded();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索'),
        bottom: _groups.isEmpty
            ? null
            : TabBar(
                controller: _tabs,
                onTap: (i) => setState(() => _tabIndex = i),
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontSize: 13),
                tabs: [
                  Tab(text: '全部 $_totalCount'),
                  for (final g in _groups)
                    Tab(
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(g.label),
                        const SizedBox(width: 4),
                        _tabBadge(g, scheme),
                      ]),
                    ),
                ],
              ),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => unawaited(_search()),
            decoration: InputDecoration(
              hintText: '搜索歌曲 / 歌手（五平台同时搜）',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                  onPressed: () => unawaited(_search()),
                  icon: const Icon(Icons.arrow_forward)),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
          ),
        ),
        if (!registry.hasActiveSource)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(children: [
              Icon(Icons.info_outline, size: 14, color: scheme.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text('可搜索；点播取链需在「我的 → 音源管理」导入脚本',
                    style: TextStyle(fontSize: 11, color: scheme.outline)),
              ),
            ]),
          ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: Row(children: [
              Icon(Icons.search_off, size: 15, color: scheme.error),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(_error!,
                      style: TextStyle(fontSize: 12, color: scheme.error))),
            ]),
          ),
        Expanded(child: _body(scheme)),
      ]),
    );
  }

  Widget _body(ColorScheme scheme) {
    if (_groups.isEmpty) {
      if (_loading) return const SizedBox.shrink();
      return const Center(
        child: Text('输入关键词开始搜索\n五个平台会同时搜索，结果按源分 Tab 展示',
            textAlign: TextAlign.center),
      );
    }
    return TabBarView(
      controller: _tabs,
      children: [
        _buildAllTab(scheme),
        for (final g in _groups) _buildGroupTab(g, scheme),
      ],
    );
  }

  /// 「全部」：合并列表，每行带来源小标签。
  Widget _buildAllTab(ColorScheme scheme) {
    final merged = _mergedAll;
    if (merged.isEmpty) {
      return _emptyHint('各平台均无结果', scheme);
    }
    // 「全部」也支持滚到底：并发拉所有仍可加载的源下一页
    return ListView.builder(
      controller: _ctrlFor('__all__'),
      itemCount: merged.length + 1,
      itemBuilder: (context, i) {
        if (i == merged.length) return _allTabFooter(scheme);
        final (g, m) = merged[i];
        final songs = g.songs;
        return _songTile(
          m,
          scheme,
          sourceLabel: g.label,
          onTap: () => _playAll(songs, songs.indexOf(m)),
        );
      },
    );
  }

  Widget _buildGroupTab(SourceGroup g, ColorScheme scheme) {
    if (g.state == SourceSearchState.failed) {
      return _emptyHint('该源搜索失败\n${g.error ?? "未知错误"}', scheme,
          icon: Icons.error_outline);
    }
    if (!g.hasResults) {
      final waiting = g.state == SourceSearchState.loading ||
          g.state == SourceSearchState.pending;
      return _emptyHint(waiting ? '搜索中…' : '该源无结果', scheme);
    }
    final showFooter = !g.isScript;
    return ListView.builder(
      controller: _ctrlFor(g.sourceId),
      itemCount: g.songs.length + (showFooter ? 1 : 0),
      itemBuilder: (context, i) {
        if (showFooter && i == g.songs.length) return _listFooter(g, scheme);
        return _songTile(
          g.songs[i],
          scheme,
          onTap: () => _playAll(g.songs, i),
        );
      },
    );
  }

  Widget _listFooter(SourceGroup g, ColorScheme scheme) {
    final Widget child;
    if (g.loadingMore) {
      child = const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 8),
        Text('加载中…', style: TextStyle(fontSize: 12)),
      ]);
    } else if (g.canLoadMore) {
      child = TextButton(
        onPressed: () => unawaited(_loadMoreById(g.sourceId)),
        child: const Text('加载更多', style: TextStyle(fontSize: 13)),
      );
    } else {
      child = Text('— 已全部加载 ${g.count} 首 —',
          style: TextStyle(fontSize: 11, color: scheme.outline));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(child: child),
    );
  }

  Widget _allTabFooter(ColorScheme scheme) {
    final loadable = _groups.where((g) => g.canLoadMore).toList();
    if (loadable.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('— 已全部加载 \$_totalCount 首 —',
              style: TextStyle(fontSize: 11, color: scheme.outline)),
        ),
      );
    }
    final busy = _groups.any((g) => g.loadingMore);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: busy
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('加载中…', style: TextStyle(fontSize: 12)),
                ],
              )
            : TextButton(
                onPressed: () => unawaited(_loadMoreAll(loadable)),
                child: Text('加载更多（$loadable.length 个源）',
                    style: const TextStyle(fontSize: 13)),
              ),
      ),
    );
  }

  /// 「全部」Tab 加载更多：并发拉所有可加载源的下一页。
  Future<void> _loadMoreAll(List<SourceGroup> targets) async {
    if (targets.isEmpty) return;
    setState(() {
      for (final g in targets) {
        g.loadingMore = true;
      }
    });
    await Future.wait([for (final g in targets) BuiltinSearch.loadMore(g)]);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadMoreById(String sourceId) async {
    final idx = _groups.indexWhere((g) => g.sourceId == sourceId);
    if (idx < 0) return;
    await _loadMore(idx);
  }

  Widget _emptyHint(String text, ColorScheme scheme,
      {IconData icon = Icons.music_off}) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 32, color: scheme.outline),
        const SizedBox(height: 8),
        Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: scheme.outline)),
      ]),
    );
  }

  /// Tab 上的状态/数量小徽章。
  Widget _tabBadge(SourceGroup g, ColorScheme scheme) {
    final (text, color) = switch (g.state) {
      SourceSearchState.pending => ('·', scheme.outline),
      SourceSearchState.loading => ('…', scheme.primary),
      SourceSearchState.done =>
        g.hasResults ? ('${g.count}', scheme.primary) : ('0', scheme.outline),
      SourceSearchState.failed => ('!', scheme.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _songTile(
    MusicInfo m,
    ColorScheme scheme, {
    String? sourceLabel,
    required VoidCallback onTap,
  }) {
    final q = m.qualities.map((e) => e.label).join(' / ').trim();
    return ListTile(
      dense: true,
      leading: const Icon(Icons.music_note, size: 20),
      title: Row(children: [
        Flexible(
            child: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (sourceLabel != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(sourceLabel,
                style: TextStyle(fontSize: 9, color: scheme.primary)),
          ),
        ],
      ]),
      subtitle: Text(
        [m.artist, if (m.album?.name.isNotEmpty == true) m.album!.name, q]
            .join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.download_for_offline_outlined, size: 20),
        tooltip: '下载',
        onPressed: () => unawaited(_download(m)),
      ),
      onTap: onTap,
    );
  }
}