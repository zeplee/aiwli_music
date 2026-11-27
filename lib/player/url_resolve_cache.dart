import '../core/models/quality.dart';
import '../core/models/quality_rank.dart';

/// 一条缓存的取链结果。
///
/// [winnerId] 必须是**实际胜出的脚本实例 id**，不能退化成曲目平台名
/// （kw/tx/...）：播放器验证死链后按 `(winnerId, platform)` 拉黑，
/// 读取方用的是 `_isDead(lx.id, platformId)`。若缓存命中丢掉脚本 id，
/// 拉黑键永远匹配不上，而缓存命中又绕过了 `_isDead` 筛选，
/// 于是 10 分钟 TTL 内会反复踩同一条死链。
class CachedResolution {
  const CachedResolution({
    required this.url,
    required this.winnerId,
    required this.winnerPlatform,
    required this.sourceLabel,
    required this.expireAt,
  });

  final String url;
  final String winnerId;
  final String? winnerPlatform;
  final String sourceLabel;
  final DateTime expireAt;
}

/// 播放地址缓存（纯 Dart，可独立实例化 / 测试）。
///
  /// key = sourceId|musicId|quality.name|quality.code，必须带音质维度。
  /// 用 name 而非仅 code：`high` / `superQuality` 的 code 都是 `320k`，
  /// 只用 code 仍会把两个档位混在一起；保留 code 让日志/排查能直接看出档位。
class UrlResolveCache {
  UrlResolveCache({
    this.ttl = const Duration(minutes: 10),
    this.maxEntries = 200,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration ttl;
  final int maxEntries;
  final DateTime Function() _now;
  final Map<String, CachedResolution> _entries = {};

  static String key(String sourceId, String musicId, Quality quality) =>
      '$sourceId|$musicId|${quality.name}|${quality.code}';

  int get length => _entries.length;

  CachedResolution? get(String sourceId, String musicId, Quality quality) {
    final k = key(sourceId, musicId, quality);
    final hit = _entries[k];
    if (hit == null) return null;
    // 到达 expireAt 即失效（边界不再多留一瞬）。
    if (!_now().isBefore(hit.expireAt)) {
      _entries.remove(k);
      return null;
    }
    return hit;
  }

  void put({
    required String sourceId,
    required String musicId,
    required Quality quality,
    required String url,
    required String winnerId,
    required String sourceLabel,
    String? winnerPlatform,
  }) {
    _entries[key(sourceId, musicId, quality)] = CachedResolution(
      url: url,
      winnerId: winnerId,
      winnerPlatform: winnerPlatform,
      sourceLabel: sourceLabel,
      expireAt: _now().add(ttl),
    );
    // 简单容量控制，避免无限增长
    if (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// 作废某曲的**全部音质变体**（拉黑死链后重试不能命中旧 URL）。
  void invalidate(String sourceId, String musicId) {
    final prefix = '$sourceId|$musicId|';
    _entries.removeWhere((k, _) => k.startsWith(prefix));
  }

  /// 作废某源名下全部条目（所有曲目、所有音质）。
  ///
  /// 调用方传进来的通常是 `ResolvedPlayback.winnerId`（脚本实例 id），
  /// 而 key 第一段是请求曲目的 sourceId（可能是 kw 这类平台名）——两者
  /// 并不相同，故还要按真实胜出源 id 反向清理，否则死链缓存清不掉。
  void invalidateAll(String sourceId) {
    final prefix = '$sourceId|';
    _entries.removeWhere(
        (k, v) => k.startsWith(prefix) || v.winnerId == sourceId);
  }
}
