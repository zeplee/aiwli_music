import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:aiwli_music/core/models/quality.dart';
import 'package:aiwli_music/core/services/settings_prefs.dart';

void main() {
  test('默认值符合现有工程约定', () {
    const p = SettingsPrefs();
    expect(p.defaultSearchSource, 'wy');
    expect(p.enabledSearchSources, {'kw', 'tx', 'wy', 'kg', 'mg'});
    expect(p.searchResultAction, 'play');
    expect(p.downloadQuality, Quality.standard);
    expect(p.downloadFileNameStyle, 'artist_title');
  });

  test('fromMap 逐字段校验，坏值只回退自己不污染其他字段', () {
    final p = SettingsPrefs.fromMap({
      'defaultSearchSource': 'nope',
      'enabledSearchSources': ['wy', 'bogus', 'kg'],
      'searchResultAction': 'replaceQueue',
      'downloadQuality': 'lossless',
      'downloadFileNameStyle': 'bad',
    });
    expect(p.defaultSearchSource, 'wy');
    expect(p.enabledSearchSources, {'wy', 'kg'}, reason: '非法源被过滤');
    expect(p.searchResultAction, 'replaceQueue', reason: '合法字段保留');
    expect(p.downloadQuality, Quality.lossless);
    expect(p.downloadFileNameStyle, 'artist_title');
  });

  test('enabledSearchSources 全非法时回退全部启用', () {
    final p = SettingsPrefs.fromMap({
      'enabledSearchSources': ['x', 'y'],
    });
    expect(p.enabledSearchSources, {'kw', 'tx', 'wy', 'kg', 'mg'});
  });

  test('toJson / fromMap 往返一致', () {
    const p = SettingsPrefs(
      defaultSearchSource: 'tx',
      enabledSearchSources: {'tx', 'wy'},
      searchResultAction: 'replaceQueue',
      downloadQuality: Quality.hires,
      downloadFileNameStyle: 'title_artist',
    );
    final json = jsonDecode(jsonEncode(p.toJson())) as Map<Object?, Object?>;
    final back = SettingsPrefs.fromMap(json);
    expect(back.toJson(), p.toJson());
  });

  test('applyFromJson 合法字段应用、非法字段跳过并给出说明', () {
    SettingsPrefs? applied;
    final warnings = SettingsPrefs.applyFromJson({
      'defaultSearchSource': 'kg',
      'enabledSearchSources': ['kg', 'wy'],
      'searchResultAction': 'bogus',
      'downloadQuality': 'flac',
      'downloadFileNameStyle': 'title_artist',
    }, (p) => applied = p);

    expect(applied, isNotNull);
    expect(applied!.defaultSearchSource, 'kg');
    expect(applied!.enabledSearchSources, {'kg', 'wy'});
    expect(applied!.searchResultAction, 'play', reason: '非法值跳过用默认');
    expect(applied!.downloadQuality, Quality.standard);
    expect(applied!.downloadFileNameStyle, 'title_artist');
    expect(warnings.length, 2);
  });

  test('导入时默认平台不在已启用集合内会自动补入', () {
    SettingsPrefs? applied;
    SettingsPrefs.applyFromJson({
      'defaultSearchSource': 'mg',
      'enabledSearchSources': ['wy'],
    }, (p) => applied = p);
    expect(applied!.enabledSearchSources.contains('mg'), isTrue);
    expect(applied!.enabledSearchSources.length, greaterThan(0));
  });

  test('导入空 sources 不产生空集合（至少保留 1 个）', () {
    SettingsPrefs? applied;
    final warnings = SettingsPrefs.applyFromJson({
      'enabledSearchSources': <String>[],
    }, (p) => applied = p);
    expect(applied!.enabledSearchSources, isNotEmpty);
    expect(warnings, isNotEmpty);
  });

  test('toJson 不含任何敏感字段', () {
    final keys = const SettingsPrefs().toJson().keys.toList();
    expect(keys, unorderedEquals([
      'defaultSearchSource',
      'enabledSearchSources',
      'searchResultAction',
      'downloadQuality',
      'downloadFileNameStyle',
    ]));
    expect(keys.any((k) => k.toLowerCase().contains('pass')), isFalse);
    expect(keys.any((k) => k.toLowerCase().contains('token')), isFalse);
    expect(keys.any((k) => k.toLowerCase().contains('webdav')), isFalse);
  });

  test('copyWith 只改指定字段', () {
    const p = SettingsPrefs();
    final q = p.copyWith(defaultSearchSource: 'kw');
    expect(q.defaultSearchSource, 'kw');
    expect(q.downloadQuality, p.downloadQuality);
    expect(q.searchResultAction, p.searchResultAction);
  });
}
