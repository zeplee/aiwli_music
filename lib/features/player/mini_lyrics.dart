import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/lyric/lrc_parser.dart';

/// 封面页左下角的迷你歌词（三行，当前行清晰、上下行淡出）。
///
/// 对应的参考实现是栖弦的 `MiniLyricsPanel`：
///   · 只显示当前行 ± 1 行，避免和封面抢视觉
///   · 当前行加粗高亮，上下文行降低不透明度
///   · 点一下直接跳到歌词页
///
/// 为什么默认关闭：封面是播放页的视觉主体，歌词叠上去会分散注意力。
/// 交给用户在「歌词设置」里决定是否开启。
class MiniLyricsPanel extends ConsumerWidget {
  const MiniLyricsPanel({
    super.key,
    required this.onOpenLyrics,
    required this.position,
  });

  /// 点按打开歌词页。
  final VoidCallback onOpenLyrics;

  /// 当前播放位置（由父层 ValueListenableBuilder 传入，避免这里再订阅一次）。
  final Duration position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    if (!settings.showMiniLyrics) return const SizedBox.shrink();

    final lyric = ref.watch(lyricServiceProvider);
    final doc = lyric.current.doc;
    if (doc == null || doc.lines.isEmpty) return const SizedBox.shrink();

    final parser = const LrcParser();
    final idx = parser.currentIndex(doc, position);
    if (idx < 0 || idx >= doc.lines.length) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    // 取当前行与前后各一行（边界处自动收缩）
    final start = (idx - 1).clamp(0, doc.lines.length - 1);
    final end = (idx + 1).clamp(0, doc.lines.length - 1);
    final rows = <Widget>[];
    for (var i = start; i <= end; i++) {
      final active = i == idx;
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
          child: Text(
            doc.lines[i].text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: active
                  ? settings.lyricFontSize * 0.72
                  : settings.lyricFontSize * 0.60,
              height: 1.25,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              // 非当前行降低不透明度：既保留上下文，又不和当前行抢注意力
              color: active
                  ? scheme.onSurface
                  : scheme.onSurfaceVariant.withValues(alpha: 0.62),
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 2),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onOpenLyrics,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: rows,
              ),
            ),
          ),
        ),
      ),
    );
  }
}