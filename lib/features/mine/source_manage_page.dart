import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter/services.dart';

import '../../../app_providers.dart';

/// 音源管理（二级页）：导入 / 启停 / 删除 / 设活跃。
class SourceManagePage extends ConsumerWidget {
  const SourceManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(sourceRegistryProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('音源管理')),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            registry.hasActiveSource
                ? '活跃源：${registry.installed.firstWhere((s) => s.id == registry.activeId).name}'
                : '尚未启用 lx 音源：导入脚本后即可在线搜索',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ),
        for (final s in registry.installed)
          ListTile(
            onTap: () => ref.read(sourceRegistryProvider).setActive(s.id),
            leading: Icon(Icons.extension,
                color:
                    s.enabled ? scheme.primary : scheme.onSurfaceVariant),
            title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(s.enabled && s.id == registry.activeId
                ? '活跃中'
                : (s.enabled ? '已启用' : '已停用')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Switch(
                value: s.enabled,
                onChanged: (v) =>
                    ref.read(sourceRegistryProvider).setEnabled(s.id, v),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () =>
                    ref.read(sourceRegistryProvider).remove(s.id),
              ),
            ]),
          ),
        if (registry.installed.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('尚未导入音源脚本。\n将 lx 脚本放入 Download 目录后点下方扫描，或复制脚本文本后剪贴板导入。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13)),
          ),
        const Divider(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Wrap(spacing: 12, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: () => _importFromClipboard(context, ref),
              icon: const Icon(Icons.content_paste, size: 18),
              label: const Text('剪贴板导入'),
            ),
            OutlinedButton.icon(
              onPressed: () => _scanDownloadDir(context, ref),
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('扫描 Download 目录'),
            ),
          ]),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }

  Future<void> _importFromClipboard(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.length < 50) {
      _toast(messenger, '剪贴板内容不是有效的脚本文本');
      return;
    }
    final src = await ref.read(sourceRegistryProvider).importScript(text);
    _toast(messenger, '已导入「${src.name}」，已设为活跃源');
  }

  Future<void> _scanDownloadDir(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final dir = Directory('/storage/emulated/0/Download');
    if (!dir.existsSync()) {
      _toast(messenger, '未找到 Download 目录（旧版 Android 才支持此方式）');
      return;
    }
    var count = 0;
    for (final f in dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.js'))) {
      try {
        final text = f.readAsStringSync();
        if (text.contains('globalThis.lx') || text.contains('lx.on')) {
          await ref.read(sourceRegistryProvider).importScript(text);
          count++;
        }
      } catch (_) {}
    }
    _toast(messenger, count > 0 ? '已导入 $count 个音源脚本' : 'Download 目录未发现 lx 脚本');
  }

  void _toast(ScaffoldMessengerState messenger, String msg) {
    messenger.showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }
}
