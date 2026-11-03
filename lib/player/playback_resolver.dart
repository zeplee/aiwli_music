import 'dart:async';

import '../core/models/music.dart';
import '../core/models/quality.dart';
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
    this.toggled = false,
  });

  final String url;
  final String sourceId;
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

  /// 换源搜索超时（对齐 lx 的 15s）。
  static const _searchTimeout = Duration(seconds: 15);

  /// 单个源取链超时。
  static const _urlTimeout = Duration(seconds: 20);

  /// 解析播放地址。失败抛 [PlaybackResolveException]。
  Future<ResolvedPlayback> resolve({
    required String title,
    required String artist,
    required String sourceId,
    required String musicId,
    required Quality quality,
    Map<Object?, Object?>? raw,
    void Function(String sourceLabel)? onToggle,
  }) async {
    final tried = <String>[];

    // —— 1. 首选：曲目自己的源 ——
    final first = await _tryOne(
      title: title,
      artist: artist,
      sourceId: sourceId,
      musicId: musicId,
      quality: quality,
      raw: raw,
    );
    if (first != null) return first;
    tried.add(_label(sourceId));

    // —— 2. 换源：按歌名+歌手在其余源里搜索 ——
    final candidates = await _findOtherSources(title, artist, exclude: {sourceId});
    for (final c in candidates) {
      if (tried.contains(_label(c.sourceId))) continue;
      tried.add(_label(c.sourceId));
      onToggle?.call(_label(c.sourceId));
      final r = await _tryOne(
        title: c.title,
        artist: c.artist,
        sourceId: c.sourceId,
        musicId: c.musicId,
        quality: quality,
      );
      if (r != null) {
        AppLog.i('PlaybackResolver', '换源成功: $sourceId → ${c.sourceId}');
        return ResolvedPlayback(
          url: r.url,
          sourceId: c.sourceId,
          sourceLabel: _label(c.sourceId),
          musicId: c.musicId,
          title: r.title,
          artist: r.artist,
          toggled: true,
        );
      }
    }

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
  }) async {
    final isBuiltin = builtinLabels.containsKey(sourceId);

    // 候选脚本源：本源（脚本/插件）或所有声明了该平台的脚本源（内置平台）
    final candidates = <LxSource>[];
    if (isBuiltin) {
      for (final lx in _registry.enabledRuntimes) {
        try {
          await lx.waitInited();
          if (lx.supportsPlatform(sourceId)) candidates.add(lx);
        } catch (_) {}
      }
    } else {
      final lx = _registry.runtimeOf(sourceId);
      if (lx != null) candidates.add(lx);
    }
    if (candidates.isEmpty) return null;

    for (final lx in candidates) {
      try {
        await lx.waitInited();
        final url = await lx
            .getMusicUrl(
              MusicInfo(
                sourceId: sourceId,
                musicId: musicId,
                title: title,
                artist: artist,
                raw: raw,
              ),
              quality,
              // 内置平台：把平台名告诉脚本；脚本源自身则用其 id
              platform: isBuiltin ? sourceId : null,
            )
            .timeout(_urlTimeout);
        if (url.isEmpty) continue;
        return ResolvedPlayback(
          url: url,
          sourceId: sourceId,
          sourceLabel: _label(sourceId),
          musicId: musicId,
          title: title,
          artist: artist,
        );
      } catch (e) {
        AppLog.w('PlaybackResolver', '${lx.name} 取 $sourceId 失败: $e');
      }
    }
    return null;
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
