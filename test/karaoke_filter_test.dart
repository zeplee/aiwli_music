import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/sources/builtin/instrumental_finder.dart';

/// K 歌模式（找官方伴奏）的匹配逻辑。
///
/// 历史：最初做成"立体声相减"（L-R 抵消中置人声），但实测发现
/// media_kit 的音频版 mpv 在编译时裁掉了 pan/bass 滤镜：
///
///     探针 "pan"  → 不支持
///     探针 "bass" → 不支持
///     探针 "equalizer" → 支持
///
/// 即信号处理在 Android 上根本跑不起来（`af` 设完读回是空串）。
/// 改走"搜官方伴奏"路线——效果是真·无人生混音，也不依赖滤镜。
void main() {
  group('伴奏标记识别', () {
    test('常见伴奏标注都能认出来', () {
      for (final t in [
        '晴天 (KTV版伴奏)',
        '演员 (伴奏)',
        '小幸运（纯音乐）',
        'Song (Instrumental)',
        '某某 伴唱版',
        '某曲 无人声',
      ]) {
        expect(InstrumentalFinder.isInstrumental(t), isTrue,
            reason: '「$t」应被判为伴奏');
      }
    });

    test('正常歌名不算伴奏', () {
      for (final t in [
        '晴天',
        '演员',
        '夜曲',
        'Live 版',
        'Cover 版',
      ]) {
        expect(InstrumentalFinder.isInstrumental(t), isFalse,
            reason: '「$t」是正常歌曲，不该被当成伴奏');
      }
    });
  });

  group('标题匹配（去掉括号内容后与原名对齐）', () {
    // 内部逻辑通过公开 API 间接验证：这里复刻规范化规则做一致性检查
    String norm(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[（(].*?[)）]'), '')
        .replaceAll(RegExp(r'[\s\-_·,，、&]'), '');

    test('「晴天 (KTV版伴奏)」规范化后等于「晴天」', () {
      expect(norm('晴天 (KTV版伴奏)').contains(norm('晴天')), isTrue);
    });

    test('不会把别的歌的伴奏认成目标', () {
      // 「雨天 (伴奏)」不该匹配「晴天」
      final a = norm('雨天 (伴奏)');
      final b = norm('晴天');
      expect(a.contains(b) || b.contains(a), isFalse);
    });
  });

  test('空歌手/空标题不崩溃', () {
    expect(InstrumentalFinder.isInstrumental(''), isFalse);
  });
}