import 'dart:convert';

import '../../sources/builtin/builtin_base.dart';
import '../../sources/builtin/catalog_sdk.dart' show CatalogHit, SearchKind;

/// 精选歌单「分类浏览」数据源（纯 Dart，零签名、零新增依赖）。
///
/// 与 `CatalogSdk.search()` 的区别：
///  - `CatalogSdk` 是关键词搜索，只有 wy/kw 实现（QQ/酷狗/咪咕的搜索
///    需要签名或已下线）；
///  - 本类是各家**公开 featured 浏览接口**，腾讯/酷狗/咪咕都有无需签名
///    的专用入口，只返回歌单的 id/标题/封面/作者/曲目数，不含任何
///    播放地址 —— 与「零内置取链」约束完全无关。
///
/// 参考了栖弦 v1.1.3 `PlaylistCatalogSdk.featured` 的接口语义，
/// 但按本工程的模型与 HTTP 底座重新实现。
class PlaylistCatalog {
  PlaylistCatalog._();

  /// 支持分类浏览的平台（与内置榜单的 5 家一致）。
  static const supportedSources = <String>['wy', 'kw', 'tx', 'kg', 'mg'];

  /// 每个平台可选分类（id → 展示名）。网易/咪咕只有一个分类，
  /// UI 上应隐藏分类切换而不是给一个空菜单。
  static const Map<String, List<({String id, String label})>> categories = {
    'wy': [(id: 'hot', label: '热门')],
    'kw': [
      (id: 'new', label: '最新'),
      (id: 'hot', label: '最热'),
    ],
    'tx': [
      (id: '-1', label: '推荐'),
      (id: '3', label: '最热'),
      (id: '2', label: '最新'),
    ],
    'kg': [
      (id: '5', label: '推荐'),
      (id: '6', label: '最热'),
      (id: '7', label: '最新'),
      (id: '3', label: '热藏'),
      (id: '8', label: '飙升'),
    ],
    'mg': [(id: '15127315', label: '推荐')],
  };

  static Future<List<CatalogHit>> featured({
    required String source,
    String categoryId = '',
    int limit = 12,
  }) async {
    final cat = categoryId.isEmpty
        ? categories[source]?.first.id ?? ''
        : categoryId;
    try {
      final list = switch (source) {
        'kw' => await _kw(cat, limit),
        'kg' => await _kg(cat, limit),
        'tx' => await _tx(cat, limit),
        'wy' => await _wy(cat, limit),
        'mg' => await _mg(cat, limit),
        _ => <CatalogHit>[],
      };
      final seen = <String>{};
      return list
          .where((h) => h.id.isNotEmpty && h.title.isNotEmpty && seen.add(h.id))
          .take(limit)
          .toList(growable: false);
    } catch (e) {
      return const <CatalogHit>[];
    }
  }

  // ——————————————— 网易 ———————————————
  static Future<List<CatalogHit>> _wy(String cat, int limit) async {
    final raw = await BuiltinHttp.getJson(
      'https://music.163.com/api/playlist/list'
      '?cat=${Uri.encodeComponent('全部')}&order=$cat&limit=$limit&offset=0',
      headers: const {'Referer': 'https://music.163.com/'},
    );
    final rows = (raw is Map ? raw['playlists'] : null) as List? ?? const [];
    return [
      for (final e in rows)
        if (e is Map) _hit(
          id: '${e['id'] ?? ''}',
          title: _text(e['name']),
          subtitle: (e['creator'] is Map)
              ? _text((e['creator'] as Map)['nickname'])
              : '',
          picUrl: _text(e['coverImgUrl']),
          extra: _countLabel(e['trackCount']),
        ),
    ];
  }

  // ——————————————— 酷我 ———————————————
  static Future<List<CatalogHit>> _kw(String cat, int limit) async {
    final raw = await BuiltinHttp.getJson(
      'http://wapi.kuwo.cn/api/pc/classify/playlist/getRcmPlayList'
      '?loginUid=0&loginSid=0&appUid=76039576&pn=1&rn=$limit&order=$cat',
    );
    final body = raw is Map ? raw['data'] : null;
    final rows = (body is Map ? body['data'] : null) as List? ?? const [];
    return [
      for (final e in rows)
        if (e is Map) _hit(
          id: '${e['id'] ?? ''}',
          title: _text(e['name']),
          subtitle: _text(e['uname']),
          picUrl: _firstText(e['img'], e['hts_img'], e['pic']),
          extra: _countLabel(e['total']),
        ),
    ];
  }

  // ——————————————— 酷狗 ———————————————
  static Future<List<CatalogHit>> _kg(String cat, int limit) async {
    final raw = await BuiltinHttp.getJson(
      'http://www2.kugou.kugou.com/yueku/v9/special/getSpecial'
      '?is_ajax=1&cdn=cdn&t=$cat&c=&p=1',
      headers: const {'Referer': 'https://www.kugou.com/'},
    );
    if (raw is! Map || raw['status'] != 1) return const [];
    final rows = (raw['special_db'] as List?) ?? const [];
    return [
      for (final e in rows)
        if (e is Map) _hit(
          id: '${e['specialid'] ?? ''}',
          title: _text(e['specialname']),
          subtitle: _text(e['nickname']),
          picUrl: _firstText(e['img'], e['imgurl']),
          extra: _countLabel(e['songcount']),
        ),
    ].take(limit).toList();
  }

  // ——————————————— QQ 音乐 ———————————————
  static Future<List<CatalogHit>> _tx(String cat, int limit) async {
    final param = cat == '-1'
        ? {
            'module': 'music.playlist.PlaylistSquare',
            'method': 'GetRecommendWhole',
            'param': {'page': 1, 'size': limit},
          }
        : {
            'module': 'playlist.PlayListCategoryServer',
            'method': 'get_category_content',
            'param': {
              'titleid': cat,
              'caller': '0',
              'category_id': cat,
              'size': limit,
              'page': 0,
              'use_page': 1,
            },
          };
    final request = {
      'comm': {'cv': 1602, 'ct': 20},
      'req': param,
    };
    final encoded = Uri.encodeComponent(jsonEncode(request));
    final raw = await BuiltinHttp.getJson(
      'https://u.y.qq.com/cgi-bin/musicu.fcg?data=$encoded',
      headers: const {'Referer': 'https://y.qq.com/'},
    );
    if (raw is! Map || raw['code'] != 0) return const [];
    final req = raw['req'];
    if (req is! Map || req['code'] != 0) return const [];
    final data = req['data'];
    if (data is! Map) return const [];

    // 推荐接口：req.data.FeedRsp.List[].Playlist.basic
    final feed = (data['FeedRsp'] is Map)
        ? (data['FeedRsp'] as Map)['List'] as List? ?? const []
        : const [];
    // 分类接口：req.data.content.v_item[].basic
    final content = (data['content'] is Map)
        ? (data['content'] as Map)['v_item'] as List? ?? const []
        : const [];

    final out = <CatalogHit>[];
    for (final e in [...feed, ...content]) {
      if (e is! Map) continue;
      final p = (e['Playlist'] is Map)
          ? (e['Playlist'] as Map)['basic']
          : e['basic'];
      if (p is! Map) continue;
      final cover = p['cover'];
      out.add(_hit(
        id: _text(p['tid']),
        title: _decodeEntities(_text(p['title'])),
        subtitle: (p['creator'] is Map)
            ? _text((p['creator'] as Map)['nick'])
            : '',
        picUrl: (cover is Map)
            ? _firstText(cover['medium_url'], cover['large_url'])
            : '',
        extra: _countLabel(p['song_cnt']),
      ));
    }
    return out.take(limit).toList();
  }

  // ——————————————— 咪咕 ———————————————
  static Future<List<CatalogHit>> _mg(String cat, int limit) async {
    final raw = await BuiltinHttp.getJson(
      'https://app.c.nf.migu.cn/pc/bmw/page-data/playlist-square-recommend/v1.0'
      '?templateVersion=2&pageNo=1',
      headers: const {
        'Referer': 'https://m.music.migu.cn/',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 11.0.0) AppleWebKit/537.36 Mobile Safari/537.36',
      },
    );
    if (raw is! Map) return const [];
    final out = <CatalogHit>[];
    // 咪咕返回一棵 contents 树，歌单节点标记 resType=='2021'，需递归收集。
    void walk(Object? node) {
      if (out.length >= limit) return;
      if (node is List) {
        for (final e in node) {
          walk(e);
          if (out.length >= limit) return;
        }
        return;
      }
      if (node is! Map) return;
      if ('${node['resType'] ?? ''}' == '2021') {
        final id = _text(node['resId']);
        if (id.isNotEmpty) {
          out.add(_hit(
            id: id,
            title: _text(node['txt']),
            subtitle: _text(node['txt2']),
            picUrl: _firstText(node['img'], node['pic']),
          ));
          return;
        }
      }
      for (final value in node.values) {
        walk(value);
        if (out.length >= limit) return;
      }
    }

    walk(raw['data']);
    return out;
  }

  static CatalogHit _hit({
    required String id,
    required String title,
    required String subtitle,
    required String picUrl,
    String extra = '',
  }) =>
      CatalogHit(
        kind: SearchKind.playlist,
        id: id,
        title: title,
        subtitle: subtitle,
        picUrl: picUrl.isEmpty ? null : picUrl,
        extra: extra,
      );

  static String _countLabel(Object? n) {
    final s = _text(n);
    return s.isEmpty || s == '0' ? '' : '$s 首';
  }

  static String _text(Object? v) => v == null ? '' : v.toString().trim();

  static String _firstText(Object? a, Object? b, [Object? c]) {
    for (final v in [a, b, c]) {
      final s = _text(v);
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static String _decodeEntities(String s) => s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}
