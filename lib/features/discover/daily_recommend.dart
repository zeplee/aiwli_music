import 'dart:async';

import '../../core/models/music.dart';
import '../../sources/builtin/builtin_search.dart';
import '../../core/services/logger.dart';

/// 每日推荐的数据源。
///
/// 说明（实测结论，不是猜测）：
/// - 内置五平台 SDK **没有**「每日推荐 / 榜单」这类官方接口
/// - lx/MusicFree 插件只声明了 boardList 的部分源，且多数未实现
///
/// 所以这里用「多歌手种子 → 各平台取曲 → 去重混排」构造一份**真实可播**的
/// 推荐列表。它不是算法推荐，但每首都是真歌、能播、有封面——
/// 比原先播放内置 demo 和弦音是实质改进。
class DailyRecommend {
  const DailyRecommend._();

  /// 可替换的取数实现。
  /// 测试环境（flutter_test）会屏蔽真实网络且不允许挂起定时器，
  /// 单测可替换为返回固定列表，避免冒烟测试失败。
  static Future<List<MusicInfo>> Function()? overrideFetcher;

  /// 取推荐（测试可注入）。生产走 [_fetchReal]。
  static Future<List<MusicInfo>> fetchOrOverride({int size = 24}) {
    final o = overrideFetcher;
    if (o != null) return o();
    return _fetchReal(size: size);
  }

  /// 种子歌手池。按日期轮换，保证「每天不一样」且无需服务端。
  static const _seedPool = [
    '周杰伦', '林俊杰', '陈奕迅', '邓紫棋', '五月天',
    '李荣浩', '毛不易', '薛之谦', '王菲', '孙燕姿',
    '陶喆', '张学友', '田馥甄', '华晨宇', '告五人',
    '任然', '周深', '梁静茹', '朴树', '许嵩',
  ];

  static const _platforms = ['kw', 'tx', 'wy'];

  /// 取今日推荐（同一天内结果稳定）。
  static Future<List<MusicInfo>> _fetchReal({int size = 24}) async {
    final day = DateTime.now();
    final seed = day.year * 1000 + day.month * 40 + day.day;
    final start = seed % _seedPool.length;

    // 今天用 4 位歌手做种子，各取一批后交叉混排
    final picked = <String>[
      for (var i = 0; i < 4; i++) _seedPool[(start + i * 5) % _seedPool.length],
    ];

    final buckets = <List<MusicInfo>>[];
    for (final singer in picked) {
      try {
        final groups = await BuiltinSearch.searchAll(
          singer,
          enabled: _platforms.toSet(),
          limit: 12,
        );
        for (final g in groups) {
          if (g.songs.isEmpty) continue;
          // 只保留确实匹配该歌手的结果，避免翻唱/伴奏混入
          final matched = [
            for (final s in g.songs)
              if (s.artist.contains(singer) &&
                  !s.title.contains('伴奏') &&
                  !s.title.contains('纯音乐') &&
                  !s.title.toLowerCase().contains('cover'))
                s,
          ];
          if (matched.isNotEmpty) buckets.add(matched);
        }
      } catch (e) {
        AppLog.w('DailyRecommend', '种子 $singer 取曲失败: $e');
      }
    }

    if (buckets.isEmpty) {
      AppLog.w('DailyRecommend', '今日推荐无数据（所有平台均失败）');
      return const [];
    }

    // 交叉混排：轮流从各桶取，避免同平台/同歌手扎堆
    final out = <MusicInfo>[];
    final seen = <String>{};
    var idx = 0;
    while (out.length < size) {
      var added = false;
      for (final b in buckets) {
        if (idx >= b.length) continue;
        final s = b[idx];
        final key = '${s.title}|${s.artist}'.toLowerCase();
        if (seen.add(key)) {
          out.add(s);
          added = true;
          if (out.length >= size) break;
        }
      }
      if (!added) break;
      idx++;
    }
    AppLog.i('DailyRecommend',
        '今日推荐 ${out.length} 首（种子: ${picked.join('/')}）');
    return out;
  }
}