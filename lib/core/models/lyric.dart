class LyricWord {
  const LyricWord({required this.text, required this.start, required this.end});
  final String text;
  final Duration start;
  final Duration end;
}

class LyricLine {
  const LyricLine({
    required this.start,
    required this.end,
    this.text = '',
    this.translation,
    this.words = const [],
  });
  final Duration start;
  final Duration end;
  final String text; // 整行文本（无逐字时用）
  final String? translation; // 翻译行
  final List<LyricWord> words; // 逐字（krc/yrc/lxlyric）
}

class LyricDocument {
  const LyricDocument({required this.lines, this.offset = Duration.zero});
  final List<LyricLine> lines;
  final Duration offset; // 全局偏移
}
