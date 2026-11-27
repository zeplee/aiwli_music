import '../../core/models/music.dart';

/// 详情内搜索过滤：歌名 / 歌手 / 专辑，多个关键词 AND 匹配。
/// 纯函数，可直接测真实现。
List<MusicInfo> filterPlaylistSongs(List<MusicInfo> songs, String query) {
  final words = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return List<MusicInfo>.unmodifiable(songs);
  return List<MusicInfo>.unmodifiable([
    for (final m in songs)
      if (words.every((w) {
        final haystack = '${m.title} ${m.artist} ${m.album?.name ?? ''}'
            .toLowerCase();
        return haystack.contains(w);
      }))
        m,
  ]);
}

/// 在线歌单批量选择状态机（纯 Dart）。
class PlaylistSelection {
  final Set<int> selected = <int>{};
  bool active = false;

  bool get isEmpty => selected.isEmpty;
  int get count => selected.length;

  void enter() => active = true;
  void exit() {
    active = false;
    selected.clear();
  }

  void toggle(int index) {
    if (!selected.add(index)) selected.remove(index);
  }

  void selectAll(int count) =>
      selected.addAll(List.generate(count, (i) => i));

  void invert(int count) {
    final next = <int>{};
    for (var i = 0; i < count; i++) {
      if (!selected.contains(i)) next.add(i);
    }
    selected
      ..clear()
      ..addAll(next);
  }
}
