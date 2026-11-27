import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/models/quality.dart';
import '../../core/services/app_settings.dart';
import '../../core/services/settings_prefs.dart';

/// 搜索与下载偏好：沿用「我的」页即时生效的设置范式，没有保存按钮。
class SettingsPrefsPage extends ConsumerWidget {
  const SettingsPrefsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final p = settings.prefs;
    final exportText = jsonEncode(p.toJson());

    return Scaffold(
      appBar: AppBar(title: const Text('搜索与下载偏好')),
      body: ListView(
        children: [
          const _SectionTitle('搜索'),
          ListTile(
            title: const Text('默认搜索平台'),
            subtitle: Text(_sourceLabel(p.defaultSearchSource)),
            onTap: () => _pick<String>(
              context: context,
              values: kSearchSources,
              current: p.defaultSearchSource,
              label: (v) => _sourceLabel(v),
              onPicked: (v) => settings.setPrefs(
                  p.copyWith(defaultSearchSource: v)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('已启用搜索源（至少保留 1 个）',
                    style: TextStyle(fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in kSearchSources)
                      FilterChip(
                        label: Text(_sourceLabel(s)),
                        selected: p.enabledSearchSources.contains(s),
                        onSelected: (on) {
                          final next = {...p.enabledSearchSources};
                          if (on) {
                            next.add(s);
                          } else {
                            if (next.length <= 1) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('至少要保留一个搜索源')),
                              );
                              return;
                            }
                            next.remove(s);
                          }
                          settings.setPrefs(
                              p.copyWith(enabledSearchSources: next));
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          ListTile(
            title: const Text('点击搜索结果'),
            subtitle: Text(p.searchResultAction == 'play'
                ? '播放这首歌'
                : '播放并替换播放列表'),
            onTap: () => _pick<String>(
              context: context,
              values: kSearchResultActions,
              current: p.searchResultAction,
              label: (v) =>
                  v == 'play' ? '播放这首歌' : '播放并替换播放列表',
              onPicked: (v) => settings.setPrefs(
                  p.copyWith(searchResultAction: v)),
            ),
          ),
          const _SectionTitle('下载'),
          ListTile(
            title: const Text('下载音质'),
            subtitle: Text(_qualityLabel(p.downloadQuality)),
            onTap: () => _pick<Quality>(
              context: context,
              values: Quality.values,
              current: p.downloadQuality,
              label: _qualityLabel,
              onPicked: (v) => settings.setPrefs(
                  p.copyWith(downloadQuality: v)),
            ),
          ),
          ListTile(
            title: const Text('文件命名方式'),
            subtitle: Text(p.downloadFileNameStyle == 'artist_title'
                ? '歌手 - 歌名'
                : '歌名 - 歌手'),
            onTap: () => _pick<String>(
              context: context,
              values: kDownloadNameStyles,
              current: p.downloadFileNameStyle,
              label: (v) =>
                  v == 'artist_title' ? '歌手 - 歌名' : '歌名 - 歌手',
              onPicked: (v) => settings.setPrefs(
                  p.copyWith(downloadFileNameStyle: v)),
            ),
          ),
          const _SectionTitle('配置导入导出'),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('复制当前配置'),
            subtitle: Text(exportText,
                maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: exportText));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('配置已复制到剪贴板')),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.input),
            title: const Text('从 JSON 导入'),
            subtitle: const Text('粘贴导出的配置，非法字段会被跳过'),
            onTap: () => _importDialog(context, settings),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _importDialog(
      BuildContext context, AppSettings settings) async {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入配置'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: '粘贴配置 JSON',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('导入')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final decoded = jsonDecode(controller.text.trim());
      if (decoded is! Map) throw const FormatException('根节点必须是对象');
      final warnings = SettingsPrefs.applyFromJson(
        decoded,
        (p) => settings.setPrefs(p),
      );
      messenger.showSnackBar(SnackBar(
        content: Text(warnings.isEmpty
            ? '配置已导入'
            : '已导入；${warnings.length} 项被跳过：${warnings.join('；')}'),
      ));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('导入失败：${e.toString().split('\n').first}')));
    } finally {
      controller.dispose();
    }
  }

  Future<void> _pick<T>({
    required BuildContext context,
    required List<T> values,
    required T current,
    required String Function(T) label,
    required void Function(T) onPicked,
  }) async {
    final picked = await showModalBottomSheet<T>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final v in values)
              ListTile(
                title: Text(label(v)),
                trailing: v == current
                    ? const Icon(Icons.check, color: Colors.blue)
                    : null,
                onTap: () => Navigator.pop(ctx, v),
              ),
          ],
        ),
      ),
    );
    if (picked != null) onPicked(picked);
  }
}

String _sourceLabel(String id) => switch (id) {
      'kw' => '酷我',
      'tx' => 'QQ音乐',
      'wy' => '网易云',
      'kg' => '酷狗',
      'mg' => '咪咕',
      _ => id,
    };

String _qualityLabel(Quality q) => switch (q) {
      Quality.standard => '标准 128k',
      Quality.high => '高品 320k',
      Quality.superQuality => '320k 高码率',
      Quality.lossless => '无损 FLAC',
      Quality.hires => 'Hi-Res',
    };

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary)),
      );
}
