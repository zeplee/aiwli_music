import 'package:flutter_test/flutter_test.dart';
import 'package:aiwli_music/core/models/quality.dart';
import 'package:aiwli_music/core/models/quality_rank.dart';

void main() {
  test('降级链：请求无损，源只支持 128k → 向下降到 128k', () {
    final chain = qualityFallbacks(
      requested: Quality.lossless,
      sourceQualities: {Quality.standard},
    );
    expect(chain, [Quality.lossless, Quality.standard]);
  });

  test('降级链：请求 128k，源支持 320k/无损 → 依次向上', () {
    final chain = qualityFallbacks(
      requested: Quality.standard,
      sourceQualities: {Quality.standard, Quality.high, Quality.lossless},
    );
    expect(chain, [Quality.standard, Quality.high, Quality.lossless]);
  });

  test('降级链：请求 320k，源只支持 128k → 向下降到 128k', () {
    final chain = qualityFallbacks(
      requested: Quality.high,
      sourceQualities: {Quality.standard},
    );
    expect(chain, [Quality.high, Quality.standard]);
  });

  test('降级链：源未声明音质 → 只有请求音质本身', () {
    final chain = qualityFallbacks(
      requested: Quality.high,
      sourceQualities: {},
    );
    expect(chain, [Quality.high]);
  });

  test('降级链：请求 Hi-Res，源只有 128k → 向下降到 128k', () {
    final chain = qualityFallbacks(
      requested: Quality.hires,
      sourceQualities: {Quality.standard},
    );
    expect(chain, [Quality.hires, Quality.standard]);
  });

  test('降级链：请求 128k，源只有 Hi-Res → 向上升到 Hi-Res', () {
    final chain = qualityFallbacks(
      requested: Quality.standard,
      sourceQualities: {Quality.hires},
    );
    expect(chain, [Quality.standard, Quality.hires]);
  });

  test('降级链：先向下从高到低，再向上从低到高，且结果去重', () {
    final chain = qualityFallbacks(
      requested: Quality.lossless,
      sourceQualities: [
        Quality.standard,
        Quality.high,
        Quality.hires,
        Quality.high,
      ],
    );
    expect(chain, [
      Quality.lossless,
      Quality.high,
      Quality.standard,
      Quality.hires,
    ]);
  });

  test('chooseQuality 优先精确命中', () {
    expect(
      chooseQuality(requested: Quality.high, sourceQualities: {Quality.high}),
      Quality.high,
    );
  });

  test('chooseQuality 未命中时向上优先，再向下兜底', () {
    // 请求 320k，源只有 128k 和 无损 → 向上选无损
    expect(
      chooseQuality(
          requested: Quality.high,
          sourceQualities: {Quality.standard, Quality.lossless}),
      Quality.lossless,
    );
    // 请求无损，源只有 128k/320k → 向下选 320k
    expect(
      chooseQuality(
          requested: Quality.lossless,
          sourceQualities: {Quality.standard, Quality.high}),
      Quality.high,
    );
  });

  test('QualityCode 双向映射', () {
    expect(Quality.standard.code, '128k');
    expect(Quality.lossless.code, 'flac');
    expect(Quality.hires.code, 'flac24bit');
    expect(QualityCode.fromCode('320k'), Quality.high);
    expect(QualityCode.fromCode('flac'), Quality.lossless);
    expect(QualityCode.fromCode('master'), Quality.hires);
    expect(QualityCode.fromCode('莫名其妙'), isNull);
  });

  test('kQualityRank 顺序从低到高', () {
    expect(kQualityRank.first, Quality.standard);
    expect(kQualityRank.last, Quality.hires);
    expect(kQualityRank.length, 5);
  });
}
