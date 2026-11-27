import 'package:flutter_test/flutter_test.dart';
import 'package:aiwli_music/core/models/music.dart';
import 'package:aiwli_music/features/discover/playlist_selection.dart';

MusicInfo _song(String title, String artist, [String album = '']) =>
    MusicInfo(
      sourceId: 'wy',
      musicId: title,
      title: title,
      artist: artist,
      album: album.isEmpty ? null : Album(id: 'a', name: album),
    );

void main() {
  group('filterPlaylistSongs', () {
    final songs = [
      _song('晴天', '周杰伦', '叶惠美'),
      _song('夜曲', '周杰伦', '十一月的萧邦'),
      _song('演员', '薛之谦', '绅士'),
    ];

    test('空关键词返回全部', () {
      expect(filterPlaylistSongs(songs, '   ').length, 3);
    });

    test('歌名匹配', () {
      expect(filterPlaylistSongs(songs, '晴天').map((m) => m.title), ['晴天']);
    });

    test('歌手匹配', () {
      expect(filterPlaylistSongs(songs, '周杰伦').length, 2);
    });

    test('专辑匹配', () {
      expect(filterPlaylistSongs(songs, '叶惠美').map((m) => m.title),
          ['晴天']);
    });

    test('多关键词 AND，且大小写不敏感', () {
      expect(
          filterPlaylistSongs(songs, '周杰伦 晴天').map((m) => m.title),
          ['晴天']);
      expect(filterPlaylistSongs(songs, '周杰伦 演员'), isEmpty);
    });
  });

  group('PlaylistSelection', () {
    test('默认未激活', () {
      final s = PlaylistSelection();
      expect(s.active, isFalse);
      expect(s.isEmpty, isTrue);
    });

    test('enter/toggle/exit', () {
      final s = PlaylistSelection()..enter();
      s.toggle(0);
      s.toggle(2);
      expect(s.count, 2);
      s.toggle(0);
      expect(s.selected, {2});
      s.exit();
      expect(s.active, isFalse);
      expect(s.isEmpty, isTrue);
    });

    test('selectAll / invert', () {
      final s = PlaylistSelection()..enter();
      s.selectAll(4);
      expect(s.count, 4);
      s.invert(4);
      expect(s.isEmpty, isTrue);
      s.invert(4);
      expect(s.count, 4);
    });
  });
}
