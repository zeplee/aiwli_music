import 'quality.dart';

/// 音质从低到高。降级链按此顺序反向尝试。
///
/// 对齐参考实现（CyShineMusic `kQualityRank` + `musicSourceQualityFallbacks`）：
/// 请求音质不被某源支持时，不是硬失败，而是沿这个序列降到源支持的最近档位。
const List<Quality> kQualityRank = [
  Quality.standard,
  Quality.high,
  Quality.superQuality,
  Quality.lossless,
  Quality.hires,
];

/// 脚本里表示音质的字符串 ↔ 枚举。
extension QualityCode on Quality {
  /// 传给 lx 脚本 / MusicFree 插件的 quality 值。
  String get code => switch (this) {
        Quality.standard => '128k',
        Quality.high => '320k',
        Quality.superQuality => '320k',
        Quality.lossless => 'flac',
        Quality.hires => 'flac24bit',
      };

  static Quality? fromCode(String? raw) {
    switch ((raw ?? '').toLowerCase().trim()) {
      case '128k':
      case 'standard':
      case 'm':
      case 'l':
        return Quality.standard;
      case '320k':
      case 'exhigh':
      case 'h':
      case 'high':
        return Quality.high;
      case 'super':
      case 'superquality':
      case '320k 高码率':
        return Quality.superQuality;
      case 'flac':
      case 'lossless':
      case 'sq':
        return Quality.lossless;
      case 'flac24bit':
      case 'hires':
      case 'hi-res':
      case 'hr':
      case 'master':
      case 'atmos':
        return Quality.hires;
    }
    return null;
  }
}

/// 生成降级链：从请求音质开始，按 kQualityRank 向上升级到源支持的档位。
///
/// 语义与参考实现一致：**只向上找**（请求 128k 而源只有 320k，就用 320k；
/// 请求无损而源只有 128k，则不在本链内——那是"源不支持"而非"可降级"）。
/// 这样能避免"请求无损 → 源不支持 → 硬等超时 → 换源"的无效等待。
List<Quality> qualityFallbacks({
  required Quality requested,
  required Iterable<Quality> sourceQualities,
}) {
  final supported = sourceQualities.toSet();
  final start = kQualityRank.indexOf(requested);
  if (start < 0) return [requested];
  return List<Quality>.unmodifiable([
    requested,
    for (var i = start + 1; i < kQualityRank.length; i++)
      if (supported.contains(kQualityRank[i])) kQualityRank[i],
  ]);
}

/// 在源支持列表里挑最接近请求的音质（优先精确命中，否则就近）。
Quality chooseQuality({
  required Quality requested,
  required Iterable<Quality> sourceQualities,
}) {
  final supported = sourceQualities.toSet();
  if (supported.isEmpty || supported.contains(requested)) return requested;
  final requestedRank = kQualityRank.indexOf(requested);
  // 先向上找（更高音质可接受）
  for (var i = requestedRank + 1; i < kQualityRank.length; i++) {
    if (supported.contains(kQualityRank[i])) return kQualityRank[i];
  }
  // 再向下找（低音质总比失败好）
  for (var i = requestedRank - 1; i >= 0; i--) {
    if (supported.contains(kQualityRank[i])) return kQualityRank[i];
  }
  return requested;
}