import '../models/lyric.dart';

/// LRC 解析（M4 基础版：单行文本；逐字格式后续按 §5 扩展）。
class LrcParser {
  const LrcParser();

  LyricDocument parse(String raw) {
    final lines = <LyricLine>[];
    final tagRe = RegExp(r'^\[(ti|ar|al|by|offset):(.*)\]$');
    var offset = Duration.zero;

    for (final rawLine in raw.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final tag = tagRe.firstMatch(line);
      if (tag != null) {
        if (tag.group(1) == 'offset') {
          offset = Duration(milliseconds: int.tryParse(tag.group(2)!) ?? 0);
        }
        continue;
      }
      // 支持一行多个时间标签 [00:01.00][00:05.00]text
      final times = RegExp(r'\[(\d+):(\d+)(?:[.:](\d+))?\]').allMatches(line);
      if (times.isEmpty) continue;
      final text = line.replaceAll(RegExp(r'\[[^\]]*\]'), '').trim();
      for (final t in times) {
        final min = int.parse(t.group(1)!);
        final sec = int.parse(t.group(2)!);
        final fracStr = t.group(3) ?? '0';
        final frac = int.parse(fracStr.padRight(2, '0').substring(0, 2));
        final start = Duration(minutes: min, seconds: sec, milliseconds: frac * 10);
        lines.add(LyricLine(start: start, end: start + const Duration(seconds: 5), text: text));
      }
    }
    // end = 下一句 start
    for (var i = 0; i < lines.length; i++) {
      final nextStart = i + 1 < lines.length ? lines[i + 1].start : lines[i].start + const Duration(seconds: 8);
      lines[i] = LyricLine(
        start: lines[i].start,
        end: nextStart,
        text: lines[i].text,
        translation: lines[i].translation,
        words: lines[i].words,
      );
    }
    lines.sort((a, b) => a.start.compareTo(b.start));
    return LyricDocument(lines: lines, offset: offset);
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
}
