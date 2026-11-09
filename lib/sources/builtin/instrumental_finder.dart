import '../../core/models/music.dart';
import '../../core/services/logger.dart';
import 'kw_sdk.dart';
import 'wy_sdk.dart';

/// 找到某首歌的**官方伴奏版**。
///
/// 为什么走这条路而不是信号处理：
///   1. 效果远好 —— 官方伴奏是真正的无人生混音，不是 L-R 相减的近似
///   2. 兼容性无问题 —— media_kit 的音频版 mpv 编译时裁掉了 pan/bass
///      滤镜（实测两者都被拒），信号处理在 Android 上根本跑不起来
///
/// 判据（对齐 daily_recommend.dart 里已有的排除逻辑，反过来用）：
///   标题里带「伴奏 / 纯音乐 / instrumental / KTV / 伴唱」等标记
///   且歌手与原曲一致（避免拿到翻唱者的伴奏）
class InstrumentalFinder {
  InstrumentalFinder._();

  /// 标题里能说明"这是伴奏"的标记。
  static final _markers = RegExp(
    r'伴奏|纯音乐|instrumental|karaoke|ktv|伴唱|无人声|off\s*vocal',
    caseSensitive: false,
  );

  /// 判断某条结果是否是伴奏版。
  static bool isInstrumental(String title) => _markers.hasMatch(title);

  /// 搜索官方伴奏。返回 null 表示没找到。
  ///
  /// [artist] 用于优先选原唱版本：酷我搜「演员 伴奏」会返回
  /// 「演员 (伴奏) - 薛之谦」（原唱）在前，也可能混入翻唱的伴奏。
  static Future<MusicInfo?> find({
    required String title,
    required String artist,
  }) async {
    final kw = '$title 伴奏'.trim();
    final queries = [kw, '$title 纯音乐', '$title instrumental'];

    for (final q in queries) {
      final hits = await _searchAll(q);
      final picked = _pickBest(hits, title: title, artist: artist);
      if (picked != null) {
        AppLog.i('Instrumental',
            '找到伴奏「${picked.title} - ${picked.artist}」(${picked.sourceId})');
        return picked;
      }
    }
    AppLog.i('Instrumental', '未找到「$title - $artist」的伴奏版');
    return null;
  }

  static Future<List<MusicInfo>> _searchAll(String q) async {
    final out = <MusicInfo>[];
    // 两家并发；单家失败不影响另一家
    final results = await Future.wait([
      KwSdk.search(q, limit: 10).catchError((_) => <MusicInfo>[]),
      WySdk.search(q, limit: 10).catchError((_) => <MusicInfo>[]),
    ]);
    for (final list in results) {
      out.addAll(list);
    }
    return out;
  }

  /// 从候选中挑一条最像"原唱伴奏"的。
  ///
  /// 排序优先级：
  ///   1. 标题必须是伴奏类（否则是原曲，换了没意义）
  ///   2. 歌手与原曲一致（原唱伴奏优先于翻唱伴奏）
  ///   3. 酷我优先（实测酷我「歌名 伴奏」命中率最高，且 KTV 版标注明确）
  static MusicInfo? _pickBest(
    List<MusicInfo> hits, {
    required String title,
    required String artist,
  }) {
    final sameArtist = <MusicInfo>[];
    final others = <MusicInfo>[];
    for (final h in hits) {
      if (!isInstrumental(h.title)) continue;
      // 标题里要能对上原曲名，避免搜到别的歌的伴奏
      if (!_titleMatches(h.title, title)) continue;
      if (_artistMatches(h.artist, artist)) {
        sameArtist.add(h);
      } else {
        others.add(h);
      }
    }
    if (sameArtist.isNotEmpty) {
      sameArtist.sort((a, b) {
        // 酷我优先
        final ak = a.sourceId == 'kw' ? 0 : 1;
        final bk = b.sourceId == 'kw' ? 0 : 1;
        return ak.compareTo(bk);
      });
      return sameArtist.first;
    }
    return others.isEmpty ? null : others.first;
  }

  /// 伴奏标题形如「晴天 (KTV版伴奏)」「演员 (伴奏)」，去掉括号内容后
  /// 应与原曲名一致。
  static bool _titleMatches(String hitTitle, String original) {
    String norm(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[（(].*?[)）]'), '')
        .replaceAll(RegExp(r'[\s\-_·,，、&]'), '');
    final a = norm(hitTitle);
    final b = norm(original);
    if (a.isEmpty || b.isEmpty) return false;
    return a.contains(b) || b.contains(a);
  }

  static bool _artistMatches(String hitArtist, String original) {
    String norm(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[\s\-_·,，、&/]'), '');
    final a = norm(hitArtist);
    final b = norm(original);
    if (a.isEmpty || b.isEmpty) return false;
    return a.contains(b) || b.contains(a);
  }
}