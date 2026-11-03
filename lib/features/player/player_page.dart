import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/models/quality.dart';
import '../../player/models.dart';
import 'lyrics_view.dart';
import 'player_extras.dart';

class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final core = ref.watch(playerCoreProvider);
    final favorites = ref.watch(favoritesProvider);
    final settings = ref.watch(appSettingsProvider);
    final sleep = ref.watch(sleepTimerProvider);
    final scheme = Theme.of(context).colorScheme;
    final item = core.current;
    final isFav =
        item != null && favorites.isFavorite(item.sourceId, item.musicId);

    return Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder<PlayerUiState>(
          valueListenable: core.state,
          builder: (context, s, _) {
            final duration =
                s.duration ?? const Duration(minutes: 3, seconds: 30);
            final pos = s.position <= duration ? s.position : duration;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(children: [
                Row(children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.keyboard_arrow_down, size: 30),
                  ),
                  const Spacer(),
                  // 定时关闭
                  IconButton(
                    tooltip: '定时关闭',
                    onPressed: () => showSleepTimerSheet(context),
                    icon: Icon(Icons.bedtime_outlined,
                        color: sleep.active
                            ? scheme.primary
                            : scheme.onSurfaceVariant),
                  ),
                  // 均衡器
                  IconButton(
                    tooltip: '均衡器',
                    onPressed: () => showEqSheet(context),
                    icon: Icon(Icons.equalizer,
                        color: settings.eqEnabled
                            ? scheme.primary
                            : scheme.onSurfaceVariant),
                  ),
                  // 音质档位
                  InkWell(
                    onTap: () => showQualitySheet(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: Text(settings.quality.label,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: scheme.primary)),
                    ),
                  ),
                  IconButton(
                    tooltip: isFav ? '取消收藏' : '收藏',
                    onPressed: item == null
                        ? null
                        : () => favorites.toggle(
                              sourceId: item.sourceId,
                              musicId: item.musicId,
                              title: item.title,
                              artist: item.artist,
                              album: item.album,
                              durationMs: item.duration?.inMilliseconds,
                            ),
                    icon: Icon(
                      isFav ? Icons.favorite : Icons.favorite_border,
                      color: isFav ? scheme.error : scheme.onSurfaceVariant,
                    ),
                  ),
                ]),
                const Spacer(flex: 2),
                Container(
                  width: double.infinity,
                  height: 180,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        scheme.primary,
                        const Color(0xFF8B5CF6),
                        scheme.tertiary,
                      ],
                    ),
                  ),
                  child: Icon(Icons.graphic_eq,
                      size: 60, color: Colors.white.withValues(alpha: 0.85)),
                ),
                const Spacer(),
                Text(s.title.isEmpty ? '未在播放' : s.title,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(s.artist,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                // 逐字歌词面板（点击展开全屏歌词）
                SizedBox(height: 84, child: LyricsPanel(compact: true)),
                _SeekBar(
                  position: pos,
                  duration: duration,
                  onChanged: (v) =>
                      core.seek(Duration(milliseconds: v.round())),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_fmt(pos),
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 12)),
                    Text(_fmt(duration),
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  IconButton(
                    onPressed: () {
                      final nextMode = switch (s.repeatMode) {
                        RepeatMode.off => RepeatMode.all,
                        RepeatMode.all => RepeatMode.one,
                        RepeatMode.one => RepeatMode.off,
                      };
                      core.setRepeat(nextMode);
                    },
                    icon: Icon(
                      switch (s.repeatMode) {
                        RepeatMode.off => Icons.repeat,
                        RepeatMode.all => Icons.repeat,
                        RepeatMode.one => Icons.repeat_one,
                      },
                      color: s.repeatMode == RepeatMode.off
                          ? scheme.onSurfaceVariant
                          : scheme.primary,
                    ),
                  ),
                  IconButton(
                      onPressed: core.previous,
                      icon: const Icon(Icons.skip_previous, size: 36)),
                  _PlayPauseButton(playing: s.playing),
                  IconButton(
                      onPressed: () => core.next(),
                      icon: const Icon(Icons.skip_next, size: 36)),
                  IconButton(
                    onPressed: () => core.setShuffle(!s.shuffleOn),
                    icon: Icon(Icons.shuffle,
                        color: s.shuffleOn
                            ? scheme.primary
                            : scheme.onSurfaceVariant),
                  ),
                ]),
                // 取链/加载中提示：切歌后可能等待数秒，必须让用户看到进度
                if (s.processing == EngineProcessing.loading ||
                    s.processing == EngineProcessing.buffering)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: scheme.primary),
                        ),
                        const SizedBox(width: 8),
                        Text('正在获取播放地址…',
                            style: TextStyle(
                                color: scheme.primary, fontSize: 12)),
                      ],
                    ),
                  ),
                if (s.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('${s.error}',
                        style: TextStyle(color: scheme.error, fontSize: 12),
                        textAlign: TextAlign.center,
                        maxLines: 3),
                  ),
                const SizedBox(height: 12),
              ]),
            );
          },
        ),
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _PlayPauseButton extends ConsumerWidget {
  const _PlayPauseButton({required this.playing});
  final bool playing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final core = ref.watch(playerCoreProvider);
    return InkWell(
      onTap: () => playing ? core.pause() : core.play(),
      customBorder: const CircleBorder(),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
            shape: BoxShape.circle, color: Theme.of(context).colorScheme.primary),
        child: Icon(
          playing ? Icons.pause : Icons.play_arrow,
          size: 40,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
    );
  }
}

class _SeekBar extends StatefulWidget {
  const _SeekBar(
      {required this.position,
      required this.duration,
      required this.onChanged});
  final Duration position;
  final Duration duration;
  final ValueChanged<double> onChanged;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final max = widget.duration.inMilliseconds.toDouble();
    final value = _dragValue ?? widget.position.inMilliseconds.toDouble();
    return Slider(
      value: value.clamp(0, max),
      max: max <= 0 ? 1 : max,
      onChanged: (v) => setState(() => _dragValue = v),
      onChangeEnd: (v) {
        widget.onChanged(v);
        _dragValue = null;
      },
    );
  }
}
