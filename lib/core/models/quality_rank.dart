import 'quality.dart';

/// 音质从低到高。降级链先沿此序列反向找可用档，再正向找可用档。
///
/// 对齐参考实现（CyShineMusic `kQualityRank` + `musicSourceQualityFallbacks`）：
/// 请求音质不被某源支持时，不是硬失败，而是尝试源支持的其他档位。
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

/// 生成「能播优先」降级链：先请求档，再向下找可用档（从高到低），
/// 最后向上找可用档（从低到高），结果去重。
///
/// **低音质总比失败好**：请求无损/Hi-Res 而脚本只声明 128k 时，仍降到
/// 128k 让用户听到声音；请求 128k 而源只有 320k 时仍能升到 320k。
/// 避免"请求无损 → 源不支持 → 硬等超时 → 换源"的无效等待。
List<Quality> qualityFallbacks({
  required Quality requested,
  required Iterable<Quality> sourceQualities,
}) {
  final supported = sourceQualities.toSet();
  final start = kQualityRank.indexOf(requested);
  if (start < 0) return List<Quality>.unmodifiable([requested]);
  final chain = <Quality>{requested};
  for (var i = start - 1; i >= 0; i--) {
    final quality = kQualityRank[i];
    if (supported.contains(quality)) chain.add(quality);
  }
  for (var i = start + 1; i < kQualityRank.length; i++) {
    final quality = kQualityRank[i];
    if (supported.contains(quality)) chain.add(quality);
  }
  return List<Quality>.unmodifiable(chain);
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