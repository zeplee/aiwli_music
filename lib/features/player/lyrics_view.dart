import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/lyric/lrc_parser.dart';
import '../../core/models/lyric.dart';
import '../../player/models.dart';

/// 卡拉OK歌词：紧凑面板（播放页内嵌，当前行逐字染色）+ 点开全屏歌词页。
class LyricsPanel extends ConsumerStatefulWidget {
  const LyricsPanel({required this.compact, this.onOpenFull, super.key});
  final bool compact;

  /// 点歌词区域打开全屏歌词页的回调（null = 用默认 sheet）。
  final VoidCallback? onOpenFull;

  @override
  ConsumerState<LyricsPanel> createState() => _LyricsPanelState();
}

/// 歌词空态文案：不把异常原文甩给用户（"SocketException: ... " 这类）。
String _lyricEmptyText(String? error) {
  if (error == null || error.isEmpty) return '暂无歌词 · 点按查看';
  final lower = error.toLowerCase();
  if (lower.contains('timeout') || lower.contains('socket')) {
    return '歌词获取超时 · 点按重试';
  }
  if (lower.contains('404') || lower.contains('not found')) {
    return '这首歌没有歌词 · 点按查看';
  }
  return '暂无歌词 · 点按查看';
}

class _LyricsPanelState extends ConsumerState<LyricsPanel> {
  String? _lastFetchedKey;

  @override
  Widget build(BuildContext context) {
    final lyric = ref.watch(lyricServiceProvider);
    final core = ref.watch(playerCoreProvider);
    final scheme = Theme.of(context).colorScheme;

    // 切歌时拉取歌词（同 key 命中缓存，不重复请求）
    final item = core.current;
    if (item != null &&
        item.sourceId != 'local' &&
        item.sourceId != 'url') {
      final key = '${item.sourceId}/${item.musicId}';
      if (key != _lastFetchedKey) {
        _lastFetchedKey = key;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(lyricServiceProvider).fetchFor(
                  item.sourceId, item.musicId,
                  title: item.title, artist: item.artist);
          }
        });
      }
    } else if (item != null && item.sourceId == 'local') {
      final key = 'local/${item.musicId}';
      if (key != _lastFetchedKey) {
        _lastFetchedKey = key;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref
                .read(lyricServiceProvider)
                .fetchFor('local', item.musicId);
          }
        });
      }
    }

    return ValueListenableBuilder<PlayerUiState>(
      valueListenable: core.state,
      builder: (context, s, _) {
        final doc = lyric.current.doc;
        if (lyric.current.loading) {
          return _tappable(context,
              child: Text('歌词加载中…',
                  style: TextStyle(
                      color: scheme.onSurfaceVariant, fontSize: 13)));
        }
        if (doc == null || doc.lines.isEmpty) {
          return _tappable(context,
              child: Text(_lyricEmptyText(lyric.current.error),
                  style: TextStyle(
                      color: scheme.onSurfaceVariant, fontSize: 13)));
        }
        final parser = const LrcParser();
        final idx = parser.currentIndex(doc, s.position);
        if (idx < 0) {
          return _tappable(context,
              child: Text('…',
                  style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: widget.compact ? 16 : 20)));
        }
        final line = doc.lines[idx];
        final wordIdx = parser.currentWordIndex(line, s.position);

        if (widget.compact) {
          return InkWell(
            onTap: () => _openFull(context, doc, parser),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _KaraokeLine(
                  line: line,
                  wordIndex: wordIdx,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                  unsungColor: scheme.onSurface,
                ),
                if (idx + 1 < doc.lines.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      doc.lines[idx + 1].text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 13),
                    ),
                  ),
              ]),
            ),
          );
        }
        // 非紧凑模式（播放页歌词 Tab）：完整滚动列表 + 翻译/罗马音开关
        final settings = ref.watch(appSettingsProvider);
        return Column(
          children: [
            _LyricAuxBar(
              hasTranslation: lyric.current.hasTranslation,
              hasRoman: lyric.current.hasRoman,
              showTranslation: settings.lyricTranslation,
              showRoman: settings.lyricRoman,
              onToggleTranslation: () => ref
                  .read(appSettingsProvider)
                  .setLyricPrefs(translation: !settings.lyricTranslation),
              onToggleRoman: () => ref
                  .read(appSettingsProvider)
                  .setLyricPrefs(roman: !settings.lyricRoman),
            ),
            Expanded(
              child: _FullLyricsList(
                doc: doc,
                parser: parser,
                position: s.position,
                translation: lyric.current.translation,
                roman: lyric.current.roman,
                showTranslation: settings.lyricTranslation,
                showRoman: settings.lyricRoman,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _tappable(BuildContext context, {required Widget child}) {
    return InkWell(
      onTap: () => _openFull(context, null, null),
      borderRadius: BorderRadius.circular(8),
      child: Center(child: child),
    );
  }

  void _openFull(BuildContext context, LyricDocument? doc, LrcParser? parser) {
    if (widget.onOpenFull != null) {
      widget.onOpenFull!();
      return;
    }
    if (doc == null || parser == null) return;
    _openFullSheet(context, doc, parser);
  }

  void _openFullSheet(
      BuildContext context, LyricDocument doc, LrcParser parser) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FullLyricsSheet(doc: doc, parser: parser),
    );
  }
}

/// 单行卡拉OK：已唱词用主色，未唱词用 unsungColor。
class _KaraokeLine extends StatelessWidget {
  const _KaraokeLine({
    required this.line,
    required this.wordIndex,
    required this.style,
    required this.unsungColor,
  });
  final LyricLine line;
  final int wordIndex; // -1 = 未开唱
  final TextStyle? style;
  final Color unsungColor;

  @override
  Widget build(BuildContext context) {
    if (line.words.isEmpty) {
      return Text(line.text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: style);
    }
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < line.words.length; i++)
            TextSpan(
              text: line.words[i].text,
              style: (style ?? const TextStyle()).copyWith(
                color: i <= wordIndex
                    ? Theme.of(context).colorScheme.primary
                    : unsungColor,
              ),
            ),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );
  }
}

/// 全屏歌词页（公开）：自带数据源，播放中任何状态可打开——
/// 有歌词显示卡拉OK滚动，无歌词/加载中显示空态。
class FullLyricsPage extends ConsumerStatefulWidget {
  const FullLyricsPage({required this.title, required this.artist, super.key});
  final String title;
  final String artist;

  @override
  ConsumerState<FullLyricsPage> createState() => _FullLyricsPageState();
}

class _FullLyricsPageState extends ConsumerState<FullLyricsPage> {
  String? _lastFetchedKey;

  @override
  Widget build(BuildContext context) {
    final lyric = ref.watch(lyricServiceProvider);
    final core = ref.watch(playerCoreProvider);
    final item = core.current;
    if (item != null) {
      final key = '${item.sourceId}/${item.musicId}';
      if (key != _lastFetchedKey) {
        _lastFetchedKey = key;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(lyricServiceProvider).fetchFor(
                  item.sourceId, item.musicId,
                  title: item.title, artist: item.artist);
          }
        });
      }
    }
    final doc = lyric.current.doc;
    if (doc != null && doc.lines.isNotEmpty) {
      return _FullLyricsSheet(
        doc: doc,
        parser: const LrcParser(),
        translation: lyric.current.translation,
        roman: lyric.current.roman,
      );
    }
    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: AppBar(title: Text(widget.title.isEmpty ? '歌词' : widget.title)),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lyrics, size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(lyric.current.loading
                  ? '歌词加载中…'
                  : _lyricEmptyText(lyric.current.error),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 14)),
        ]),
      ),
    );
  }
}

class _FullLyricsSheet extends StatefulWidget {
  const _FullLyricsSheet({
    required this.doc,
    required this.parser,
    this.translation,
    this.roman,
  });
  final LyricDocument doc;
  final LrcParser parser;
  final LyricDocument? translation;
  final LyricDocument? roman;

  @override
  State<_FullLyricsSheet> createState() => _FullLyricsSheetState();
}

class _FullLyricsSheetState extends State<_FullLyricsSheet> {
  final _controller = ScrollController();
  static const _itemExtent = 48.0;
  int _lastIndex = -1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final scheme = Theme.of(context).colorScheme;
      return ValueListenableBuilder<PlayerUiState>(
        valueListenable: ref.watch(playerCoreProvider).state,
        builder: (context, s, _) {
          final doc = widget.doc;
          final idx = widget.parser.currentIndex(doc, s.position);
          if (idx >= 0 && idx != _lastIndex) {
            _lastIndex = idx;
            if (_controller.hasClients) {
              _controller.animateTo(
                (idx - 4).clamp(0, doc.lines.length - 1) * _itemExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          }
          return Container(
            height: MediaQuery.of(context).size.height * 0.82,
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('歌词',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _controller,
                  itemExtent: _itemExtent,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: doc.lines.length,
                  itemBuilder: (context, i) {
                    final active = i == idx;
                    return Center(
                      child: active
                          ? _KaraokeLine(
                              line: doc.lines[i],
                              wordIndex:
                                  widget.parser.currentWordIndex(doc.lines[i], s.position),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                              unsungColor: scheme.onSurface)
                          : Text(doc.lines[i].text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: scheme.onSurfaceVariant, fontSize: 14)),
                    );
                  },
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
            ]),
          );
        },
      );
    });
  }
}

/// 歌词 Tab 的完整滚动列表：当前行逐字高亮 + 自动居中滚动，
/// 可选叠加翻译 / 罗马音（网易源提供）。
class _FullLyricsList extends StatefulWidget {
  const _FullLyricsList({
    required this.doc,
    required this.parser,
    required this.position,
    this.translation,
    this.roman,
    this.showTranslation = true,
    this.showRoman = true,
  });
  final LyricDocument doc;
  final LrcParser parser;
  final Duration position;
  final LyricDocument? translation;
  final LyricDocument? roman;
  final bool showTranslation;
  final bool showRoman;

  @override
  State<_FullLyricsList> createState() => _FullLyricsListState();
}

class _FullLyricsListState extends State<_FullLyricsList> {
  final _controller = ScrollController();
  static const _itemHeight = 56.0;
  int _lastIndex = -1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 按时间戳从译文/罗马音文档取对应行（±200ms 视为同一行）。
  String? _auxText(LyricDocument? aux, int index) {
    if (aux == null || aux.lines.isEmpty) return null;
    final t = widget.doc.lines[index].start;
    for (final a in aux.lines) {
      if ((a.start - t).inMilliseconds.abs() <= 200) return a.text;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final idx = widget.parser.currentIndex(widget.doc, widget.position);
    if (idx >= 0 && idx != _lastIndex) {
      _lastIndex = idx;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients) {
          final target =
              (idx - 3).clamp(0, widget.doc.lines.length - 1) * _itemHeight;
          _controller.animateTo(target,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOut);
        }
      });
    }

    return ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemExtent: _itemHeight,
      itemCount: widget.doc.lines.length,
      itemBuilder: (context, i) {
        final active = i == idx;
        final tr = widget.showTranslation ? _auxText(widget.translation, i) : null;
        final ro = widget.showRoman ? _auxText(widget.roman, i) : null;
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              active
                  ? _KaraokeLine(
                      line: widget.doc.lines[i],
                      wordIndex: widget.parser.currentWordIndex(
                          widget.doc.lines[i], widget.position),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                      unsungColor: scheme.onSurface,
                    )
                  : Text(widget.doc.lines[i].text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 14)),
              if (i == idx && (tr != null || ro != null))
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    [?tr, ?ro].join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 歌词页顶部小工具条：只在源提供译文/罗马音时才显示对应开关，
/// 全无时整条隐藏（不占视觉空间）。
class _LyricAuxBar extends StatelessWidget {
  const _LyricAuxBar({
    required this.hasTranslation,
    required this.hasRoman,
    required this.showTranslation,
    required this.showRoman,
    required this.onToggleTranslation,
    required this.onToggleRoman,
  });
  final bool hasTranslation;
  final bool hasRoman;
  final bool showTranslation;
  final bool showRoman;
  final VoidCallback onToggleTranslation;
  final VoidCallback onToggleRoman;

  @override
  Widget build(BuildContext context) {
    if (!hasTranslation && !hasRoman) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    Widget pill({
      required String label,
      required bool on,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: on ? scheme.primary.withValues(alpha: 0.18) : null,
              border: Border.all(
                  color: on
                      ? scheme.primary.withValues(alpha: 0.55)
                      : scheme.outlineVariant),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: on ? scheme.primary : scheme.onSurfaceVariant)),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 4, bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (hasTranslation)
            pill(
                label: '翻译',
                on: showTranslation,
                onTap: onToggleTranslation),
          if (hasRoman)
            pill(label: '罗马音', on: showRoman, onTap: onToggleRoman),
        ],
      ),
    );
  }
}
