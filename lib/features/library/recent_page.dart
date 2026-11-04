import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/ui/cover_image.dart';
import '../../player/player_core.dart';
import '../player/player_page.dart';

/// 最近播放：按时间倒序，点击播放，长按可移除单条。
class RecentPlayedPage extends ConsumerWidget {
  const RecentPlayedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(playHistoryProvider);
    final scheme = Theme.of(context).colorScheme;
    final items = history.items;

    if (items.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('最近播放')),
        body: const Center(child: Text('还没有播放记录')),
      );
    }

    List<PlayerItem> toQueue() => [
          for (final h in items)
            PlayerItem(
              title: h.title,
              artist: h.artist,
              sourceId: h.sourceId,
              musicId: h.musicId,
              album: h.album,
              artUri: (h.picUrl == null || h.picUrl!.isEmpty)
                  ? null
                  : Uri.tryParse(h.picUrl!),
              duration: h.durationMs == null
                  ? null
                  : Duration(milliseconds: h.durationMs!),
            ),
        ];

    void playAt(int index) {
      ref.read(playerCoreProvider).setQueue(toQueue(), index: index);
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const PlayerPage()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('最近播放 · ${items.length} 首'),
        actions: [
          TextButton.icon(
            onPressed: () => ref.read(playHistoryProvider).clear(),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('清空'),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, i) {
          final h = items[i];
          return ListTile(
            leading: CoverImage(
              url: (h.picUrl == null || h.picUrl!.isEmpty) ? null : h.picUrl,
              size: 44,
              radius: 6,
            ),
            title: Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(h.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
            trailing: IconButton(
              tooltip: '从记录中移除',
              onPressed: () =>
                  ref.read(playHistoryProvider).remove(h.sourceId, h.musicId),
              icon: Icon(Icons.close, size: 18, color: scheme.outline),
            ),
            onTap: () => playAt(i),
          );
        },
      ),
    );
  }
}
