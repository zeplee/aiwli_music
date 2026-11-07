import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/core/services/playlists.dart';
import 'package:aiwli_music/features/library/playlist_search.dart';

/// 歌单内歌曲搜索（对齐参考工程 playlist_search.dart 的语义）。
///
/// 关键不变量：**返回结果必须带原始下标**。
/// 歌单列表的点击播放、多选、移出都用 playlist.entries 的原位置
/// 索引；如果过滤后重新编号，用户点第 1 条会播到别的歌。
void main() {
  PlaylistEntry e(String title, String artist,
          {String? album, String? localPath}) =>
      PlaylistEntry(
        sourceId: 'kw',
        musicId: title,
        title: title,
        artist: artist,
        album: album,
        resolvedPath: localPath,
      );

  final sample = [
    e('晴天', '周杰伦', album: '叶惠美'),
    e('稻香', '周杰伦', album: '魔杰座'),
    e('小幸运', '田馥甄', album: '我的少女时代'),
    e('山风山风等等我', '万海东'),
    e('demo_song', '本地歌手',
        localPath: '/storage/music/我的录音.mp3'),
  ];

  test('空查询返回全部，且下标连续', () {
    final r = filterEntriesByQuery(sample, '');
    expect(r.length, sample.length);
    expect(r.map((x) => x.index), [0, 1, 2, 3, 4]);
  });

  test('单关键词匹配歌名（大小写不敏感）', () {
    final r = filterEntriesByQuery(sample, '晴天');
    expect(r.length, 1);
    expect(r.first.index, 0, reason: '必须保留原始下标');
    expect(r.first.entry.title, '晴天');
  });

  test('匹配歌手', () {
    final r = filterEntriesByQuery(sample, '周杰伦');
    expect(r.map((x) => x.entry.title), ['晴天', '稻香']);
    expect(r.map((x) => x.index), [0, 1]);
  });

  test('匹配专辑', () {
    final r = filterEntriesByQuery(sample, '魔杰座');
    expect(r.single.entry.title, '稻香');
    expect(r.single.index, 1);
  });

  test('多关键词是 AND 不是 OR', () {
    // 「周杰伦 稻香」应只命中稻香，而不是把周杰伦的两首全列出来
    final r = filterEntriesByQuery(sample, '周杰伦 稻香');
    expect(r.length, 1);
    expect(r.single.entry.title, '稻香');

    // 反证：如果用 OR，会命中晴天和稻香两首
    expect(r.length, lessThan(filterEntriesByQuery(sample, '周杰伦').length));
  });

  test('关键词顺序无关', () {
    final a = filterEntriesByQuery(sample, '周杰伦 稻香');
    final b = filterEntriesByQuery(sample, '稻香 周杰伦');
    expect(a.map((x) => x.index), b.map((x) => x.index));
  });

  test('本地曲目用文件名匹配（标题与文件名不同时也能搜到）', () {
    // 标题是 demo_song，文件名是「我的录音」
    final byFileName = filterEntriesByQuery(sample, '我的录音');
    expect(byFileName.single.entry.title, 'demo_song');
    // 原标题依然可搜
    expect(filterEntriesByQuery(sample, 'demo').single.index, 4);
  });

  test('无匹配返回空而不是全部', () {
    expect(filterEntriesByQuery(sample, '不存在的歌'), isEmpty);
  });

  test('多余空白不影响结果', () {
    final r = filterEntriesByQuery(sample, '  周杰伦   稻香  ');
    expect(r.length, 1);
  });

  test('过滤后顺序与原列表一致（不重排）', () {
    final r = filterEntriesByQuery(sample, '周杰伦');
    expect(r[0].index, lessThan(r[1].index),
        reason: '保持原顺序，用户才能预期上下相邻关系');
  });
}