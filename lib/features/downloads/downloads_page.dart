import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../player/player_core.dart';
import '../player/player_page.dart';

/// 下载页：任务列表 + 进度。
class DownloadsPage extends ConsumerWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(downloadManagerProvider);
    final tasks = manager.tasks;
    return Scaffold(
      appBar: AppBar(title: const Text('下载')),
      body: tasks.isEmpty
          ? const Center(
              child: Text('暂无下载任务\n在搜索结果点下载图标即可离线保存',
                  textAlign: TextAlign.center))
          : ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (context, i) {
                final t = tasks[i];
                final progress =
                    t.total > 0 ? (t.received / t.total).clamp(0.0, 1.0) : 0.0;
                return ListTile(
                  leading: const Icon(Icons.audio_file),
                  trailing: t.playable
                      ? IconButton(
                          tooltip: '播放本地文件',
                          icon: const Icon(Icons.play_circle_outline),
                          onPressed: () {
                            // 落库后直接以本地曲目入队：sourceId=local，
                            // resolvedUrl 指向媒体库 uri，解析器不再取链。
                            ref.read(playerCoreProvider).setQueue([
                              PlayerItem(
                                title: t.title,
                                artist: t.artist,
                                sourceId: 'local',
                                musicId: t.savedUri!,
                                resolvedUrl: t.savedUri,
                              )
                            ], index: 0);
                            Navigator.of(context).push(MaterialPageRoute<void>(
                                builder: (_) => const PlayerPage()));
                          },
                        )
                      : null,
                  title: Text(t.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${t.status} · ${_fmtMb(t.received)}'
                          '${t.total > 0 ? ' / ${_fmtMb(t.total)}' : ''}'
                          '${t.status == '下载中' && t.total > 0 ? '  ${(progress * 100).toStringAsFixed(0)}%' : ''}',
                          style: const TextStyle(fontSize: 12)),
                      if (t.status == '下载中')
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: LinearProgressIndicator(
                              // 服务端没给 Content-Length 时用不确定进度条
                              value: t.total > 0 ? progress : null,
                              minHeight: 3),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  static String _fmtMb(int bytes) =>
      bytes >= 1024 * 1024
          ? '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB'
          : '${(bytes / 1024).toStringAsFixed(0)}KB';
}
