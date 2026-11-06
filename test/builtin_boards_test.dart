@Tags(['network'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/sources/builtin/board_songs.dart';
import 'package:aiwli_music/sources/builtin/builtin_boards.dart';

/// 内置五平台榜单：**不依赖 lx 脚本**的榜单数据源。
///
/// 为什么必须有（实测背景）：lx 脚本的取链后端会整片失效
/// （music-dl.sayqz.com 已 NXDOMAIN），榜单跟着一起挂。
/// 内置榜单走各平台官方接口，实测五平台全部可用。
void main() {
  test('五个平台都有榜单定义', () {
    expect(BuiltinBoards.catalog.keys.toSet(),
        {'kw', 'wy', 'tx', 'kg', 'mg'});
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

  test('五平台榜单都能取到真实曲目且字段完整', () async {
    for (final e in BuiltinBoards.catalog.entries) {
      final board = e.value.first;
      final songs = await BoardSongs.fetch(e.key, board.id, limit: 5);

      expect(songs, isNotEmpty, reason: '${e.key} 榜单应能取到曲');
      final s = songs.first;
      expect(s.sourceId, e.key);
      expect(s.musicId, isNotEmpty, reason: '${e.key} 曲目必须有 id');
      expect(s.title, isNotEmpty, reason: '${e.key} 曲目必须有标题');
      // 歌手不能为空——酷狗曾因字段名取错导致全空，这里锁死
      expect(s.artist, isNotEmpty, reason: '${e.key} 曲目必须有歌手');
      // ignore: avoid_print
      print('RESULT ${e.key} ${board.name}: ${songs.length} 首 | ${s.title} - ${s.artist}');
    }
  }, timeout: const Timeout(Duration(seconds: 150)));

  test('未知平台/坏 id 返回空列表而不是抛异常', () async {
    expect(await BoardSongs.fetch('nope', '1'), isEmpty);
    expect(await BoardSongs.fetch('kw', ''), isEmpty);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
