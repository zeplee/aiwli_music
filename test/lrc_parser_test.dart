import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/core/lyric/lrc_parser.dart';

void main() {
  const parser = LrcParser();

  test('plain LRC regression', () {
    final doc = parser.parse('[00:01.00]hello\n[00:03.50]world');
    expect(doc.lines.length, 2);
    expect(doc.lines[0].text, 'hello');
    expect(doc.lines[0].start, const Duration(seconds: 1));
    // end = 下一句 start
    expect(doc.lines[0].end, const Duration(seconds: 3, milliseconds: 500));
    expect(doc.lines[0].words, isEmpty);
    expect(parser.currentIndex(doc, const Duration(seconds: 2)), 0);
    expect(parser.currentIndex(doc, const Duration(seconds: 4)), 1);
  });

  test('enhanced LRC word timeline', () {
    final doc = parser.parse(
        '[00:10.00]<00:10.00>你 <00:10.50>好 <00:11.20>呀');
    expect(doc.lines.length, 1);
    final line = doc.lines[0];
    expect(line.words.length, 3);
    expect(line.words[0].text, '你 '); // 保留尾随空格
    expect(line.words[0].start, const Duration(seconds: 10));
    expect(line.words[1].start, const Duration(seconds: 10, milliseconds: 500));
    expect(line.words[1].end, const Duration(seconds: 11, milliseconds: 200));
    expect(line.text, '你 好 呀');
    // 词高亮：10.2s → 第 0 词；10.6s → 第 1 词；11.3s → 第 2 词
    expect(parser.currentWordIndex(line, const Duration(milliseconds: 10200)), 0);
    expect(parser.currentWordIndex(line, const Duration(milliseconds: 10600)), 1);
    expect(parser.currentWordIndex(line, const Duration(milliseconds: 11300)), 2);
    // 行 end 兜底 = +8s（末行），最后词 end = 行 end
    expect(line.words[2].end, line.end);
  });

  test('offset applies via document', () {
    final doc = parser.parse('[offset:500]\n[00:01.00]abc');
    expect(doc.offset, const Duration(milliseconds: 500));
  });

  test('multi timestamp line duplicates', () {
    final doc = parser.parse('[00:01.00][00:05.00]repeat');
    expect(doc.lines.length, 2);
    expect(doc.lines[1].start, const Duration(seconds: 5));
  });
}
