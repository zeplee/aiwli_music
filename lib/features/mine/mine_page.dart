import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../downloads/downloads_page.dart';
import 'webdav_page.dart';
import 'source_manage_page.dart';

/// 我的：入口列表（下载 / 音源管理 / WebDAV 同步）+ 关于。
class MinePage extends ConsumerWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(sourceRegistryProvider);
    final favorites = ref.watch(favoritesProvider);
    final webdav = ref.watch(webDavServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(children: [
        const SizedBox(height: 8),
        // —— 头部卡 ——
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF5B8DEF), Color(0xFF8B5CF6)],
              ),
            ),
            child: Row(children: [
              const CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white24,
                child: Icon(Icons.person, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Aiwli Music',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
                Text('v0.1.0 · ${registry.installed.length} 个音源',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12)),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        // —— 入口列表 ——
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: const Text('下载管理'),
          subtitle: Text(tasksSubtitle(ref)),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const DownloadsPage())),
        ),
        ListTile(
          leading: const Icon(Icons.extension),
          title: const Text('音源管理'),
          subtitle: Text(registry.hasActiveSource
              ? '活跃源：${registry.installed.firstWhere((s) => s.id == registry.activeId).name}'
              : '未导入音源脚本'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const SourceManagePage())),
        ),
        ListTile(
          leading: const Icon(Icons.favorite),
          title: const Text('我的收藏'),
          subtitle: Text('${favorites.items.length} 首'),
          trailing: const Icon(Icons.chevron_right),
          onTap: null, // 收藏列表页待 M4 后期；数据已在 WebDAV 备份内
        ),
        ListTile(
          leading: const Icon(Icons.cloud_sync_outlined),
          title: const Text('WebDAV 同步'),
          subtitle: Text(webdav.config.isConfigured
              ? webdav.config.serverUrl
              : '未配置服务器'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const WebDavPage())),
        ),
        const Divider(height: 32),
        // —— 关于 ——
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text('关于',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ),
        const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Aiwli Music'),
            subtitle: Text('v0.1.0 · 本地+音源闭环版')),
        const ListTile(
            leading: Icon(Icons.code),
            title: Text('架构'),
            subtitle: Text('media_kit 引擎 · lx 脚本音源 · 五端 Flutter')),
        const SizedBox(height: 24),
      ]),
    );
  }

  static String tasksSubtitle(WidgetRef ref) {
    final manager = ref.watch(downloadManagerProvider);
    final running =
        manager.tasks.where((t) => t.status == '下载中').length;
    if (manager.tasks.isEmpty) return '暂无任务';
    return running > 0
        ? '${manager.tasks.length} 个任务（$running 个进行中）'
        : '${manager.tasks.length} 个任务';
  }
}
