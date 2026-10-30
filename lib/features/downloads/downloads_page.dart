import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';

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
                  title: Text(t.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${t.status} · ${_fmtMb(t.received)}${t.total > 0 ? ' / ${_fmtMb(t.total)}' : ''}',
                          style: const TextStyle(fontSize: 12)),
                      if (t.status == '下载中')
                        LinearProgressIndicator(value: progress),
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
