import 'dart:convert';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/models/quality.dart';
import '../../player/models.dart';
import 'lyrics_view.dart';
import '../../player/player_core.dart';
import 'player_extras.dart';
import '../library/playlist_pages.dart';
import '../../core/services/playlists.dart';

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
                  // 播放队列：最常用，单独留一个入口
                  IconButton(
                    tooltip: '播放队列',
                    onPressed: () => showQueueSheet(context),
                    icon: Icon(Icons.queue_music,
                        color: scheme.onSurfaceVariant),
                  ),
                  // 倍速：非 1x 时高亮（一眼看出当前是变速播放）
                  InkWell(
                    onTap: () => showSpeedSheet(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 8),
                      child: Text(
                        s.speed == 1.0 ? '1.0x' : '${_fmtRate(s.speed)}x',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: s.speed == 1.0
                                ? scheme.onSurfaceVariant
                                : scheme.primary),
                      ),
                    ),
                  ),
                  // 其余低频操作收进「更多」，避免顶栏 6 个图标挤成一排
                  PopupMenuButton<String>(
                    tooltip: '更多',
                    icon: Icon(Icons.more_horiz,
                        color: scheme.onSurfaceVariant),
                    onSelected: (v) {
                      switch (v) {
                        case 'sleep':
                          showSleepTimerSheet(context);
                        case 'eq':
                          showEqSheet(context);
                        case 'quality':
                          showQualitySheet(context);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'sleep',
                        child: Row(children: [
                          Icon(Icons.bedtime_outlined,
                              size: 18,
                              color: sleep.active
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant),
                          const SizedBox(width: 10),
                          Text(sleep.active ? '定时关闭 · 已开启' : '定时关闭'),
                        ]),
                      ),
                      PopupMenuItem(
                        value: 'eq',
                        child: Row(children: [
                          Icon(Icons.equalizer,
                              size: 18,
                              color: settings.eqEnabled
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant),
                          const SizedBox(width: 10),
                          Text(settings.eqEnabled ? '均衡器 · 已开启' : '均衡器'),
                        ]),
                      ),
                      PopupMenuItem(
                        value: 'quality',
                        child: Row(children: [
                          Icon(Icons.high_quality,
                              size: 18, color: scheme.primary),
                          const SizedBox(width: 10),
                          Text('音质：${settings.quality.label}'),
                        ]),
                      ),
                    ],
                  ),
                  IconButton(
                    tooltip: isFav ? '已收藏 · 点击取消' : '收藏到「我的收藏」',
                    onPressed: item == null
                        ? null
                        : () => favorites.toggle(
                              sourceId: item.sourceId,
                              musicId: item.musicId,
                              title: item.title,
                              artist: item.artist,
                              album: item.album,
                              picUrl: item.artUri?.toString(),
                              durationMs: item.duration?.inMilliseconds,
                            ),
                    icon: Icon(
                      isFav ? Icons.favorite : Icons.favorite_border,
                      color: isFav ? scheme.error : scheme.onSurfaceVariant,
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                // 标题/歌手贴顶（不再挤在 Tab 中间浪费视觉空间）
                Text(s.title.isEmpty ? '未在播放' : s.title,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(s.artist,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                // 上半区三页：封面 / 歌词 / 评论（左右滑动，撑满剩余空间）
                Expanded(child: _PlayerTabs(item: item)),
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


  /// 1.25 → 1.25, 1.50 → 1.5, 0.75 → 0.75
  static String _fmtRate(double v) {
    final t = v.toStringAsFixed(2);
    if (t.endsWith('0')) return t.substring(0, t.length - 1);
    return t;
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

/// 播放页上半区：封面 / 歌词 / 评论，左右滑动切换（PageView），
/// 页面指示点同步高亮；底部操作区不受影响。
class _PlayerTabs extends ConsumerStatefulWidget {
  const _PlayerTabs({required this.item});
  final PlayerItem? item;

  @override
  ConsumerState<_PlayerTabs> createState() => _PlayerTabsState();
}

class _PlayerTabsState extends ConsumerState<_PlayerTabs> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.expand(
      child: Column(children: [
        Expanded(
          child: PageView(
            controller: _controller,
            onPageChanged: (i) => setState(() => _index = i),
            children: [
              _coverPage(scheme),
              const ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(20)),
                child: LyricsPanel(compact: false),
              ),
              const _CommentsPage(),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // 页面指示点
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < 3; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _index == i ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: _index == i ? scheme.primary : scheme.onSurfaceVariant,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _coverPage(ColorScheme scheme) {
    final item = widget.item;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      // 封面点击 = 当前歌曲操作菜单（对齐参考工程 player_cover_actions_sheet）
      onTap: item == null
          ? null
          : () => _showCoverActions(context, ref, item, () {
                _controller.animateToPage(1,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut);
              }),
      child: Container(
        width: double.infinity,
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
        child: item?.artUri != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.network(
                  item!.artUri.toString(),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Icon(Icons.graphic_eq,
                      size: 60,
                      color: Colors.white.withValues(alpha: 0.85)),
                ),
              )
            : Icon(Icons.graphic_eq,
                size: 60, color: Colors.white.withValues(alpha: 0.85)),
      ),
    );
  }
}

/// 封面操作菜单：添加到歌单 / 下载 / 切换音质 / 跳到歌词页。
/// 对齐参考工程动作集（playlist_add / download / high_quality / subtitles）。
Future<void> _showCoverActions(BuildContext context, WidgetRef ref,
    PlayerItem item, VoidCallback onOpenLyrics) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                Text(item.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text('添加到歌单'),
            subtitle: const Text('选择歌单并加入当前歌曲'),
            onTap: () {
              Navigator.of(ctx).pop();
              showAddToPlaylistSheet(
                context,
                ref,
                PlaylistEntry(
                  sourceId: item.sourceId,
                  musicId: item.musicId,
                  title: item.title,
                  artist: item.artist,
                  album: item.album,
                  durationMs: item.duration?.inMilliseconds,
                  rawJson: item.raw == null
                      ? null
                      : jsonEncode(item.raw!.cast<String, Object?>()),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('下载当前歌曲'),
            subtitle: Text(item.sourceId == 'local'
                ? '本地歌曲无需下载'
                : '选择音质并下载当前在线歌曲'),
            enabled: item.sourceId != 'local',
            onTap: () {
              Navigator.of(ctx).pop();
              ref.read(downloadManagerProvider).start(item);
            },
          ),
          ListTile(
            leading: const Icon(Icons.high_quality),
            title: const Text('切换播放音质'),
            onTap: () {
              Navigator.of(ctx).pop();
              showQualitySheet(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.lyrics_outlined),
            title: const Text('查看歌词'),
            onTap: () {
              Navigator.of(ctx).pop();
              onOpenLyrics();
            },
          ),
          const SizedBox(height: 8),
        ]),
      );
    },
  );
}

/// 评论页：内置多平台评论（网易热评），切歌自动拉取。
class _CommentsPage extends ConsumerStatefulWidget {
  const _CommentsPage();
  @override
  ConsumerState<_CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends ConsumerState<_CommentsPage> {
  String? _key;

  @override
  Widget build(BuildContext context) {
    final core = ref.watch(playerCoreProvider);
    final item = core.current;
    final scheme = Theme.of(context).colorScheme;

    if (item != null) {
      final k = '${item.sourceId}/${item.musicId}';
      if (k != _key) {
        _key = k;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(commentServiceProvider).fetchFor(
                  item.sourceId, item.musicId,
                  title: item.title, artist: item.artist);
          }
        });
      }
    }

    final state = ref.watch(commentServiceProvider).current;
    Widget body;
    if (state.loading) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(height: 10),
          Text('评论加载中…',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ]),
      );
    } else if (state.items.isEmpty) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.chat_bubble_outline,
              size: 36, color: scheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(state.error ?? '暂无评论',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        ]),
      );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: state.items.length,
        separatorBuilder: (_, _) => const Divider(height: 16),
        itemBuilder: (context, i) {
          final c = state.items[i];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                  radius: 11,
                  backgroundColor: scheme.primaryContainer,
                  child: Text(c.user.isEmpty ? '?' : c.user.characters.first,
                      style: TextStyle(
                          fontSize: 11, color: scheme.onPrimaryContainer)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(c.user,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant)),
                ),
                Icon(Icons.favorite, size: 11, color: scheme.outline),
                const SizedBox(width: 3),
                Text('${c.likedCount}',
                    style: TextStyle(fontSize: 11, color: scheme.outline)),
              ]),
              const SizedBox(height: 4),
              Text(c.content,
                  style: const TextStyle(fontSize: 13, height: 1.35)),
            ],
          );
        },
      );
    }
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      child: Container(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
          child: body),
    );
  }
}
