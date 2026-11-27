/// 搜索联想建议（纯 Dart，不发网络请求）。
///
/// 数据来源只有两类本地信息：搜索历史 + 当前已加载结果里的歌名/歌手。
/// 这样输入过程零额外请求，也不会因为接口风控把联想词也拖垮。
List<String> searchSuggestions({
  required String input,
  required Iterable<String> history,
  Iterable<String> resultTitles = const [],
  Iterable<String> resultArtists = const [],
  int limit = 8,
}) {
  final q = input.trim().toLowerCase();
  if (q.isEmpty) return const <String>[];

  // 有序去重：历史优先，其次当前结果的歌名，再歌手名。
  final out = <String>[];
  final seen = <String>{};
  void add(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return;
    final k = s.toLowerCase();
    if (k == q || !k.contains(q)) return;
    if (!seen.add(k)) return;
    if (out.length < limit) out.add(s);
  }

  for (final h in history) {
    add(h);
  }
  for (final t in resultTitles) {
    add(t);
  }
  for (final a in resultArtists) {
    add(a);
  }
  return List<String>.unmodifiable(out);
}

/// 批量选择状态机（纯 Dart）：只存索引集合，便于测试真实现。
class SearchSelection {
  final Set<int> selected = <int>{};
  bool active = false;

  bool get isEmpty => selected.isEmpty;
  int get count => selected.length;

  void enter() {
    active = true;
  }

  void exit() {
    active = false;
    selected.clear();
  }

  void toggle(int index) {
    if (!selected.add(index)) selected.remove(index);
  }

  void selectAll(int count) {
    selected.addAll(List.generate(count, (i) => i));
  }

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
