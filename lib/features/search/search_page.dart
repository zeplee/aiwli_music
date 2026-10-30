import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/models/music.dart';
import '../../../core/models/quality.dart';
import '../../../player/player_core.dart';
import '../player/player_page.dart';

/// 搜索页：关键词 → 内置 kw 搜索 → 点播（脚本取链）/下载。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  List<MusicInfo>? _results;
  bool _loading = false;
  String? _error;

  Future<void> _search() async {
    final kw = _controller.text.trim();
    if (kw.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lx = ref.read(sourceRegistryProvider).activeRuntime;
      if (lx == null) {
        if (!mounted) return;
        setState(() => _error = '未启用音源：请在「我的 → 音源管理」导入并启用');
        return;
      }
      final list = await lx.searchFromScript(kw);
      if (list == null) {
        if (!mounted) return;
        setState(() => _error = '当前音源不支持搜索（需脚本声明 musicSearch 能力）');
        return;
      }
      if (!mounted) return;
      setState(() => _results = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '搜索失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
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
    final registry = ref.watch(sourceRegistryProvider);
    final rows = _results;
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
              hintText: '搜索歌曲 / 歌手（酷我源）',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                  onPressed: () => unawaited(_search()),
                  icon: const Icon(Icons.arrow_forward)),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
          ),
        ),
        if (!registry.hasActiveSource)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              child: const ListTile(
                dense: true,
                leading: Icon(Icons.warning_amber_rounded),
                title: Text('尚未启用 lx 音源',
                    style: TextStyle(fontSize: 13)),
                subtitle: Text('点播在线歌曲前请到「设置 → 音源管理」导入脚本',
                    style: TextStyle(fontSize: 12)),
              ),
            ),
          ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
        Expanded(
          child: rows == null
              ? const Center(
                  child: Text('输入关键词开始搜索\n结果可点播（脚本取链）或下载',
                      textAlign: TextAlign.center))
              : rows.isEmpty
                  ? const Center(child: Text('无结果'))
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, i) {
                        final m = rows[i];
                        return ListTile(
                          leading: const Icon(Icons.music_note),
                          title: Text(m.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${m.artist} · ${m.album?.name ?? ""} · ${m.qualities.map((q) => q.label).join("/").trim()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            icon: const Icon(
                                Icons.download_for_offline_outlined),
                            tooltip: '下载',
                            onPressed: () => unawaited(_download(m)),
                          ),
                          onTap: () => _playAll(rows, i),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
