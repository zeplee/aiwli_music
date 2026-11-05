import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import '../../../app_providers.dart';
import '../../../core/services/source_health_service.dart';

/// 音源管理（二级页）：导入 / 启停 / 删除 / 设活跃。
class SourceManagePage extends ConsumerWidget {
  const SourceManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(sourceRegistryProvider);
    final health = ref.watch(sourceHealthProvider);
    final scheme = Theme.of(context).colorScheme;
    // 已失效（连续失败 ≥5）的源，用于顶部汇总提示
    final deadSources = <(String, String)>[
      for (final s in registry.installed)
        if (s.enabled && health.recordFor(s.id).health == SourceHealth.dead)
          (s.name, s.id),
    ];
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
        // 失效源汇总提示（被动统计，不从网络探测）
        if (deadSources.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${deadSources.length} 个源近期连续取链失败：${deadSources.map((e) => e.$1).join('、')}',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onErrorContainer),
                ),
              ),
              TextButton(
                onPressed: () {
                  for (final e in deadSources) {
                    ref.read(sourceRegistryProvider).setEnabled(e.$2, false);
                  }
                },
                child: Text('全部禁用',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onErrorContainer)),
              ),
            ]),
          ),
        for (final s in registry.installed)
          _SourceTile(
            source: s,
            isActive: s.id == registry.activeId,
            health: health.recordFor(s.id),
            onSetActive: () => ref.read(sourceRegistryProvider).setActive(s.id),
            onToggle: (v) =>
                ref.read(sourceRegistryProvider).setEnabled(s.id, v),
            onDelete: () => ref.read(sourceRegistryProvider).remove(s.id),
            onDisable: () =>
                ref.read(sourceRegistryProvider).setEnabled(s.id, false),
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
            OutlinedButton.icon(
              onPressed: () => _importPluginFiles(context, ref),
              icon: const Icon(Icons.extension, size: 18),
              label: const Text('导入插件文件'),
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
        if (_isMusicFreePlugin(text)) {
          await ref.read(sourceRegistryProvider).importMusicFreePlugin(text);
          count++;
        } else if (text.contains('globalThis.lx') || text.contains('lx.on')) {
          await ref.read(sourceRegistryProvider).importScript(text);
          count++;
        }
      } catch (_) {}
    }
    _toast(messenger, count > 0 ? '已导入 $count 个音源脚本' : 'Download 目录未发现 lx 脚本');
  }

  /// MusicFree 插件判定：CommonJS 模块导出 + 典型方法名。
  static bool _isMusicFreePlugin(String code) {
    if (code.contains('globalThis.lx')) return false;
    return code.contains('getMediaSource') &&
        (code.contains('module.exports') || code.contains('exports.'));
  }

  /// 从文件选择器导入多个 .js（自动区分 lx 脚本与 MusicFree 插件）。
  Future<void> _importPluginFiles(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    const groups = [
      XTypeGroup(label: '音源脚本/插件', extensions: ['js', 'txt']),
    ];
    final files = await openFiles(acceptedTypeGroups: groups);
    if (files.isEmpty) return;
    var lxCount = 0, mfCount = 0, failed = 0;
    for (final f in files) {
      try {
        final text = await f.readAsString();
        if (_isMusicFreePlugin(text)) {
          await ref.read(sourceRegistryProvider).importMusicFreePlugin(text);
          mfCount++;
        } else if (text.contains('globalThis.lx') || text.contains('lx.on')) {
          await ref.read(sourceRegistryProvider).importScript(text);
          lxCount++;
        } else {
          failed++;
        }
      } catch (_) {
        failed++;
      }
    }
    final parts = <String>[];
    if (lxCount > 0) parts.add('lx 脚本 $lxCount');
    if (mfCount > 0) parts.add('MusicFree 插件 $mfCount');
    if (failed > 0) parts.add('无法识别 $failed');
    _toast(messenger, parts.isEmpty ? '未导入任何源' : '已导入：${parts.join('、')}');
  }

  void _toast(ScaffoldMessengerState messenger, String msg) {
    messenger.showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }
}


/// 单个源卡片：名称 + 健康状态 + 最近失败原因 + 操作。
class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.isActive,
    required this.health,
    required this.onSetActive,
    required this.onToggle,
    required this.onDelete,
    required this.onDisable,
  });
  final dynamic source;
  final bool isActive;
  final SourceHealthRecord health;
  final VoidCallback onSetActive;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;
  final VoidCallback onDisable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = source.enabled as bool;
    final dead = health.health == SourceHealth.dead;
    final degraded = health.health == SourceHealth.degraded;

    final dotColor = !enabled
        ? scheme.onSurfaceVariant
        : dead
            ? scheme.error
            : degraded
                ? scheme.tertiary
                : scheme.primary;

    return ListTile(
      onTap: onSetActive,
      leading: Icon(Icons.extension,
          color: enabled ? scheme.primary : scheme.onSurfaceVariant),
      title: Row(children: [
        // 健康状态圆点
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        Expanded(
          child: Text(source.name as String,
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (enabled)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: dotColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(health.healthLabel,
                style: TextStyle(fontSize: 10, color: dotColor)),
          ),
      ]),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            enabled && isActive
                ? '活跃中'
                : (enabled ? '已启用' : '已停用'),
            style: const TextStyle(fontSize: 12),
          ),
          // 失败原因（只在有失败时显示，翻译成人类语言）
          if (enabled && health.consecutiveFailures > 0)
            Text(
              '连续失败 ${health.consecutiveFailures} 次 · ${health.friendlyError}',
              style: TextStyle(
                  fontSize: 11,
                  color: dead ? scheme.error : scheme.onSurfaceVariant),
            ),
        ],
      ),
      isThreeLine: enabled && health.consecutiveFailures > 0,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        // 失效源给一键禁用
        if (dead)
          TextButton(
            onPressed: onDisable,
            child: Text('禁用',
                style: TextStyle(fontSize: 12, color: scheme.error)),
          ),
        Switch(value: enabled, onChanged: onToggle),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: onDelete,
        ),
      ]),
    );
  }
}
