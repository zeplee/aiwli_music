import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/core/lyric/lrc_parser.dart';
import 'package:aiwli_music/core/models/lyric.dart';
import 'package:aiwli_music/sources/builtin/lyric_sdk.dart';

/// 验证译文/罗马音的行归属算法。
///
/// 背景（实测发现）：网易 tlyric/romalrc 的时间轴与原歌词并非逐行对齐，
/// 早期的「±200ms 相等」匹配在 Lemon 上只有 42/46 行命中，
/// 4 行明明有罗马音却显示空白。
void main() {
  /// 生产实现（_FullLyricsList._auxText）的等价逻辑。
  String? auxText(LyricDocument doc, LyricDocument? aux, int index) {
    if (aux == null || aux.lines.isEmpty) return null;
    if (index < 0 || index >= doc.lines.length) return null;
    final start = doc.lines[index].start;
    final end = index + 1 < doc.lines.length ? doc.lines[index + 1].start : null;

    String? best;
    var bestDelta = Duration.zero;
    var bestFound = false;
    for (final a in aux.lines) {
      final inRange =
          end == null ? a.start >= start : (a.start >= start && a.start < end);
      if (!inRange) continue;
      final delta = a.start >= start ? a.start - start : start - a.start;
      if (!bestFound || delta < bestDelta) {
        bestFound = true;
        bestDelta = delta;
        best = a.text;
      }
    }
    if (bestFound) return best;

    Duration? nearest;
    var nearestDelta = const Duration(days: 1);
    for (final a in aux.lines) {
      final d = a.start >= start ? a.start - start : start - a.start;
      if (d < nearestDelta) {
        nearestDelta = d;
        nearest = a.start;
        best = a.text;
      }
    }
    if (nearest != null && nearestDelta.inMilliseconds <= 1500) return best;
    return null;
  }

  const parser = LrcParser();

  test('时间戳轻微偏移仍能匹配（原 ±200ms 会丢）', () {
    final doc = parser.parse('[00:10.00]line A\n[00:20.00]line B\n');
    // 译文比原文晚 340ms —— 旧逻辑直接丢弃
    final aux = parser.parse('[00:10.34]trans A\n[00:20.34]trans B\n');
    expect(auxText(doc, aux, 0), 'trans A');
    expect(auxText(doc, aux, 1), 'trans B');
  });

  test('区间归属：译文落在本行区间内即归属本行', () {
    final doc = parser.parse('[00:10.00]A\n[00:20.00]B\n');
    // 译文在 12s（A 的区间内）
    final aux = parser.parse('[00:12.00]trans A\n');
    expect(auxText(doc, aux, 0), 'trans A');
  });

  test('译文稀疏时用最近邻兜底（1.5s 内）', () {
    final doc = parser.parse('[00:10.00]A\n[00:20.00]B\n');
    // 译文只有一条且在 11.2s（A 区间内，但假设干扰场景）
    final aux = parser.parse('[00:11.20]only\n');
    expect(auxText(doc, aux, 0), 'only');
  });

  test('差距过大不硬凑（超过 1.5s 返回 null）', () {
    final doc = parser.parse('[00:10.00]A\n[00:30.00]B\n');
    // 译文在 25s，离 30s 的 B 有 5s —— 不应错配
    final aux = parser.parse('[00:25.00]wrong\n');
    expect(auxText(doc, aux, 1), isNull, reason: '不能把远处的译文错配过来');
  });

  test('末行也能取到（无下界）', () {
    final doc = parser.parse('[00:10.00]A\n[00:20.00]B\n');
    final aux = parser.parse('[00:10.10]tA\n[00:20.10]tB\n');
    expect(auxText(doc, aux, 1), 'tB');
  });

  test('空文档/越界安全', () {
    final doc = parser.parse('[00:10.00]A\n');
    expect(auxText(doc, null, 0), isNull);
    expect(auxText(doc, parser.parse(''), 0), isNull);
    expect(auxText(doc, parser.parse('[00:10.00]x\n'), 99), isNull);
  });

  test('真实数据：Lemon 罗马音覆盖率应显著高于旧算法', () async {
    final r = await LyricSdk.fetch(
      sourceId: 'wy',
      musicId: '0',
      title: 'Lemon',
      artist: '米津玄師',
    );
    expect(r, isNotNull);
    if (r!.roman == null || r.roman!.isEmpty) return; // 无罗马音时跳过

    final main = parser.parse(r.lyric);
    final ro = parser.parse(r.roman!);

    var newHit = 0;
    var oldHit = 0;
    for (var i = 0; i < main.lines.length; i++) {
      if (auxText(main, ro, i) != null) newHit++;
      // 旧算法：±200ms
      for (final a in ro.lines) {
        if ((a.start - main.lines[i].start).inMilliseconds.abs() <= 200) {
          oldHit++;
          break;
        }
      }
    }
    // ignore: avoid_print
    print('COVERAGE 旧=$oldHit/${main.lines.length} 新=$newHit/${main.lines.length}');
    expect(newHit, greaterThanOrEqualTo(oldHit), reason: '新算法不能比旧的差');
    expect(newHit, greaterThan(main.lines.length * 0.9),
        reason: '覆盖率应达 90% 以上');
  }, timeout: const Timeout(Duration(seconds: 90)));
}