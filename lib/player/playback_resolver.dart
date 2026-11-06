import 'dart:async';

import '../core/models/music.dart';
import '../core/models/quality.dart';
import '../core/models/quality_rank.dart';
import '../core/services/logger.dart';
import '../sources/lx/lx_source.dart';
import '../sources/registry.dart';

/// 一次取链的结果（含实际生效的源与曲目，便于上层更新 UI）。
class ResolvedPlayback {
  const ResolvedPlayback({
    required this.url,
    required this.sourceId,
    required this.sourceLabel,
    required this.musicId,
    required this.title,
    required this.artist,
    required this.winnerId,
    this.winnerPlatform,
    this.toggled = false,
  });

  final String url;

  /// 曲目所属平台/源（kw/tx/... 或脚本源 id）。
  final String sourceId;

  /// 实际取链胜出的脚本实例 id（内置平台由某脚本代取时与 sourceId 不同）。
  ///
  /// 播放器 load 失败时拉黑用的是 **(winnerId, 平台)** 二元组：
  /// 只按脚本拉黑会连带判死该脚本的其他平台；
  /// 只按平台拉黑会连带判死其他脚本的同一平台。
  ///
  /// 注意：缓存命中与换源路径拿不到脚本 id，此时该字段退化为平台 id
  /// （见 [PlaybackResolver.reportUnplayable] 的退化匹配）。
  final String winnerId;

  /// 胜出时的平台 id（kw/tx/...）。缓存/换源路径为 null。
  final String? winnerPlatform;
  final String sourceLabel;
  final String musicId;
  final String title;
  final String artist;

  /// true 表示经过换源（原源失败，改用其他源）。
  final bool toggled;
}

/// 取链失败异常（携带已尝试的源，便于提示）。
class PlaybackResolveException implements Exception {
  PlaybackResolveException(this.message, this.tried);
  final String message;
  final List<String> tried;

  @override
  String toString() => tried.isEmpty ? message : '$message（已试 ${tried.join("、")}）';
}

/// 播放地址解析器：先按「曲目所属源」取链，失败则**自动换源**。
///
/// 换源策略对齐 lx-music 的 `getOtherSource` + `getOnlineOtherSourceMusicUrl`：
///  1. 首选曲目自己的 sourceId（内置平台 kw/tx/wy/kg/mg 走内置取链；
///     脚本/插件源 id 走对应脚本取链）
///  2. 该源失败 → 用「歌名 + 歌手」在所有可搜索源里重新搜索
///  3. 取第一个匹配项，在新源上重试取链；**已试过的源不再重试**
///  4. 全部失败才抛错，错误里带上试过的源
class PlaybackResolver {
  PlaybackResolver(this._registry);

  final SourceRegistry _registry;

  /// 英文平台名 → 展示名。
  static const builtinLabels = <String, String>{
    'kw': '酷我',
    'tx': 'QQ音乐',
    'wy': '网易云',
    'kg': '酷狗',
    'mg': '咪咕',
  };

  /// 换源搜索超时。参考实现用 15s，但那是桌面端且只搜内置 5 平台；
  /// 我们源更多、QuickJS 更慢，缩到 8s 避免用户长时间无反馈。
  static const _searchTimeout = Duration(seconds: 8);

  /// 单个源取链超时。真实可用脚本通常 1-3s 内返回；20s 会让串行尝试
  /// 拖到一分钟以上，这里收到 6s。
  static const _urlTimeout = Duration(seconds: 6);

  /// 记住「哪个源成功取到过链接」，下次同平台优先用它（内存级，会话内有效）。
  final Map<String, String> _preferred = {};

  /// 死源/坏源记忆：URL 取到但播放器打不开（如域名 NXDOMAIN、5xx）。
  ///
  /// **键必须是 (脚本id, 平台id) 二元组**，不能只用其中一个：
  ///   · 只用脚本 id → 幻音返回的酷我链接挂了，会连带把网易/QQ 也判死
  ///   · 只用平台 id → 幻音的酷我挂了，会把其他脚本的酷我也判死
  /// 两者都会让之后的取链白白跳过可用源。
  ///
  /// 历史 bug：这里曾是 `Map<String, DateTime>`，而写入方
  /// （缓存命中 / 换源路径）传的是平台 id、读取方 `_isDead(lx.id)`
  /// 传的是脚本 id —— 键混用导致那些记录永远不会被命中，成了死数据。
  final Map<String, DateTime> _deadUntil = {};
  static const _deadPenalty = Duration(minutes: 30);

  String _deadKey(String lxId, String platformId) => '$lxId|$platformId';

  /// 是否已判死。任一键为空时退化为单键匹配（缓存/换源路径拿不到脚本 id）。
  bool _isDead(String lxId, {String? platformId}) {
    final keys = <String>[
      if (platformId != null) _deadKey(lxId, platformId),
      _deadKey(lxId, ''),
    ];
    final now = DateTime.now();
    var dead = false;
    for (final k in keys) {
      final t = _deadUntil[k];
      if (t == null) continue;
      if (now.isAfter(t)) {
        _deadUntil.remove(k);
      } else {
        dead = true;
      }
    }
    return dead;
  }

  /// 测试可见：判断某 (脚本, 平台) 是否已被判死。
  bool debugIsDead(String lxId, {String? platformId}) =>
      _isDead(lxId, platformId: platformId);

  /// 播放器报告「这个源+平台的 URL 打不开」。
  ///
  /// [platformId] 与 [lxId] 都可能与调用方拿到的对象不同：
  /// 缓存/换源路径只有平台 id，此时 lxId 传平台 id、platformId 传 null
  /// 也能正确记下来（见 [_isDead] 的退化匹配）。
  void reportUnplayable(String lxId, {String? platformId, Object? error}) {
    final key = _deadKey(lxId, platformId ?? '');
    _deadUntil[key] = DateTime.now().add(_deadPenalty);
    AppLog.w('Resolve',
        '标记坏源 $lxId${platformId != null ? '/$platformId' : ''}'
        '（30min 内跳过）: $error');
  }

  /// 在途请求去重：同一首歌并发触发（点播+预取+自动下一首）时，
  /// 后到者复用同一个 Future，避免同时压到同一个 LxRuntime 串行队列
  /// 造成 dispatch 超时连锁重建。
  final Map<String, Future<ResolvedPlayback>> _inFlight = {};

  /// 播放地址缓存：key = sourceId|musicId，value = (url, 过期时间)。
  ///
  /// 对齐 lx-music 的 `music_url` 表（取链前先查缓存，命中直接返回不发请求）。
  /// 平台直链通常带时效（vkey 约 20 分钟～数小时），故设 TTL 保守 10 分钟；
  /// 过期自动丢弃重取。
  static const _urlTtl = Duration(minutes: 10);
  final Map<String, ({String url, DateTime expireAt})> _urlCache = {};

  String _cacheKey(String sourceId, String musicId) => '$sourceId|$musicId';

  /// 播放器报告 URL 打不开：作废该曲缓存（否则重试永远命中同一条死链）。
  void invalidateCache(String sourceId, String musicId) {
    _urlCache.remove(_cacheKey(sourceId, musicId));
  }

  /// 某源被拉黑时，作废它名下的全部缓存条目（key 前缀 = sourceId|）。
  void invalidateCacheAll(String sourceId) {
    final prefix = '$sourceId|';
    _urlCache.removeWhere((k, _) => k.startsWith(prefix));
  }

  String? _cacheGet(String sourceId, String musicId) {
    final hit = _urlCache[_cacheKey(sourceId, musicId)];
    if (hit == null) return null;
    if (DateTime.now().isAfter(hit.expireAt)) {
      _urlCache.remove(_cacheKey(sourceId, musicId));
      return null;
    }
    return hit.url;
  }

  void _cachePut(String sourceId, String musicId, String url) {
    _urlCache[_cacheKey(sourceId, musicId)] =
        (url: url, expireAt: DateTime.now().add(_urlTtl));
    // 简单容量控制，避免无限增长
    if (_urlCache.length > 200) {
      _urlCache.remove(_urlCache.keys.first);
    }
  }

  /// 平台/源 → 上次成功的源 id。
  String? _preferredFor(String sourceId) => _preferred[sourceId];

  /// 解析播放地址。失败抛 [PlaybackResolveException]。
  Future<ResolvedPlayback> resolve({
    required String title,
    required String artist,
    required String sourceId,
    required String musicId,
    required Quality quality,
    Map<Object?, Object?>? raw,
    void Function(String sourceLabel)? onToggle,
    Set<String> excludeIds = const {},
  }) {
    final ex = excludeIds.join(',');
    final key = '${_cacheKey(sourceId, musicId)}|ex=$ex';
    final inflight = _inFlight[key];
    if (inflight != null) {
      AppLog.i('Resolve', '在途复用 $key');
      return inflight;
    }
    final fut = _resolveInner(
      title: title,
      artist: artist,
      sourceId: sourceId,
      musicId: musicId,
      quality: quality,
      raw: raw,
      onToggle: onToggle,
      excludeIds: excludeIds,
    );
    _inFlight[key] = fut;
    return fut.whenComplete(() => _inFlight.remove(key));
  }

  Future<ResolvedPlayback> _resolveInner({
    required String title,
    required String artist,
    required String sourceId,
    required String musicId,
    required Quality quality,
    Map<Object?, Object?>? raw,
    void Function(String sourceLabel)? onToggle,
    Set<String> excludeIds = const {},
  }) async {
    final tried = <String>[];
    final total = Stopwatch()..start();
    AppLog.i('Resolve',
        '开始 source=$sourceId id=$musicId q=${quality.code} title="$title"');

    // —— 0. 缓存命中直接返回（切歌/重播几乎瞬时）——
    final cached = excludeIds.isEmpty ? _cacheGet(sourceId, musicId) : null;
    if (cached != null) {
      total.stop();
      AppLog.i('Resolve', '缓存命中，用时 ${total.elapsedMilliseconds}ms');
      return ResolvedPlayback(
        url: cached,
        sourceId: sourceId,
        winnerId: sourceId,
        winnerPlatform: sourceId,
        sourceLabel: _label(sourceId),
        musicId: musicId,
        title: title,
        artist: artist,
      );
    }

    // —— 1. 首选：曲目自己的源 ——
    final first = await _tryOne(
      title: title,
      artist: artist,
      sourceId: sourceId,
      musicId: musicId,
      quality: quality,
      raw: raw,
    );
    if (first != null) {
      _cachePut(sourceId, musicId, first.url);
      total.stop();
      AppLog.i('Resolve',
          '本源取链成功，用时 ${total.elapsedMilliseconds}ms（source=$sourceId）');
      return first;
    }
    tried.add(_label(sourceId));
    AppLog.w('Resolve', '本源取链失败，用时 ${total.elapsedMilliseconds}ms，进入换源');

    // —— 2. 换源：按歌名+歌手在其余源里搜索 ——
    //
    // 这里原先用 `for await` **串行**尝试每个候选平台：4 个平台各 500ms
    // 就是 2 秒起步，全失败时用户等到的是"点了半天才有红条"。
    // 改为并发：任一平台成功即采用，全部失败再抛错——这才符合
    // "把所有源都扫一遍再说失败"的预期，耗时也从 Σ 变成 max。
    final candidates = await _findOtherSources(title, artist,
        exclude: {sourceId, ...excludeIds});
    final todo = <MusicInfo>[];
    for (final c in candidates) {
      final label = _label(c.sourceId);
      if (tried.contains(label)) continue;
      tried.add(label);
      onToggle?.call(label);
      todo.add(c);
    }
    if (todo.isNotEmpty) {
      final results = await Future.wait(todo.map((c) async {
        try {
          return await _tryOne(
            title: c.title,
            artist: c.artist,
            sourceId: c.sourceId,
            musicId: c.musicId,
            quality: quality,
            raw: raw,
            excludeIds: {...excludeIds, sourceId},
          );
        } catch (_) {
          return null;
        }
      }));

      for (var i = 0; i < todo.length; i++) {
        final r = results[i];
        if (r == null) continue;
        final c = todo[i];
        total.stop();
        AppLog.i('Resolve',
            '换源成功 $sourceId → ${c.sourceId}，总用时 ${total.elapsedMilliseconds}ms');
        _cachePut(sourceId, musicId, r.url);
        return ResolvedPlayback(
          url: r.url,
          sourceId: c.sourceId,
          winnerId: c.sourceId,
          winnerPlatform: c.sourceId,
          sourceLabel: _label(c.sourceId),
          musicId: c.musicId,
          title: r.title,
          artist: r.artist,
          toggled: true,
        );
      }
    }

    total.stop();
    AppLog.e('Resolve',
        '全部失败，总用时 ${total.elapsedMilliseconds}ms，已试 ${tried.join("/")}');
    throw PlaybackResolveException('所有音源都无法取到播放链接', tried);
  }

  String _label(String sourceId) {
    final builtin = builtinLabels[sourceId];
    if (builtin != null) return builtin;
    for (final s in _registry.installed) {
      if (s.id == sourceId) return s.name;
    }
    return sourceId;
  }

  /// 在单个源上取链；失败返回 null（不抛）。
  ///
  /// 内置平台曲目（kw/tx/wy/kg/mg）没有内置取链接口（合规：壳不内置取链），
  /// 需要借用「声明了该平台能力的脚本源」来取链——脚本的 musicUrl 请求里
  /// source 传平台名即可（如 source: 'kw'）。
  Future<ResolvedPlayback?> _tryOne({
    required String title,
    required String artist,
    required String sourceId,
    required String musicId,
    required Quality quality,
    Map<Object?, Object?>? raw,
    Set<String> excludeIds = const {},
  }) async {
    final isBuiltin = builtinLabels.containsKey(sourceId);

    // 候选脚本源：本源（脚本/插件）或所有声明了该平台的脚本源（内置平台）。
    // 排除集 = 播放器已验证「URL 打不开」的脚本实例 id。
    final candidates = <LxSource>[];
    if (isBuiltin) {
      for (final lx in _registry.enabledRuntimes) {
        if (_isDead(lx.id, platformId: sourceId) ||
            excludeIds.contains(lx.id)) {
          continue;
        }
        try {
          await lx.waitInited();
          if (lx.supportsPlatform(sourceId)) candidates.add(lx);
        } catch (e) {
          // 不能静默：初始化超时/报错的源会被排除在候选之外，
          // 若全部源都这样，上层只会看到笼统的"取链失败"，
          // 无法判断是"源初始化挂了"还是"接口没数据"。
          AppLog.w('Resolve', '源 ${lx.id} 初始化失败，已跳过候选: $e');
        }
      }
    } else {
      if (excludeIds.contains(sourceId) || _isDead(sourceId, platformId: sourceId)) {
        return null;
      }
      final lx = _registry.runtimeOf(sourceId);
      if (lx != null) candidates.add(lx);
    }
    if (candidates.isEmpty) return null;

    // 按音质降级链尝试：请求音质不被源支持时不硬失败，而是沿链上移
    // （对齐参考实现 musicSourceQualityFallbacks，避免"请求无损→源不支持
    //  →硬等超时→换源"的无效等待）。
    final qualityChain = qualityFallbacks(
      requested: quality,
      sourceQualities: candidates.expand((c) => c.declaredQualities).toSet(),
    );

    for (final q in qualityChain) {
      final got = await _tryWithQuality(
        candidates: candidates,
        sourceId: sourceId,
        musicId: musicId,
        title: title,
        artist: artist,
        quality: q,
        raw: raw,
        isBuiltin: isBuiltin,
        excludeIds: excludeIds,
      );
      if (got != null) return got;
    }
    return null;
  }

  /// 用指定音质并发尝试候选源。
  Future<ResolvedPlayback?> _tryWithQuality({
    required List<LxSource> candidates,
    required String sourceId,
    required String musicId,
    required String title,
    required String artist,
    required Quality quality,
    required Map<Object?, Object?>? raw,
    required bool isBuiltin,
    Set<String> excludeIds = const {},
  }) async {
    // 能力预筛选：声明了平台但没声明该音质、或已被播放器验证打不开的源
    // 直接跳过，不浪费一次请求
    final capable = <LxSource>[];
    for (final lx in candidates) {
      if (excludeIds.contains(lx.id)) continue;
      final qs = lx.declaredQualities;
      if (qs.isEmpty || qs.contains(quality)) capable.add(lx);
    }
    if (capable.isEmpty) {
      AppLog.w('Resolve',
          '音质 ${quality.code}: 所有候选源都不支持，跳过（不浪费时间）');
      return null;
    }
    AppLog.i('Resolve',
        '音质 ${quality.code}: 候选 ${candidates.length} → 支持 ${capable.length} 个');

    // 优先用上次成功的源；否则并发尝试所有候选，谁先成功用谁。
    final preferredId = _preferredFor(sourceId);
    final ordered = [
      if (preferredId != null)
        ...capable.where((c) => c.id == preferredId),
      ...capable.where((c) => c.id != preferredId),
    ];

    final winner = await _firstSuccess(ordered, (
      {required lx, required platform}) async {
      await lx.waitInited();
      return lx.getMusicUrl(
        MusicInfo(
          sourceId: sourceId,
          musicId: musicId,
          title: title,
          artist: artist,
          raw: raw,
        ),
        quality,
        platform: platform,
      );
    }, platform: isBuiltin ? sourceId : null);

    if (winner == null) return null;
    _preferred[sourceId] = winner.$1;
    return ResolvedPlayback(
      url: winner.$2,
      sourceId: sourceId,
      winnerId: winner.$1,
      winnerPlatform: sourceId,
      sourceLabel: _label(sourceId),
      musicId: musicId,
      title: title,
      artist: artist,
    );
  }

  /// 并发尝试多个源，返回第一个成功的结果（源 id + url）。
  /// 全部失败/超时返回 null。用 true 并发避免串行等待逐个超时。
  Future<(String, String)?> _firstSuccess(
    List<LxSource> candidates,
    Future<String> Function(
            {required LxSource lx, required String? platform})
        attempt, {
    required String? platform,
  }) async {
    if (candidates.isEmpty) return null;

    final completer = Completer<(String, String)?>();
    var pending = candidates.length;

    void finish((String, String)? r) {
      if (completer.isCompleted) return;
      completer.complete(r);
    }

    for (final lx in candidates) {
      unawaited(() async {
        final sw = Stopwatch()..start();
        try {
          final url = await attempt(lx: lx, platform: platform)
              .timeout(_urlTimeout);
          sw.stop();
          if (url.isNotEmpty) {
            AppLog.i('Resolve', '  ${lx.name} 成功 ${sw.elapsedMilliseconds}ms');
            // 胜出即取消其余输家：它们还挂在各自 runtime 的串行队列上，
            // 任其超时会触发 6s 等待 + 重建级联（现场日志证实）。
            for (final other in candidates) {
              if (other.id != lx.id) other.cancelPending();
            }
            finish((lx.id, url));
          } else {
            AppLog.w('Resolve', '  ${lx.name} 空结果 ${sw.elapsedMilliseconds}ms');
          }
        } catch (e) {
          sw.stop();
          AppLog.w('Resolve',
              '  ${lx.name} 失败 ${sw.elapsedMilliseconds}ms: $e');
        } finally {
          pending--;
          if (pending == 0) finish(null);
        }
      }());
    }
    return completer.future.timeout(
      _urlTimeout + const Duration(seconds: 2),
      onTimeout: () => null,
    );
  }

  /// 用歌名+歌手在所有「能搜索」的源里找同一首歌的另一个版本。
  Future<List<MusicInfo>> _findOtherSources(
    String title,
    String artist, {
    required Set<String> exclude,
  }) async {
    final keyword = '$artist $title'.trim();
    final runtimes = _registry.enabledRuntimes
        .where((lx) => !exclude.contains(lx.id))
        .toList();
    if (runtimes.isEmpty) return const [];

    // 只保留声明了 musicSearch 的源
    final capable = <LxSource>[];
    await Future.wait(runtimes.map((lx) async {
      try {
        await lx.waitInited();
        if (lx.actions.contains('musicSearch')) capable.add(lx);
      } catch (_) {}
    }));
    if (capable.isEmpty) return const [];

    final results = await Future.wait(capable.map((lx) async {
      try {
        final list = await lx
            .searchFromScript(keyword)
            .timeout(_searchTimeout);
        return list ?? const <MusicInfo>[];
      } catch (_) {
        return const <MusicInfo>[];
      }
    }));

    // 按「歌名+主歌手」相似度取每源的第一个匹配
    final out = <MusicInfo>[];
    for (final list in results) {
      for (final m in list) {
        if (_similar(m.title, title) && _similar(m.artist, artist)) {
          out.add(m);
          break;
        }
      }
    }
    return out;
  }

  /// 宽松匹配：任一方向包含即算相似（去掉空格与常见符号）。
  bool _similar(String a, String b) {
    String norm(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\-_·,，、&()（）\[\]【】]'), '')
        .replaceAll(RegExp(r'(live|remix|伴奏|版)$'), '');
    final x = norm(a);
    final y = norm(b);
    if (x.isEmpty || y.isEmpty) return false;
    return x.contains(y) || y.contains(x);
  }
}
