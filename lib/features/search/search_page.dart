import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/models/music.dart';
import '../../../core/models/quality.dart';
import '../../../player/player_core.dart';
import '../../../sources/builtin/builtin_search.dart';
import '../player/player_page.dart';

/// 搜索页：内置三平台并发聚合（酷我 / QQ / 网易）+ 脚本源补充。
///
/// 设计要点（对齐 lx-music / 同类实现）：
///  - 内置平台**并发**请求，谁先返回先显示（渐进式）
///  - 结果**按源分组**，便于跨源对比音质
///  - 单源失败不影响其他源，组内显示错误标记
///  - 脚本声明 musicSearch 时额外追加脚本结果分组
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  List<SourceGroup> _groups = const [];
  bool _loading = false;
  String? _error;

  /// 当前搜索的世代号，用于丢弃过期结果（快速连续搜索）。
  int _generation = 0;

  Future<void> _search() async {
    final kw = _controller.text.trim();
    if (kw.isEmpty) return;
    final gen = ++_generation;

    setState(() {
      _loading = true;
      _error = null;
      _groups = const [];
    });

    // ① 内置三平台：并发 + 渐进式
    final builtinFuture = BuiltinSearch.searchAll(
      kw,
      onGroup: (groups) {
        if (!mounted || gen != _generation) return;
        setState(() => _groups = groups);
      },
    );

    // ② 脚本源（声明 musicSearch 才有）：并行发起，完成后追加分组
    final scriptFuture = _searchScript(kw, gen);

    try {
      final builtin = await builtinFuture;
      if (!mounted || gen != _generation) return;
      final scriptGroups = await scriptFuture;
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

  /// 脚本源搜索（可选）：只有声明了 musicSearch 的脚本才参与。
  Future<List<SourceGroup>> _searchScript(String kw, int gen) async {
    final registry = ref.read(sourceRegistryProvider);
    final lx = registry.activeRuntime;
    if (lx == null) return const [];
    try {
      final list = await lx.searchFromScript(kw);
      if (list == null || list.isEmpty) return const [];
      return [
        SourceGroup(
          sourceId: 'script:${lx.id}',
          label: '脚本源 · ${lx.name}',
          state: SourceSearchState.done,
          songs: list,
        ),
      ];
    } catch (_) {
      return const [];
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final registry = ref.watch(sourceRegistryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => unawaited(_search()),
            decoration: InputDecoration(
              hintText: '搜索歌曲 / 歌手（酷我 · QQ · 网易 同时搜）',
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Material(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              child: const ListTile(
                dense: true,
                leading: Icon(Icons.info_outline, size: 18),
                title: Text('在线播放需要音源脚本', style: TextStyle(fontSize: 13)),
                subtitle: Text('搜索可用；点播取链请到「我的 → 音源管理」导入脚本',
                    style: TextStyle(fontSize: 12)),
              ),
            ),
          ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(children: [
              Icon(Icons.search_off, size: 16, color: scheme.error),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(_error!,
                      style: TextStyle(fontSize: 13, color: scheme.error))),
            ]),
          ),
        Expanded(
          child: _groups.isEmpty && !_loading
              ? const Center(
                  child: Text('输入关键词开始搜索\n三个平台会同时搜索，按源分组展示',
                      textAlign: TextAlign.center))
              : ListView(
                  children: [
                    for (final g in _groups) _sourceSection(g, scheme),
                    const SizedBox(height: 24),
                  ],
                ),
        ),
      ]),
    );
  }

  Widget _sourceSection(SourceGroup g, ColorScheme scheme) {
    final songs = g.songs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 分组头：源名 + 状态 + 数量
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(children: [
            Text(g.label,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            _stateChip(g, scheme),
            const Spacer(),
            if (g.hasResults)
              Text('${g.count} 首',
                  style: TextStyle(fontSize: 12, color: scheme.outline)),
          ]),
        ),
        const Divider(height: 1),
        if (g.state == SourceSearchState.failed)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Text('该源搜索失败：${g.error ?? "未知错误"}',
                style: TextStyle(fontSize: 12, color: scheme.error)),
          )
        else if (!g.hasResults)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Text(
                g.state == SourceSearchState.loading ||
                        g.state == SourceSearchState.pending
                    ? '搜索中…'
                    : '无结果',
                style: TextStyle(fontSize: 12, color: scheme.outline)),
          )
        else
          for (var i = 0; i < songs.length; i++) _songTile(songs, i),
      ],
    );
  }

  Widget _stateChip(SourceGroup g, ColorScheme scheme) {
    final (text, color) = switch (g.state) {
      SourceSearchState.pending => ('等待', scheme.outline),
      SourceSearchState.loading => ('搜索中', scheme.primary),
      SourceSearchState.done =>
        g.hasResults ? ('完成', scheme.primary) : ('无结果', scheme.outline),
      SourceSearchState.failed => ('失败', scheme.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color)),
    );
  }

  Widget _songTile(List<MusicInfo> songs, int i) {
    final m = songs[i];
    final q = m.qualities.map((e) => e.label).join(' / ').trim();
    return ListTile(
      dense: true,
      leading: const Icon(Icons.music_note, size: 20),
      title: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis),
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
      onTap: () => _playAll(songs, i),
    );
  }
}