import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/ui/cover_image.dart';
import '../../player/models.dart';
import '../player/player_page.dart';

/// 全局快捷播放条（唯一实现）。
///
/// 之前「音乐库」和「我的」页各写了一份，样式与能力不一致：
///   · 音乐库版：有进度、有下一首，但点不动
///   · 我的版：能跳转，但没进度、没切歌
/// 现在统一成这一份，放在 HomeShell 底部，三个 Tab 共用。
///
/// 能力：封面 + 标题歌手 + 进度 + 播放/暂停 + 下一首 + 点击进播放页。
class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final core = ref.watch(playerCoreProvider);
    final scheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder<PlayerUiState>(
      valueListenable: core.state,
      builder: (context, s, _) {
        if (s.title.isEmpty) return const SizedBox.shrink();

        final duration = s.duration ?? Duration.zero;
        final progress = duration.inMilliseconds <= 0
            ? 0.0
            : (s.position.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0);

        return Material(
          color: scheme.surfaceContainerHighest,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PlayerPage())),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // 顶部细进度线：一眼看出播到哪
              LinearProgressIndicator(
                value: progress,
                minHeight: 2,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation(scheme.primary),
              ),
              // 高度固定为 56：IconButton 默认 48 + 上下 padding 会溢出 4px
              // （真机日志确认 "RenderFlex overflowed by 4.0 pixels"）。
              SizedBox(
                height: 56,
                child: Row(children: [
                  const SizedBox(width: 12),
                  CoverImage(
                    bytes: core.current?.artBytes,
                    url: core.current?.artUri?.toString(),
                    size: 40,
                    radius: 6,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                        Text(
                          '${s.artist} · ${_fmt(s.position)} / ${_fmt(duration)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  // 紧凑按钮：默认 IconButton 是 48x48，会在 56 高的行里
                  // 加上 Material 内边距导致底部溢出。
                  IconButton(
                    tooltip: s.playing ? '暂停' : '播放',
                    onPressed: () => s.playing ? core.pause() : core.play(),
                    icon: Icon(s.playing ? Icons.pause : Icons.play_arrow),
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 40),
                    padding: EdgeInsets.zero,
                  ),
                  IconButton(
                    tooltip: '下一首',
                    onPressed: core.next,
                    icon: const Icon(Icons.skip_next),
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 40),
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(width: 4),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$sec';
  }
}