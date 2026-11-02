import '../models/lyric.dart';

/// LRC 解析：单行文本 + 增强 LRC 逐字（`[mm:ss.xx]<mm:ss.xx>字`，A2 扩展）。
class LrcParser {
  const LrcParser();

  static final _lineTagRe =
      RegExp(r'\[(\d+):(\d+)(?:[.:](\d+))?\]');
  static final _wordTagRe =
      RegExp(r'<(\d+):(\d+)(?:[.:](\d+))?>');
  static final _metaTagRe = RegExp(r'^\[(ti|ar|al|by|offset):(.*)\]$');

  Duration _parseTag(RegExpMatch m) {
    final min = int.parse(m.group(1)!);
    final sec = int.parse(m.group(2)!);
    final fracStr = m.group(3) ?? '0';
    final frac = int.parse(fracStr.padRight(2, '0').substring(0, 2));
    return Duration(minutes: min, seconds: sec, milliseconds: frac * 10);
  }

  LyricDocument parse(String raw) {
    final lines = <LyricLine>[];
    var offset = Duration.zero;

    for (final rawLine in raw.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final meta = _metaTagRe.firstMatch(line);
      if (meta != null) {
        if (meta.group(1) == 'offset') {
          offset = Duration(milliseconds: int.tryParse(meta.group(2)!) ?? 0);
        }
        continue;
      }
      final times = _lineTagRe.allMatches(line)
          .where((m) => m.start == 0 || line[m.start - 1] != '<')
          .toList();
      if (times.isEmpty) continue;
      final content =
          line.substring(times.last.end).trim();
      final starts = times.map(_parseTag).toList();

      // 增强 LRC：内容里含 <..> 逐字标签
      final wordTags = _wordTagRe.allMatches(content).toList();
      List<LyricWord> words = const [];
      String text;
      if (wordTags.isNotEmpty) {
        words = _parseWords(content, wordTags);
        text = words.map((w) => w.text).join();
      } else {
        text = content.trim();
      }
      if (text.isEmpty && words.isEmpty) continue;
      for (final start in starts) {
        lines.add(LyricLine(
            start: start,
            end: start + const Duration(seconds: 5),
            text: text,
            words: [
              // 逐字标签是绝对时间戳，直接使用
              for (final w in words)
                LyricWord(text: w.text, start: w.start, end: w.end)
            ]));
      }
    }
    // end = 下一句 start；逐字最后一词 end = 行 end
    lines.sort((a, b) => a.start.compareTo(b.start));
    for (var i = 0; i < lines.length; i++) {
      final nextStart = i + 1 < lines.length
          ? lines[i + 1].start
          : lines[i].start + const Duration(seconds: 8);
      lines[i] = LyricLine(
        start: lines[i].start,
        end: nextStart,
        text: lines[i].text,
        translation: lines[i].translation,
        words: [
          for (var k = 0; k < lines[i].words.length; k++)
            k == lines[i].words.length - 1
                ? LyricWord(
                    text: lines[i].words[k].text,
                    start: lines[i].words[k].start,
                    end: nextStart)
                : lines[i].words[k]
        ],
      );
    }
    return LyricDocument(lines: lines, offset: offset);
  }

  /// 内容按 <..> 标签切词：标签后的文本直到下一标签为该词文本。
  List<LyricWord> _parseWords(String content, List<RegExpMatch> tags) {
    final words = <LyricWord>[];
    for (var i = 0; i < tags.length; i++) {
      final start = _parseTag(tags[i]);
      final from = tags[i].end;
      final to = i + 1 < tags.length ? tags[i + 1].start : content.length;
      var text = content.substring(from, to);
      if (i == tags.length - 1) text = text.trimRight();
      if (i == 0 && content.substring(0, tags[0].start).trim().isNotEmpty) {
        // 标签前的散文本并入首词
        text = '${content.substring(0, tags[0].start).trim()} $text';
      }
      if (text.isEmpty && words.isNotEmpty) continue; // 空片段跳过
      // 保留词内空格：英文逐字若去掉尾随空格会粘连（Hello world → Helloworld）
      words.add(LyricWord(text: text, start: start, end: start));
    }
    // word end = 下一词 start
    return [
      for (var i = 0; i < words.length; i++)
        LyricWord(
          text: words[i].text,
          start: words[i].start,
          end: i + 1 < words.length ? words[i + 1].start : words[i].end,
        )
    ];
  }

  /// 当前应高亮的行下标（二分）。
  int currentIndex(LyricDocument doc, Duration position) {
    final pos = position - doc.offset;
    var lo = 0;
    var hi = doc.lines.length - 1;
    var ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (doc.lines[mid].start <= pos) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  /// 当前行内应高亮的词下标（线性；词数少）。
  int currentWordIndex(LyricLine line, Duration position) {
    if (line.words.isEmpty) return -1;
    final pos = position;
    var ans = -1;
    for (var i = 0; i < line.words.length; i++) {
      if (line.words[i].start <= pos) ans = i;
    }
    return ans;
  }
}
