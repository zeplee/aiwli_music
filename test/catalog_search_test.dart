@Tags(['network'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/sources/builtin/catalog_sdk.dart';

/// 分类搜索（专辑 / 歌单 / 艺人）实测。
///
/// 背景：只搜歌曲时，用户找「周杰伦的专辑」「某个歌单」「艺人」
/// 是搜不到的——这些结果不在歌曲结果集里。参考工程把它们拆成
/// 独立分类 Tab。
///
/// 实测结论（本测试锁定）：
///   · 网易三种分类接口今天全部可用
///   · 酷我 album/playlist/artist 需要 ft 参数 + 伪 JSON 解析
///   · QQ/酷狗/咪咕的分类接口需要 App 签名或已下线，不做
void main() {
  test('网易：专辑 / 歌单 / 艺人 三类都能搜到', () async {
    for (final k in [
      SearchKind.album,
      SearchKind.playlist,
      SearchKind.artist,
    ]) {
      final r = await CatalogSdk.search(
          kind: k, keyword: '周杰伦', source: 'wy', limit: 3);
      expect(r, isNotEmpty, reason: '网易 ${k.name} 应有结果');
      expect(r.first.title, isNotEmpty, reason: '标题不能为空');
      expect(r.first.id, isNotEmpty, reason: 'id 不能为空');
    }
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('酷我：专辑 / 歌单 / 艺人 三类都能搜到', () async {
    for (final k in [
      SearchKind.album,
      SearchKind.playlist,
      SearchKind.artist,
    ]) {
      final r = await CatalogSdk.search(
          kind: k, keyword: '周杰伦', source: 'kw', limit: 3);
      expect(r, isNotEmpty, reason: '酷我 ${k.name} 应有结果');
      expect(r.first.title, isNotEmpty);
      expect(r.first.id, isNotEmpty);
    }
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('酷我专辑：字段名是 name 而不是 album（写错会全空）', () async {
    final r = await CatalogSdk.search(
        kind: SearchKind.album, keyword: '周杰伦', source: 'kw', limit: 3);
    expect(r, isNotEmpty);
    // 修复前拿到的是空标题（用了 a['album']）
    expect(r.first.title.trim(), isNotEmpty,
        reason: '酷我专辑字段是 name，用 album 会得到空串');
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('酷我歌单：id 字段是 playlistid（写错会全被过滤）', () async {
    final r = await CatalogSdk.search(
        kind: SearchKind.playlist, keyword: '周杰伦', source: 'kw', limit: 3);
    expect(r, isNotEmpty,
        reason: '修复前用 p["id"] 判断，导致整列表被过滤成空');
    expect(r.first.id, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('酷我字段清洗：HTML 实体与 \\uXXXX 转义都要还原', () async {
    final r = await CatalogSdk.search(
        kind: SearchKind.album, keyword: '周杰伦', source: 'kw', limit: 5);
    for (final h in r) {
      expect(h.title.contains(r'\u'), isFalse,
          reason: '不该出现字面 \\u 转义：${h.title}');
      expect(h.subtitle.contains(r'\&'), isFalse,
          reason: '不该出现字面 \\& 转义：${h.subtitle}');
      expect(h.title.contains('&nbsp;'), isFalse);
    }
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('空关键词直接返回空，不发请求', () async {
    for (final k in SearchKind.values) {
      final r = await CatalogSdk.search(kind: k, keyword: '   ');
      expect(r, isEmpty);
    }
  });

  test('歌曲类型不走 CatalogSdk（由 BuiltinSearch 负责）', () async {
    final r = await CatalogSdk.search(
        kind: SearchKind.song, keyword: '周杰伦', source: 'wy');
    expect(r, isEmpty, reason: '走错入口会导致歌曲结果重复');
  });
}