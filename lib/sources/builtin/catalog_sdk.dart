import 'dart:convert';

import '../../core/services/logger.dart';
import 'builtin_base.dart';

/// 搜索结果的四类（对齐参考工程 SearchCategory）。
///
/// 为什么需要分类：只搜歌曲时，用户找「周杰伦的专辑」「某个歌单」
/// 是搜不到的——这类结果不在歌曲结果集里。参考工程把它们拆成
/// 独立 Tab，并且**歌手搜索做得更强**（能直接点到艺人页）。
enum SearchKind { song, album, playlist, artist }

/// 一条非歌曲结果（专辑 / 歌单 / 艺人）。
class CatalogHit {
  const CatalogHit({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.picUrl,
    this.extra = '',
  });

  final SearchKind kind;

  /// 该类型在所属平台内的 id（专辑 id / 歌单 id / 艺人 id）。
  final String id;
  final String title;

  /// 副标题：专辑→歌手，歌单→创建者/歌曲数，艺人→地区/粉丝数
  final String subtitle;
  final String? picUrl;

  /// 额外信息（歌曲数、专辑数等），用于 UI 上的次要说明。
  final String extra;
}

/// 多平台分类搜索（歌曲以外的专辑 / 歌单 / 艺人）。
///
/// 只做**网易 + 酷我**两家：实测这两家的分类接口当前可用，
/// QQ/酷狗/咪咕的分类接口需要 App 端签名或已下线（见 CHANGELOG）。
/// 歌曲搜索仍走既有的 BuiltinSearch（五平台齐全）。
class CatalogSdk {
  CatalogSdk._();

  /// 按类型搜索。返回空列表表示该平台无结果或不支持。
  static Future<List<CatalogHit>> search({
    required SearchKind kind,
    required String keyword,
    String source = 'wy',
    int limit = 20,
  }) async {
    if (keyword.trim().isEmpty) return const [];
    try {
      return switch (source) {
        'kw' => await _kuwo(kind, keyword, limit),
        _ => await _netease(kind, keyword, limit),
      };
    } catch (e) {
      AppLog.w('CatalogSdk', '$source/${kind.name} 搜索失败: $e');
      return const [];
    }
  }

  // ————————————————— 网易 —————————————————
  //
  // type: 1=单曲 10=专辑 1000=歌单 100=歌手
  // 返回 result.albums / result.playlists / result.artists
  static Future<List<CatalogHit>> _netease(
      SearchKind kind, String keyword, int limit) async {
    final type = switch (kind) {
      SearchKind.song => 1,
      SearchKind.album => 10,
      SearchKind.playlist => 1000,
      SearchKind.artist => 100,
    };
    final raw = await BuiltinHttp.getJson(
      'https://music.163.com/api/search/get'
      '?s=${Uri.encodeComponent(keyword)}&type=$type&limit=$limit',
      headers: const {'Referer': 'https://music.163.com/'},
    );
    final body = tryDecodeJson(raw);
    if (body is! Map) return const [];
    final result = body['result'];
    if (result is! Map) return const [];

    final out = <CatalogHit>[];
    switch (kind) {
      case SearchKind.album:
        for (final a in (result['albums'] as List? ?? const [])) {
          if (a is! Map) continue;
          final id = '${a['id'] ?? ''}';
          if (id.isEmpty) continue;
          final artist = a['artist'];
          out.add(CatalogHit(
            kind: kind,
            id: id,
            title: '${a['name'] ?? ''}',
            subtitle: artist is Map ? '${artist['name'] ?? ''}' : '',
            picUrl: '${a['picUrl'] ?? ''}'.isEmpty
                ? null
                : '${a['picUrl']}',
          ));
        }
      case SearchKind.playlist:
        for (final p in (result['playlists'] as List? ?? const [])) {
          if (p is! Map) continue;
          final id = '${p['id'] ?? ''}';
          if (id.isEmpty) continue;
          out.add(CatalogHit(
            kind: kind,
            id: id,
            title: '${p['name'] ?? ''}',
            subtitle: '${p['trackCount'] ?? 0} 首',
            picUrl:
                '${p['coverImgUrl'] ?? ''}'.isEmpty ? null : '${p['coverImgUrl']}',
            extra: '${p['playCount'] ?? 0}',
          ));
        }
      case SearchKind.artist:
        for (final a in (result['artists'] as List? ?? const [])) {
          if (a is! Map) continue;
          final id = '${a['id'] ?? ''}';
          if (id.isEmpty) continue;
          out.add(CatalogHit(
            kind: kind,
            id: id,
            title: '${a['name'] ?? ''}',
            subtitle: _firstAlias(a['alias']),
            picUrl: '${a['picUrl'] ?? ''}'.isEmpty ? null : '${a['picUrl']}',
            extra: '${a['albumSize'] ?? 0}',
          ));
        }
      case SearchKind.song:
        // 歌曲走 BuiltinSearch，这里不重复实现
        break;
    }
    return out;
  }

  /// 解析酷我的"伪 JSON"。
  ///
  /// 酷我部分接口（如 ft=album）返回的是 **Python dict 风格**：
  ///   {'SHOW':'3','albumlist':[{...}]}
  /// 单引号不是合法 JSON，tryDecodeJson 会直接返回 null，
  /// 表现为"接口有数据但解析出 0 条"（实测酷我专辑/歌单都栽在这）。
  ///
  /// 这里做最小安全转换：单引号 → 双引号，并把内容里转义过的单引号还原。
  /// 不做通用解析器——只为这一家接口服务。
  static dynamic decodeKuwoPseudoJson(dynamic raw) {
    final strict = tryDecodeJson(raw);
    if (strict != null) return strict;
    if (raw is! String) return null;
    try {
      // 先把值内的 \' 临时替换，避免误伤
      final tmp = raw.replaceAll(r"\'", '\u0001');
      final fixed = tmp
          .replaceAll("'", '"')
          .replaceAll('\u0001', "'");
      return jsonDecode(fixed);
    } catch (_) {
      return null;
    }
  }

  /// 酷我字段清洗。
  ///
  /// 除了 HTML 实体（&nbsp; &amp;），部分字段还残留 JSON 层面的
  /// Unicode 转义（实测 `周杰伦\u0026言承旭` —— 界面会直接显示
  /// 反斜杠和 u0026，很难看）。这里一并还原。
  static String _cleanKuwo(dynamic raw) {
    var s = '${raw ?? ''}';
    // \uXXXX → 实际字符
    s = s.replaceAllMapped(
      RegExp(r'\\u([0-9a-fA-F]{4})'),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
    );
    // 单引号转义残留：\& \' 等（酷我把 ' 写成 \' 后我们转换时留下的）
    s = s.replaceAll(r"\&", '&');
    s = s.replaceAll(r"\'", "'");
    s = s.replaceAll(r'\"', '"');
    return decodeText(s);
  }

  /// 取艺人别名列表的第一项（网易 artists[].alias 是 List）。
  static String _firstAlias(Object? alias) {
    if (alias is List && alias.isNotEmpty) return '${alias.first}';
    return '';
  }

  // ————————————————— 酷我 —————————————————
  //
  // 实测可用的 ft 取值：
  //   ft=playlist → abslist[]（name / pic）
  //   ft=artist   → abslist[]（ARTIST / ARTISTID）
  //   ft=album + v4=1 → albumlist[]（album / albumid / pic）
  static Future<List<CatalogHit>> _kuwo(
      SearchKind kind, String keyword, int limit) async {
    final q = Uri.encodeComponent(keyword);
    switch (kind) {
      case SearchKind.playlist:
        final raw = await BuiltinHttp.getJson(
          'https://search.kuwo.cn/r.s?client=kt&all=$q&pn=0&rn=$limit'
          '&uid=794762570&ver=kwplayer_ar_9.2.2.1&vipver=1'
          '&show_copyright_off=1&newver=1&ft=playlist&cluster=0'
          '&strategy=2012&encoding=utf8&rformat=json&vermerge=1&mobi=1',
        );
        final body = decodeKuwoPseudoJson(raw);
        if (body is! Map) return const [];
        return [
          // 歌单的 id 字段是 playlistid（不是 id）——写错会全部被过滤成空列表
          for (final p in (body['abslist'] as List? ?? const []))
            if (p is Map && '${p['playlistid'] ?? ''}'.isNotEmpty)
              CatalogHit(
                kind: kind,
                id: '${p['playlistid']}',
                title: _cleanKuwo(p['name']),
                subtitle: _cleanKuwo(p['nickname']),
                picUrl:
                    '${p['pic'] ?? ''}'.isEmpty ? null : '${p['pic']}',
                extra: '${p['playcnt'] ?? 0}',
              ),
        ];

      case SearchKind.artist:
        final raw = await BuiltinHttp.getJson(
          'https://search.kuwo.cn/r.s?client=kt&all=$q&pn=0&rn=$limit'
          '&uid=794762570&ver=kwplayer_ar_9.2.2.1&vipver=1'
          '&show_copyright_off=1&newver=1&ft=artist&cluster=0'
          '&strategy=2012&encoding=utf8&rformat=json&vermerge=1&mobi=1',
        );
        final body = decodeKuwoPseudoJson(raw);
        if (body is! Map) return const [];
        return [
          for (final a in (body['abslist'] as List? ?? const []))
            if (a is Map && '${a['ARTISTID'] ?? ''}'.isNotEmpty)
              CatalogHit(
                kind: kind,
                id: '${a['ARTISTID']}',
                title: _cleanKuwo(a['ARTIST']),
              ),
        ];

      case SearchKind.album:
        final raw = await BuiltinHttp.getJson(
          'https://search.kuwo.cn/r.s?all=$q&ft=album&rn=$limit&pn=0'
          '&rformat=json&encoding=utf8&vipver=1&client=kt&v4=1',
        );
        final body = decodeKuwoPseudoJson(raw);
        if (body is! Map) return const [];
        return [
          for (final a in (body['albumlist'] as List? ?? const []))
            if (a is Map && '${a['albumid'] ?? ''}'.isNotEmpty)
              CatalogHit(
                kind: kind,
                id: '${a['albumid']}',
                // 酷我专辑字段是 name（不是 album）；封面只给相对路径 pic，
                // 需拼成完整 CDN 地址，否则 UI 上会裂图。
                title: _cleanKuwo(a['name']),
                subtitle: _cleanKuwo(a['artist']),
                picUrl: '${a['pic'] ?? ''}'.isEmpty
                    ? null
                    : 'https://img2.kuwo.cn/star/albumcover/${a['pic']}',
                extra: '${a['musiccnt'] ?? 0}',
              ),
        ];

      case SearchKind.song:
        return const [];
    }
  }
}