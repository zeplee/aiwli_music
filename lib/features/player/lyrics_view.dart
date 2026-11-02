import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/lyric/lrc_parser.dart';
import '../../core/models/lyric.dart';
import '../../player/models.dart';

/// 卡拉OK歌词：紧凑面板（播放页内嵌，当前行逐字染色）+ 点开全屏歌词页。
class LyricsPanel extends ConsumerStatefulWidget {
  const LyricsPanel({required this.compact, super.key});
  final bool compact;

  @override
  ConsumerState<LyricsPanel> createState() => _LyricsPanelState();
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
            ref.read(lyricServiceProvider).fetchFor(item.sourceId, item.musicId);
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
          return Center(
              child: Text('歌词加载中…',
                  style: TextStyle(
                      color: scheme.onSurfaceVariant, fontSize: 13)));
        }
        if (doc == null || doc.lines.isEmpty) {
          return Center(
              child: Text(lyric.current.error ?? '暂无歌词',
                  style: TextStyle(
                      color: scheme.onSurfaceVariant, fontSize: 13)));
        }
        final parser = const LrcParser();
        final idx = parser.currentIndex(doc, s.position);
        if (idx < 0) {
          return Center(
              child: Text('…',
                  style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: widget.compact ? 16 : 20)));
        }
        final line = doc.lines[idx];
        final wordIdx = parser.currentWordIndex(line, s.position);

        if (widget.compact) {
          return InkWell(
            onTap: () => _openFullSheet(context, doc, parser),
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
        return _KaraokeLine(
          line: line,
          wordIndex: wordIdx,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
          unsungColor: scheme.onSurface,
        );
      },
    );
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

class _FullLyricsSheet extends StatefulWidget {
  const _FullLyricsSheet({required this.doc, required this.parser});
  final LyricDocument doc;
  final LrcParser parser;

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
