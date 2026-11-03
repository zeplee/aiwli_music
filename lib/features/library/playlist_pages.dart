import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/services/backup_service.dart' show parseTextPlaylist;
import '../../core/services/playlists.dart';
import '../../player/player_core.dart';
import '../player/player_page.dart';

/// 歌单详情：条目列表 + 播放全部 + 删除/重命名 + 条目移除。
class PlaylistDetailPage extends ConsumerStatefulWidget {
  const PlaylistDetailPage({required this.playlistId, super.key});
  final String playlistId;

  @override
  ConsumerState<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  @override
  Widget build(BuildContext context) {
    final service = ref.watch(playlistsProvider);
    final playlist = service.playlists
        .where((p) => p.id == widget.playlistId)
        .firstOrNull;
    final scheme = Theme.of(context).colorScheme;
    if (playlist == null) {
      return const Scaffold(body: Center(child: Text('歌单不存在')));
    }

    PlayerItem entryToItem(PlaylistEntry e) => PlayerItem(
          title: e.title,
          artist: e.artist,
          sourceId: e.sourceId,
          musicId: e.musicId,
          album: e.album,
          duration: e.durationMs != null
              ? Duration(milliseconds: e.durationMs!)
              : null,
          resolvedUrl: e.resolvedPath,
          raw: e.raw,
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name),
        actions: [
          IconButton(
            tooltip: '重命名',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _rename(context, service, playlist),
          ),
          IconButton(
            tooltip: '删除歌单',
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              service.delete(playlist.id);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: playlist.entries.isEmpty
          ? Center(
              child: Text('空歌单，去音乐库长按歌曲加入',
                  style: TextStyle(color: scheme.onSurfaceVariant)))
          : ListView.builder(
              itemCount: playlist.entries.length,
              itemBuilder: (context, i) {
                final e = playlist.entries[i];
                return ListTile(
                  leading: const Icon(Icons.music_note),
                  title: Text(e.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(e.artist,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: Icon(Icons.play_circle_outline,
                          size: 22,
                          color: Theme.of(context).colorScheme.primary),
                      tooltip: '播放',
                      onPressed: () {
                        final items = [
                          for (final e in playlist.entries) entryToItem(e)
                        ];
                        ref.read(playerCoreProvider).setQueue(items, index: i);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      tooltip: '移出歌单',
                      onPressed: () => service.removeEntry(playlist.id, i),
                    ),
                  ]),
                  onTap: () {
                    final items = [
                      for (final e in playlist.entries) entryToItem(e)
                    ];
                    ref.read(playerCoreProvider).setQueue(items, index: i);
                    Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const PlayerPage()));
                  },
                );
              },
            ),
      bottomNavigationBar: playlist.entries.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () {
                    final items = [
                      for (final e in playlist.entries) entryToItem(e)
                    ];
                    ref.read(playerCoreProvider).setQueue(items, index: 0);
                    Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const PlayerPage()));
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('播放全部'),
                ),
              ),
            ),
    );
  }

  Future<void> _rename(BuildContext context, PlaylistService service,
      Playlist playlist) async {
    final controller = TextEditingController(text: playlist.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名歌单'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('确定')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      service.rename(playlist.id, name);
    }
  }
}

/// 音乐库歌单条（新建 / 导入 M3U / 歌单卡片）。
class PlaylistsStrip extends ConsumerWidget {
  const PlaylistsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(playlistsProvider);
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('歌单',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const Spacer(),
        TextButton.icon(
          onPressed: () => _importPlaylistFile(context, ref),
          icon: const Icon(Icons.upload_file, size: 18),
          label: const Text('导入歌单', style: TextStyle(fontSize: 12)),
        ),
        TextButton.icon(
          onPressed: () => _create(context, ref),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('新建', style: TextStyle(fontSize: 12)),
        ),
      ]),
      SizedBox(
        height: 96,
        child: service.playlists.isEmpty
            ? Align(
                alignment: Alignment.centerLeft,
                child: Text('还没有歌单，新建一个或导入 M3U',
                    style: TextStyle(
                        color: scheme.onSurfaceVariant, fontSize: 12)))
            : ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: service.playlists.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final p = service.playlists[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) =>
                                PlaylistDetailPage(playlistId: p.id))),
                    child: Container(
                      width: 132,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: scheme.surfaceContainerHighest,
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Icon(Icons.queue_music),
                            Text(p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                            Text('${p.entries.length} 首',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant)),
                          ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(controller: controller, autofocus: true,
            decoration: const InputDecoration(hintText: '歌单名称')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('创建')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      ref.read(playlistsProvider).create(name);
    }
  }

  /// 导入歌单文件：自动识别 M3U / 文本歌单（每行“歌手 - 标题”，lx 风格）。
  /// 文本条目在音源支持 musicSearch 时自动匹配。
  Future<void> _importPlaylistFile(BuildContext context, WidgetRef ref) async {
    const groups = [
      XTypeGroup(
          label: '歌单文件', extensions: ['m3u', 'm3u8', 'txt', 'list']),
    ];
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final file = await openFile(acceptedTypeGroups: groups);
    if (file == null) return;
    final content = await file.readAsString();
    final baseName =
        file.name.replaceAll(RegExp(r'\.(m3u8?|txt|list)$', caseSensitive: false), '');

    final isM3u = content.contains('#EXTINF') ||
        RegExp(r'^\[\d+:\d+', multiLine: true).hasMatch(content);

    final service = ref.read(playlistsProvider);
    List<PlaylistEntry> entries;
    var matched = 0;

    if (isM3u) {
      final p = service.importM3u(baseName, content);
      if (p == null) {
        messenger.showSnackBar(const SnackBar(content: Text('未解析到有效条目')));
        return;
      }
      entries = p.entries;
      matched = entries.length;
    } else {
      final lines = parseTextPlaylist(content);
      if (lines.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('未解析到有效条目')));
        return;
      }
      // 创建歌单，先放入待匹配条目
      final p = service.create(baseName);
      entries = [
        for (final l in lines)
          PlaylistEntry(
            sourceId: 'pending',
            musicId: '',
            title: l.title,
            artist: l.artist ?? '未知歌手',
          ),
      ];
      service.addEntries(p.id, entries);

      // 自动匹配（活跃音源声明 musicSearch 才可用）
      final lx = ref.read(sourceRegistryProvider).activeRuntime;
      if (lx != null) {
        final canSearch = await lx.searchFromScript('__probe__').then(
              (v) => true,
              onError: (_) => false,
            );
        if (canSearch) {
          matched = await _matchEntries(
              rootNavigator, ref, p.id, entries);
        }
      }
    }

    final pending = entries.length - matched;
    messenger.showSnackBar(SnackBar(
        content: Text('导入 ${entries.length} 首：已匹配 $matched${pending > 0 ? '，未匹配 $pending（需支持搜索的音源）' : ''}')));
  }

  Future<int> _matchEntries(NavigatorState rootNavigator, WidgetRef ref,
      String playlistId, List<PlaylistEntry> entries) async {
    final service = ref.read(playlistsProvider);
    final lx = ref.read(sourceRegistryProvider).activeRuntime;
    if (lx == null) return 0;

    var matched = 0;
    var cancelled = false;
    // 进度弹窗
    showDialog<void>(
      context: rootNavigator.context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('正在匹配歌曲'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: entries.isEmpty ? 0 : matched / entries.length),
            const SizedBox(height: 12),
            Text('$matched / ${entries.length}'),
          ]),
          actions: [
            TextButton(
                onPressed: () {
                  cancelled = true;
                  Navigator.of(dialogCtx).pop();
                },
                child: const Text('停止')),
          ],
        ),
      ),
    );

    final pl = service.playlists.where((x) => x.id == playlistId).firstOrNull;
    if (pl == null) return 0;
    final fresh = pl.entries; // 与刚创建一致
    for (var i = 0; i < fresh.length && i < entries.length && !cancelled; i++) {
      final e = fresh[i];
      if (e.sourceId != 'pending') {
        matched++;
        continue;
      }
      try {
        final kw = e.artist == '未知歌手' ? e.title : '${e.artist} ${e.title}';
        final hits = await lx.searchFromScript(kw);
        if (hits != null && hits.isNotEmpty) {
          final hit = hits.first;
          service.replaceEntry(playlistId, i,
              PlaylistEntry(
                sourceId: hit.sourceId,
                musicId: hit.musicId,
                title: hit.title,
                artist: hit.artist,
                album: hit.album?.name,
                durationMs: hit.duration?.inMilliseconds,
                rawJson: hit.raw == null
                    ? null
                    : jsonEncode(hit.raw!.cast<String, Object?>()),
              ));
          matched++;
        }
      } catch (_) {
        // 单条失败继续
      }
    }
    if (!cancelled && rootNavigator.canPop()) rootNavigator.pop();
    return matched;
  }
}

/// 长按歌曲加入歌单（底部弹层）。
Future<void> showAddToPlaylistSheet(
    BuildContext context, WidgetRef ref, PlaylistEntry entry) {
  final service = ref.read(playlistsProvider);
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
            padding: const EdgeInsets.all(14),
            child: Text('加入歌单', style: Theme.of(context).textTheme.titleMedium)),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('新建歌单'),
          onTap: () async {
            final controller = TextEditingController();
            final name = await showDialog<String>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('新建歌单'),
                content: TextField(controller: controller, autofocus: true),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () =>
                          Navigator.of(context).pop(controller.text),
                      child: const Text('创建')),
                ],
              ),
            );
            if (name != null && name.trim().isNotEmpty) {
              final p = service.create(name);
              service.addEntries(p.id, [entry]);
            }
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
        for (final p in service.playlists)
          ListTile(
            leading: const Icon(Icons.queue_music),
            title: Text(p.name),
            subtitle: Text('${p.entries.length} 首'),
            onTap: () {
              service.addEntries(p.id, [entry]);
              Navigator.of(context).pop();
            },
          ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}
