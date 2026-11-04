import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';

/// 歌词设置面板（参考栖弦 lyric_settings_sheet）。
///
/// 三个独立控制：字号档位、翻译开关、罗马音开关。
/// 字号独立于系统字号，便于车载/大屏场景单独放大。
Future<void> showLyricSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => const _LyricSettingsSheet(),
  );
}

class _LyricSettingsSheet extends ConsumerWidget {
  const _LyricSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(children: [
            Text('歌词设置',
                style: Theme.of(context).textTheme.titleMedium),
          ]),
        ),
        const Divider(height: 1),

        // —— 字号 ——
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            const Text('字号', style: TextStyle(fontSize: 13)),
            const Spacer(),
            Text(
              switch (settings.lyricSizeLevel) {
                1 => '小',
                3 => '大',
                4 => '特大',
                _ => '中',
              },
              style: TextStyle(fontSize: 12, color: scheme.primary),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            for (var level = 1; level <= 4; level++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: OutlinedButton(
                    onPressed: () => ref
                        .read(appSettingsProvider)
                        .setLyricPrefs(sizeLevel: level),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: settings.lyricSizeLevel == level
                          ? scheme.primaryContainer
                          : null,
                      side: BorderSide(
                        color: settings.lyricSizeLevel == level
                            ? scheme.primary
                            : scheme.outlineVariant,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(
                      switch (level) {
                        1 => '小',
                        3 => '大',
                        4 => '特大',
                        _ => '中',
                      },
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
          ]),
        ),

        // 字号预览
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              Text('夜色渐浓 风也温柔',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: settings.lyricFontSize,
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  )),
              if (settings.lyricTranslation)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('夜色渐浓，风也温柔（翻译示例）',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: settings.lyricFontSize * 0.6,
                        color: scheme.onSurfaceVariant,
                      )),
                ),
            ]),
          ),
        ),

        // —— 翻译 / 罗马音开关 ——
        SwitchListTile(
          title: const Text('显示翻译', style: TextStyle(fontSize: 14)),
          subtitle: const Text('外语歌的译文（源提供时）',
              style: TextStyle(fontSize: 11)),
          value: settings.lyricTranslation,
          onChanged: (v) =>
              ref.read(appSettingsProvider).setLyricPrefs(translation: v),
        ),
        SwitchListTile(
          title: const Text('显示罗马音', style: TextStyle(fontSize: 14)),
          subtitle: const Text('日文歌的罗马音读音（源提供时）',
              style: TextStyle(fontSize: 11)),
          value: settings.lyricRoman,
          onChanged: (v) =>
              ref.read(appSettingsProvider).setLyricPrefs(roman: v),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}