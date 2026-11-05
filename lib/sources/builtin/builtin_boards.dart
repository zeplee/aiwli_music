import '../../core/models/music.dart';

/// 内置五平台榜单：**不依赖任何 lx 脚本**。
///
/// 为什么必须内置（实测结论）：
///   lx 脚本的取链后端正在大面积失效（如 music-dl.sayqz.com 已 NXDOMAIN），
///   榜单跟着一起挂，用户看到的就是"排行榜空了"。
///   而各平台官方榜单接口实测全部可用：
///     · 酷我 kbangserver.kuwo.cn/ksong.s?id=93    → 300 首
///     · 网易 music.163.com/api/playlist/detail    → 200 首
///     · QQ   u.y.qq.com musicToplist.GetDetail    → 有数据
///     · 酷狗 mobilecdn.kugou.com/api/v3/rank/*    → 56 个榜
///     · 咪咕 app.c.nf.migu.cn columnId=27186466   → 100 首
///
/// 每个平台提供：榜单列表（静态 id 表）+ 按 id 取曲。
class BuiltinBoards {
  const BuiltinBoards._();

  /// 各平台内置榜单（只放常用榜，避免列表过长）。
  static const Map<String, List<MusicBoard>> catalog = {
    'kw': [
      MusicBoard(id: '16', name: '酷我热歌榜'),
      MusicBoard(id: '17', name: '酷我新歌榜'),
      MusicBoard(id: '93', name: '酷我飙升榜'),
      MusicBoard(id: '158', name: '抖音热歌榜'),
      MusicBoard(id: '284', name: '酷我热评榜'),
    ],
    'wy': [
      MusicBoard(id: '3778678', name: '网易热歌榜'),
      MusicBoard(id: '3779629', name: '网易新歌榜'),
      MusicBoard(id: '19723756', name: '网易飙升榜'),
      MusicBoard(id: '2884035', name: '网易原创榜'),
    ],
    'tx': [
      MusicBoard(id: '26', name: 'QQ热歌榜'),
      MusicBoard(id: '27', name: 'QQ新歌榜'),
      MusicBoard(id: '4', name: 'QQ飙升榜'),
      MusicBoard(id: '62', name: 'QQ欧美榜'),
    ],
    'kg': [
      MusicBoard(id: '8888', name: '酷狗TOP500'),
      MusicBoard(id: '6666', name: '酷狗飙升榜'),
      MusicBoard(id: '74534', name: '酷狗新歌榜'),
      MusicBoard(id: '31308', name: '酷狗内地榜'),
    ],
    'mg': [
      MusicBoard(id: '27186466', name: '咪咕尖叫热歌榜'),
      MusicBoard(id: '27553319', name: '咪咕新歌榜'),
      MusicBoard(id: '27553408', name: '咪咕原创榜'),
      MusicBoard(id: '75959118', name: '咪咕音乐风向榜'),
    ],
  };

  /// 平台展示名。
  static const Map<String, String> labels = {
    'kw': '酷我',
    'wy': '网易云',
    'tx': 'QQ音乐',
    'kg': '酷狗',
    'mg': '咪咕',
  };

  /// 该平台是否有内置榜单。
  static bool has(String sourceId) => catalog.containsKey(sourceId);

  /// 全部内置榜单（带平台前缀，便于在发现页统一展示）。
  static List<({String sourceId, MusicBoard board})> all() => [
        for (final e in catalog.entries)
          for (final b in e.value) (sourceId: e.key, board: b),
      ];
}