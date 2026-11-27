import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/sources/builtin/builtin_boards.dart';
import 'package:aiwli_music/sources/builtin/builtin_search.dart';
import 'package:aiwli_music/sources/builtin/catalog_sdk.dart';

/// 从被 `@Tags(['network'])` 整体跳过的文件里拆出来的**纯逻辑**用例。
///
/// 原来文件级 tag 会把这些不发网络请求的断言一起跳过，导致榜单定义、
/// 搜索 Tab 状态机、分类搜索的短路契约长期没有测试保护。这里单独成文件，
/// 真实网络实测仍留在原文件并用 `flutter test --tags network --run-skipped` 跑。
void main() {
  test('五个平台都有榜单定义', () {
    expect(BuiltinBoards.catalog.keys.toSet(), {'kw', 'wy', 'tx', 'kg', 'mg'});
    for (final e in BuiltinBoards.catalog.entries) {
      expect(e.value, isNotEmpty, reason: '${e.key} 应有榜单');
      for (final b in e.value) {
        expect(b.id, isNotEmpty);
        expect(b.name, isNotEmpty);
      }
    }
  });

  test('all() 汇总所有平台榜单', () {
    final all = BuiltinBoards.all();
    expect(all.length,
        BuiltinBoards.catalog.values.fold<int>(0, (a, b) => a + b.length));
    expect(all.every((e) => e.board.id.isNotEmpty), isTrue);
  });

  test('SourceGroup 空结果时 hasResults=false、count=0', () {
    final g = SourceGroup(sourceId: 'kw', label: '酷我')
      ..state = SourceSearchState.done;
    expect(g.hasResults, isFalse);
    expect(g.count, 0);
    expect(g.label, '酷我');
  });

  test('五个平台标签齐全且顺序固定', () {
    expect(BuiltinSearch.labels.keys.toSet(), {'kw', 'kg', 'tx', 'wy', 'mg'});
    expect(BuiltinSearch.order, ['kw', 'tx', 'wy', 'kg', 'mg']);
  });

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
