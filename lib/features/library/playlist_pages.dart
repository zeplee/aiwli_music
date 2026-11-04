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
/// 歌单区：纵向列表（替代原先的横向滚动条）。
///
/// 横向滚动条的问题（用户实测反馈）：歌单超过 4-5 个就找不到，
/// 必须左右滑且没有搜索。参考栖弦的 playlist_management_page：
/// 独立管理页 + 纵向 SliverList。
///
/// 这里保持"嵌在曲库页里"的形态（不新开页），但改为纵向列表 +
/// 歌单数超过 6 个时出现搜索框。
class PlaylistsStrip extends ConsumerStatefulWidget {
  const PlaylistsStrip({super.key});

  @override
  ConsumerState<PlaylistsStrip> createState() => _PlaylistsStripState();
}

class _PlaylistsStripState extends ConsumerState<PlaylistsStrip> {
  String _query = '';
  final Set<String> _expandedFolders = <String>{};

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(playlistsProvider);
    final scheme = Theme.of(context).colorScheme;

    final sorted = service.sorted;
    final q = _query.trim().toLowerCase();
    final grouped = service.grouped;

    // 搜索时退化为平铺结果（便于快速定位），否则按文件夹分组
    final searchHits = q.isEmpty
        ? <Playlist>[]
        : [
            for (final p in sorted)
              if (p.name.toLowerCase().contains(q)) p,
          ];

    final showSearch = sorted.length > 6;

    // 分组渲染顺序：未分组在前，其次各文件夹（保持首次出现顺序）
    final folderKeys = <String?>[
      if (grouped.containsKey(null)) null,
      for (final f in service.folders)
        if (grouped.containsKey(f)) f,
    ];

    Widget tileFor(Playlist p) => SizedBox(
          height: 56,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            // 性能：12 个歌单各下一张网络封面会让首帧掉到秒级，
            // 歌单条目用图标占位即可。
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: scheme.surfaceContainerHighest,
              ),
              child: Icon(
                p.system ? Icons.star_outline : Icons.queue_music,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ),
            title: Text(p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14)),
            subtitle: Text('${p.entries.length} 首',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              // 移动到文件夹 / 移出文件夹
              IconButton(
                tooltip: p.folder == null ? '移到文件夹' : '移出文件夹',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  p.folder == null ? Icons.drive_file_move_outline : Icons.folder_off_outlined,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                onPressed: () => _moveToFolder(p),
              ),
              Icon(Icons.chevron_right,
                  size: 18, color: scheme.onSurfaceVariant),
            ]),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => PlaylistDetailPage(playlistId: p.id))),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // —— 标题栏：歌单数 + 新建文件夹 + 导入/新建歌单 ——
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Text('歌单',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
          Text('${sorted.length}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const Spacer(),
          IconButton(
            tooltip: '新建文件夹',
            onPressed: _createFolder,
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: '导入歌单',
            onPressed: () => _importPlaylistFile(context, ref),
            icon: const Icon(Icons.upload_file, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: '新建歌单',
            onPressed: () => _create(context, ref),
            icon: const Icon(Icons.add, size: 20),
            visualDensity: VisualDensity.compact,
          ),
        ]),
      ),

      if (showSearch)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: TextField(
            decoration: InputDecoration(
              hintText: '搜索歌单',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            style: const TextStyle(fontSize: 13),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),

      if (sorted.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('还没有歌单，新建一个或导入 M3U',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        )
      else if (q.isNotEmpty) ...[
        // 搜索结果：平铺
        if (searchHits.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text('没有匹配「$_query」的歌单',
                style: TextStyle(
                    color: scheme.onSurfaceVariant, fontSize: 12)),
          )
        else
          for (final p in searchHits) tileFor(p),
      ] else ...[
        // 分组渲染
        for (final f in folderKeys) ...[
          if (f == null) ...[
            for (final p in grouped[null]!) tileFor(p),
          ] else
            _FolderSection(
              name: f,
              count: grouped[f]!.length,
              initiallyExpanded: _expandedFolders.contains(f),
              onToggle: () => setState(() {
                if (!_expandedFolders.remove(f)) _expandedFolders.add(f);
              }),
              onRemove: () => _confirmRemoveFolder(f),
              children: [
                if (_expandedFolders.contains(f))
                  for (final p in grouped[f]!)
                    if (!(p.name == '（空文件夹）' && p.entries.isEmpty))
                      tileFor(p),
              ],
            ),
        ],
      ],
    ]);
  }

  // ————————————————— 文件夹操作 —————————————————

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '文件夹名称，如「李泽鹏」'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('创建')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    ref.read(playlistsProvider).ensureFolder(name);
    if (mounted) setState(() => _expandedFolders.add(name));
  }

  Future<void> _moveToFolder(Playlist p) async {
    final service = ref.read(playlistsProvider);
    if (p.folder != null) {
      service.setFolder(p.id, null);
      if (mounted) setState(() {});
      return;
    }
    final folders = service.folders;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text('「${p.name}」移到…',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final f in folders)
            ListTile(
              leading: const Icon(Icons.folder_outlined, size: 20),
              title: Text(f),
              onTap: () => Navigator.of(context).pop(f),
            ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined, size: 20),
            title: const Text('新建文件夹…'),
            onTap: () => Navigator.of(context).pop('__new__'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked == null) return;
    if (picked == '__new__') {
      await _createFolder();
      final latest = service.folders;
      if (latest.isEmpty) return;
      service.setFolder(p.id, latest.last);
    } else {
      service.setFolder(p.id, picked);
    }
    if (mounted) setState(() {});
  }

  Future<void> _confirmRemoveFolder(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除文件夹「$name」？'),
        content: const Text('文件夹里的歌单会回到顶层，歌单本身不会被删除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除文件夹')),
        ],
      ),
    );
    if (ok == true) {
      ref.read(playlistsProvider).removeFolder(name);
      if (mounted) setState(() => _expandedFolders.remove(name));
    }
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '歌单名称')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('创建')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    ref.read(playlistsProvider).create(name);
    if (mounted) setState(() {});
  }

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

  /// lx 导入时给待匹配条目（sourceId='pending'）找真实音源并回填。
  Future<int> _matchEntries(NavigatorState rootNavigator, WidgetRef ref,
      String playlistId, List<PlaylistEntry> entries) async {
    final service = ref.read(playlistsProvider);
    final lx = ref.read(sourceRegistryProvider).activeRuntime;
    if (lx == null) return 0;
    var cancelled = false;
    rootNavigator.push(PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: false,
      pageBuilder: (_, _, _) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('正在为歌单曲目匹配音源…', style: TextStyle(fontSize: 13)),
            ]),
          ),
        ),
      ),
    ));
    var matched = 0;
    final pl = service.byId(playlistId);
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

/// 文件夹分组：可折叠，头部显示名称 + 歌单数 + 删除。
class _FolderSection extends StatelessWidget {
  const _FolderSection({
    required this.name,
    required this.count,
    required this.initiallyExpanded,
    required this.onToggle,
    required this.onRemove,
    required this.children,
  });
  final String name;
  final int count;
  final bool initiallyExpanded;
  final VoidCallback onToggle;
  final VoidCallback onRemove;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(initiallyExpanded ? Icons.folder_open : Icons.folder,
                size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Text(name,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Text('$count',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            const Spacer(),
            IconButton(
              tooltip: '删除文件夹',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.delete_outline,
                  size: 16, color: scheme.onSurfaceVariant),
              onPressed: onRemove,
            ),
            Icon(initiallyExpanded ? Icons.expand_less : Icons.expand_more,
                size: 18, color: scheme.onSurfaceVariant),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Column(children: children),
      ),
    ]);
  }
}
