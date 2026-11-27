import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../player/player_core.dart';
import '../player/player_page.dart';

/// 下载页：进行中 / 历史 双 Tab。
///
/// 沿用工程现有 Scaffold + ListView 交互，只是补上暂停/继续/重试/删除
/// 与历史记录；不新增导航层级、不引入第三方控件。
class DownloadsPage extends ConsumerStatefulWidget {
  const DownloadsPage({super.key});

  @override
  ConsumerState<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends ConsumerState<DownloadsPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(downloadManagerProvider);
    final list = _tab == 0 ? manager.tasks : manager.history;
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载'),
        actions: [
          if (_tab == 1 && manager.history.isNotEmpty)
            TextButton(
              onPressed: manager.clearFinished,
              child: const Text('清空记录'),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Row(
            children: [
              for (var i = 0; i < 2; i++)
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: _tab == i
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () => setState(() => _tab = i),
                    child: Text(i == 0 ? '进行中' : '历史'),
                  ),
                ),
            ],
          ),
        ),
      ),
      body: list.isEmpty
          ? Center(
              child: Text(
                _tab == 0
                    ? '暂无下载任务\n在搜索结果点下载图标即可离线保存'
                    : '暂无完成或失败的记录',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) => _row(context, manager, list[i]),
            ),
    );
  }

  Widget _row(BuildContext context, DownloadManager manager, DownloadTask t) {
    final progress = t.total > 0
        ? (t.received / t.total).clamp(0.0, 1.0)
        : 0.0;
    final running = t.status == '下载中' || t.status == '取链接…';
    return ListTile(
      leading: const Icon(Icons.audio_file),
      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${t.status} · ${_fmtMb(t.received)}'
            '${t.total > 0 ? ' / ${_fmtMb(t.total)}' : ''}'
            '${running && t.total > 0 ? '  ${(progress * 100).toStringAsFixed(0)}%' : ''}'
            '${t.error != null && t.error!.isNotEmpty ? '\n${t.error}' : ''}',
            style: const TextStyle(fontSize: 12),
          ),
          if (running)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(
                value: t.total > 0 ? progress : null,
                minHeight: 3,
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (t.playable)
            IconButton(
              tooltip: '播放本地文件',
              icon: const Icon(Icons.play_circle_outline),
              onPressed: () => _play(context, t),
            ),
          if (_tab == 0 && running)
            IconButton(
              tooltip: '暂停',
              icon: const Icon(Icons.pause_circle_outline),
              onPressed: () => manager.pause(t),
            ),
          if (t.status == '已暂停')
            IconButton(
              tooltip: '继续',
              icon: const Icon(Icons.play_circle_outline),
              onPressed: () => manager.resume(t),
            ),
          if (t.status == '失败' || t.status == '已暂停')
            IconButton(
              tooltip: '重试',
              icon: const Icon(Icons.refresh),
              onPressed: () => manager.retry(t),
            ),
          IconButton(
            tooltip: '删除记录（不删已保存文件）',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => manager.remove(t),
          ),
        ],
      ),
    );
  }

  void _play(BuildContext context, DownloadTask t) {
    // 落库后直接以本地曲目入队：sourceId=local，resolvedUrl 指向媒体库 uri。
    ref.read(playerCoreProvider).setQueue([
      PlayerItem(
        title: t.title,
        artist: t.artist,
        sourceId: 'local',
        musicId: t.savedUri!,
        resolvedUrl: t.savedUri,
      )
    ], index: 0);
    Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const PlayerPage()));
  }

  static String _fmtMb(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB'
      : '${(bytes / 1024).toStringAsFixed(0)}KB';
}
