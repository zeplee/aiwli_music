import 'dart:convert';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/models/quality.dart';
import '../../core/ui/cover_palette.dart';
import '../../player/models.dart';
import 'lyric_settings.dart';
import 'lyrics_view.dart';
import '../../player/player_core.dart';
import 'player_extras.dart';
import '../library/playlist_pages.dart';
import '../../core/services/playlists.dart';

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key});

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  /// 上一次已提示过的错误（同一错误不重复弹 SnackBar）。
  Object? _lastShownError;

  /// 当前封面提取出的主色（动态主题）；null 时用主题默认色。
  Color? _coverColor;
  String? _paletteKey;

  /// 封面变化时重新取色（用 key 去重，避免每帧重算）。
  void _syncPalette(String? artUrl) {
    if (artUrl == _paletteKey) return;
    _paletteKey = artUrl;
    if (artUrl == null || artUrl.isEmpty) {
      if (_coverColor != null) setState(() => _coverColor = null);
      return;
    }
    CoverPalette.extract(artUrl).then((c) {
      if (!mounted || artUrl != _paletteKey) return;
      if (c != null) setState(() => _coverColor = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    final core = ref.watch(playerCoreProvider);
    final playlists = ref.watch(playlistsProvider);
    final settings = ref.watch(appSettingsProvider);
    final sleep = ref.watch(sleepTimerProvider);
    final scheme = Theme.of(context).colorScheme;
    final item = core.current;
    // 是否已在任一歌单中（仅用于图标状态提示，不再有"收藏"概念）
    final inAnyPlaylist = item != null &&
        playlists.playlists.any((p) => p.entries.any(
            (e) => e.sourceId == item.sourceId && e.musicId == item.musicId));

    return CallbackShortcuts(
      bindings: {
        // Space：播放/暂停
        const SingleActivator(LogicalKeyboardKey.space): () {
          final st = core.state.value;
          st.playing ? core.pause() : core.play();
        },
        // ← / →：快退/快进 5s
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          final target = core.state.value.position - const Duration(seconds: 5);
          core.seek(target.isNegative ? Duration.zero : target);
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          final cur = core.state.value;
          final dur = cur.duration ?? Duration.zero;
          final target = cur.position + const Duration(seconds: 5);
          core.seek(target > dur ? dur : target);
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          // 透明底：背景由 _CoverBackdrop 负责画到全屏。
          // 不设的话 Scaffold 会用主题 surface（浅色主题=白色），
          // 任何没被背景覆盖到的缝隙都会露出白边。
          backgroundColor: Colors.transparent,
          // 背景必须铺满到状态栏下：SafeArea 只约束「内容」，
          // 不能包住背景层。否则 Positioned.fill 也被限制在 SafeArea 内，
          // 状态栏那条没人绘制 → 露出 Scaffold 默认底色
          // （浅色主题下就是用户看到的那条白条）。
          body: ValueListenableBuilder<PlayerUiState>(
          valueListenable: core.state,
          builder: (context, s, _) {
            // 错误提示分两级，避免"已在播还挂红条"的干扰：
            //
            //   换源中/中途 error → 不弹任何东西。界面本身已有
            //     "正在获取播放地址…"，用户能看到它在努力。
            //   真失败（processing=error）→ 才弹红条。
            //
            // 之前只要 s.error 非空就弹，而换源过程会短暂带 error，
            // 于是换源成功后红条仍要挂满 3 秒——观感很差。
            final isRealFailure =
                s.error != null && s.processing == EngineProcessing.error;
            if (isRealFailure && s.error != _lastShownError) {
              _lastShownError = s.error;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final messenger = ScaffoldMessenger.maybeOf(context);
                messenger
                  ?..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(
                    // 不复述 mpv 英文原文，给用户能理解的说法
                    content: const Text('这首歌暂时播不了，换源后仍无法播放'),
                    duration: const Duration(seconds: 3),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Theme.of(context).colorScheme.error,
                    // floating SnackBar 默认贴底，会盖住播放控制栏
                    // （真机截图确认：暂停按钮下半截被遮）。
                    // 往上抬 96 让出控制行 + 安全区。
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  ));
              });
            }
            // 恢复播放后重置去重标记：下次真失败仍要能弹出
            if (s.error == null && s.playing) _lastShownError = null;
            // 封面变化 → 重新提取主色（动态主题 + 背景模糊）
            _syncPalette(item?.artUri?.toString());

            final duration =
                s.duration ?? const Duration(minutes: 3, seconds: 30);
            final pos = s.position <= duration ? s.position : duration;
            // 动态主题色：取到封面主色就用它，否则回退到主题默认
            final accent = _coverColor ?? scheme.primary;
            return Stack(
              children: [
                // 封面模糊背景 + 主色渐变（规格 §2.4「播放页背景」）
                Positioned.fill(
                  child: _CoverBackdrop(
                    artUrl: item?.artUri?.toString(),
                    accent: accent,
                  ),
                ),
                // 内容区才需要避让状态栏/刘海；背景层已经铺满全屏
                SafeArea(
                  child: Padding(
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
                  // 倍速：非 1x 时高亮（一眼看出当前是变速播放）。
                  //
                  // 点击区必须撑到 48dp：原来只有 61x33，夹在两个 48dp 的
                  // IconButton 中间，实测很难点中（Material 最小触控标准
                  // 是 48x48）。用 minWidth/minHeight 保证，而不是加大
                  // padding——后者会让文字周围留白过多、和图标不对齐。
                  InkWell(
                    onTap: () => showSpeedSheet(context),
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      child: Center(
                        widthFactor: 1,
                        heightFactor: 1,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
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
                        case 'lyric':
                          showLyricSettingsSheet(context);
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
                        value: 'lyric',
                        child: Row(children: [
                          Icon(Icons.text_fields,
                              size: 18, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 10),
                          const Text('歌词设置（字号 / 翻译）'),
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
                  // 「添加到歌单」（取代原爱心按钮）。
                  // lx 与栖弦都没有"收藏"这个概念，只有歌单；
                  // 若已在任一歌单里，图标高亮提示。
                  IconButton(
                    tooltip: '添加到歌单',
                    onPressed: item == null
                        ? null
                        : () => showAddToPlaylistSheet(context, ref, item.toEntry()),
                    icon: Icon(
                      inAnyPlaylist
                          ? Icons.playlist_add_check
                          : Icons.playlist_add,
                      color: inAnyPlaylist
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
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
                // 上半区：窄屏=三页滑动；宽屏(>900)=左封面 + 右歌词/评论分栏
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      if (c.maxWidth <= 900) {
                        return _PlayerTabs(item: item);
                      }
                      return Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: _WideCoverPane(item: item),
                          ),
                          const VerticalDivider(width: 24),
                          Expanded(
                            flex: 5,
                            child: _PlayerTabs(
                              item: item,
                              wideMode: true,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                _SeekBar(
                  position: pos,
                  duration: duration,
                  // 缓冲进度来自引擎快照（media_kit buffer 流）
                  buffered: s.buffered,
                  enabled: s.processing != EngineProcessing.loading &&
                      s.processing != EngineProcessing.buffering,
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
                // 加载提示：固定高度占位，出现/消失不推挤布局
                // （之前是条件插入 Row，导致整个页面上下伸缩）
                SizedBox(
                  height: 24,
                  child: (s.processing == EngineProcessing.loading ||
                          s.processing == EngineProcessing.buffering)
                      ? Row(
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
                        )
                      : null,
                ),
                const SizedBox(height: 4),
                    ]),
                  ),
                ),
              ],
            );
          },
        ),
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
  const _SeekBar({
    required this.position,
    required this.duration,
    required this.onChanged,
    this.buffered = Duration.zero,
    this.enabled = true,
  });
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  /// 与 SliderTheme 里 thumbShape 的半径保持一致。
  static const double _thumbRadius = 6;

  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final max = widget.duration.inMilliseconds.toDouble();
    final value = _dragValue ?? widget.position.inMilliseconds.toDouble();
    final bufferedRatio = max <= 0
        ? 0.0
        : (widget.buffered.inMilliseconds / max).clamp(0.0, 1.0);
    final dragging = _dragValue != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 拖动时的时间气泡：拖动过程只更新预览，松手才真正 seek
        SizedBox(
          height: 20,
          child: dragging
              ? Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _fmt(Duration(milliseconds: _dragValue!.round())),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: scheme.onPrimaryContainer),
                    ),
                  ),
                )
              : null,
        ),
        // 轨道必须铺满整行、滑块中心能到达两端。
        //
        // Flutter Slider 默认给左右各留一个「thumb 宽度」的 padding
        // （SliderTheme.padding 的文档写明：horizontal padding defaults to
        // the width of the thumb shape）。于是：
        //   · value=0 时滑块停在离左端一个 thumb 宽的位置 → 圆不在最开头
        //   · 拖到最左也只是到那个 padding 边界 → 拖不到 0
        // 用户反馈的两个症状都源于此。
        //
        // 修法：显式 padding=0 + 自定义 trackShape 铺满，
        // 并让 thumb 用较小半径，避免 padding=0 时圆头被裁掉。
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            padding: EdgeInsets.zero,
            trackHeight: 3,
            trackShape: const _FullWidthTrackShape(),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 缓冲进度：与轨道同宽，避免两套宽度错位
              if (bufferedRatio > 0.001)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: _thumbRadius),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: bufferedRatio,
                      minHeight: 3,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation(
                          scheme.onSurface.withValues(alpha: 0.22)),
                    ),
                  ),
                ),
              Slider(
                value: value.clamp(0, max <= 0 ? 1 : max),
                max: max <= 0 ? 1 : max,
                // 加载中禁用拖动（规格 §2.2）
                onChanged: widget.enabled && max > 0
                    ? (v) => setState(() => _dragValue = v)
                    : null,
                onChangeEnd: (v) {
                  widget.onChanged(v);
                  setState(() => _dragValue = null);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// 播放页上半区：封面 / 歌词 / 评论，左右滑动切换（PageView），
/// 页面指示点同步高亮；底部操作区不受影响。
class _PlayerTabs extends ConsumerStatefulWidget {
  const _PlayerTabs({required this.item, this.wideMode = false});
  final PlayerItem? item;

  /// 宽屏模式：封面已由左侧栏独立展示，这里只保留 歌词 / 评论 两页。
  final bool wideMode;

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
    // children 数量必须在拖动全程稳定。
    //
    // 真机取证：拖动中途切歌 → item 变化 → 页数 3→1 → Scrollable 重建
    // → ScrollDragController.update 打到已失效的 activity →
    // 「activity!.isScrolling」断言失败 → 整页白屏。
    // 因此封面页永远保留，只是没有歌曲时渲染占位（见 _coverPage）。
    final pages = widget.wideMode
        ? <Widget>[
            const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(20)),
              child: LyricsPanel(compact: false),
            ),
            const _CommentsPage(),
          ]
        : <Widget>[
            _coverPage(scheme),
            const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(20)),
              child: LyricsPanel(compact: false),
            ),
            const _CommentsPage(),
          ];
    return SizedBox.expand(
      child: Column(children: [
        Expanded(
          child: PageView(
            controller: _controller,
            onPageChanged: (i) => setState(() {
              // 页数可能因宽屏切换而变化，夹住避免指示点越界
              _index = i.clamp(0, pages.length - 1);
            }),
            children: pages,
          ),
        ),
        const SizedBox(height: 10),
        // 页面指示点
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < pages.length; i++)
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
        child: (item?.artBytes?.isNotEmpty ?? false)
            ? ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.memory(
                  item!.artBytes!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => Icon(Icons.graphic_eq,
                      size: 60,
                      color: Colors.white.withValues(alpha: 0.85)),
                ),
              )
            : item?.artUri != null
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
          Text(state.error == null || state.error!.isEmpty
              ? '暂无评论'
              : '评论加载失败 · 换个音源试试',
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

/// 宽屏左栏封面（桌面/平板横屏）：封面独立展示，点击弹操作菜单。
class _WideCoverPane extends ConsumerWidget {
  const _WideCoverPane({required this.item});
  final PlayerItem? item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final art = item?.artUri;
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: item == null
              ? null
              : () => _showCoverActions(context, ref, item!, () {}),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, const Color(0xFF8B5CF6), scheme.tertiary],
              ),
            ),
            child: (item?.artBytes?.isNotEmpty ?? false)
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.memory(
                      item!.artBytes!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => Icon(Icons.graphic_eq,
                          size: 72,
                          color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  )
                : art != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.network(
                          art.toString(),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(Icons.graphic_eq,
                              size: 72,
                              color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      )
                    : Icon(Icons.graphic_eq,
                        size: 72,
                        color: Colors.white.withValues(alpha: 0.85)),
          ),
        ),
      ),
    );
  }
}

/// 播放页背景：封面高斯模糊 + 主色渐变遮罩。
/// 无封面时退化为纯主色渐变（不留空白）。
class _CoverBackdrop extends StatelessWidget {
  const _CoverBackdrop({required this.artUrl, required this.accent});
  final String? artUrl;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasArt = artUrl != null && artUrl!.isNotEmpty;
    final veil = PlayerBackdropVeil.of(
      brightness: scheme.brightness,
      hasArt: hasArt,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        // 底层：主色铺底（无封面时也不留空白）
        // 无封面时铺底要更实：否则整页只剩"白纸 + 一点点色"，
        // 顶部看上去就是一条白带。
        ColoredBox(
          color: Color.alphaBlend(
            accent.withValues(alpha: hasArt ? 0.10 : 0.34),
            scheme.surface,
          ),
        ),

        // 封面大幅模糊（参考栖弦 ImmersiveBackground：整块封面糊成色块背景）
        if (hasArt)
          ImageFiltered(
            imageFilter: ImageFilter.blur(
                sigmaX: 64, sigmaY: 64, tileMode: TileMode.decal),
            child: Image.network(
              artUrl!,
              fit: BoxFit.cover,
              // 封面色块放大铺满，避免边缘露出黑边
              alignment: Alignment.center,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),

        // 主色光晕：左上浓、右下淡，让背景有方向感而不是均匀灰
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.7, -0.8),
              radius: 1.5,
              colors: [
                accent.withValues(alpha: 0.34),
                Colors.transparent,
              ],
            ),
          ),
        ),
        // 对侧补一层次色，避免单色单调
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.8, 0.9),
              radius: 1.3,
              colors: [
                scheme.tertiary.withValues(alpha: 0.22),
                Colors.transparent,
              ],
            ),
          ),
        ),

        // 可读性遮罩：保证前景文字对比度（封面再花也不影响阅读）。
        //
        // 强度必须随主题亮度调整：
        //   深色主题 surface≈近黑 → 74% 遮罩只是压暗，背景色仍透得出来
        //   浅色主题 surface=纯白 → 74% 遮罩等于糊了一层白纸，
        //   顶部变成一条难看的白带（用户反馈的「播放页顶部白条」）
        // 所以浅色主题下把 alpha 降低，让封面主色能透上来。
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scheme.surface.withValues(alpha: veil.top),
                scheme.surface.withValues(alpha: veil.mid),
                scheme.surface.withValues(alpha: veil.bottom),
              ],
            ),
          ),
        ),
      ],
    );
  }
}


/// 播放页背景「可读性遮罩」的三档不透明度。
///
/// 强度必须同时考虑**主题亮度**与**有没有封面**：
///
///   · 有封面：需要足够遮罩压住花哨图案，保证前景文字可读
///   · 无封面：底下只有一层主色铺底，遮罩越强越是糊成一张白纸
///     —— 实测封面回填仅命中 27/1504，绝大多数歌曲都走这条路，
///     这正是"播放页顶部一条白带"的真正成因（不是布局问题，
///     背景确实铺满了，只是被白色遮罩糊掉了）。
///
/// 浅色主题的 surface 是纯白，同样的 alpha 比深色主题更具破坏性，
/// 所以浅色一律更低。
@immutable
class PlayerBackdropVeil {
  const PlayerBackdropVeil({
    required this.top,
    required this.mid,
    required this.bottom,
  });

  final double top;
  final double mid;
  final double bottom;

  factory PlayerBackdropVeil.of({
    required Brightness brightness,
    required bool hasArt,
  }) {
    final isLight = brightness == Brightness.light;
    if (hasArt) {
      return PlayerBackdropVeil(
        top: isLight ? 0.52 : 0.74,
        mid: isLight ? 0.66 : 0.96,
        bottom: isLight ? 0.80 : 1.0,
      );
    }
    return PlayerBackdropVeil(
      top: isLight ? 0.10 : 0.30,
      mid: isLight ? 0.16 : 0.45,
      bottom: isLight ? 0.28 : 0.72,
    );
  }
}


/// 铺满整行的滑轨：左右各让出半个 thumb 半径，
/// 使「滑块圆心」在 value=0 / value=max 时正好贴到两端。
///
/// Flutter 默认的 RoundedRectSliderTrackShape 会把轨道两端再内缩，
/// 加上 Slider 默认 padding，结果就是拖不到 0（真机反馈）。
class _FullWidthTrackShape extends SliderTrackShape
    with BaseSliderTrackShape {
  const _FullWidthTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final radius = Radius.circular(rect.height / 2);

    // 已播放部分：从左端到滑块圆心
    final active = Rect.fromLTRB(rect.left, rect.top, thumbCenter.dx, rect.bottom);
    // 未播放部分：从滑块圆心到右端
    final inactive =
        Rect.fromLTRB(thumbCenter.dx, rect.top, rect.right, rect.bottom);

    final paintActive = Paint()..color = sliderTheme.activeTrackColor!;
    final paintInactive = Paint()..color = sliderTheme.inactiveTrackColor!;

    context.canvas.drawRRect(
        RRect.fromRectAndRadius(active, radius), paintActive);
    context.canvas.drawRRect(
        RRect.fromRectAndRadius(inactive, radius), paintInactive);
  }
}
