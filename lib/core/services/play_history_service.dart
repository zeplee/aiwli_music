import 'dart:convert';

import '../storage/settings_store.dart';
import 'cover_backfill.dart';
import 'safe_notifier.dart';

/// 一条播放记录。
class HistoryItem {
  const HistoryItem({
    required this.sourceId,
    required this.musicId,
    required this.title,
    required this.artist,
    this.album,
    this.picUrl,
    this.durationMs,
    required this.playedAt,
  });

  factory HistoryItem.fromMap(Map<Object?, Object?> m) => HistoryItem(
        sourceId: m['sourceId'] as String? ?? '',
        musicId: m['musicId'] as String? ?? '',
        title: m['title'] as String? ?? '',
        artist: m['artist'] as String? ?? '',
        album: m['album'] as String?,
        picUrl: m['picUrl'] as String?,
        durationMs: (m['durationMs'] as num?)?.toInt(),
        playedAt: DateTime.tryParse(m['playedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  final String sourceId;
  final String musicId;
  final String title;
  final String artist;
  final String? album;
  final String? picUrl;
  final int? durationMs;
  final DateTime playedAt;

  String get key => '$sourceId/$musicId';

  Map<String, Object?> toJson() => {
        'sourceId': sourceId,
        'musicId': musicId,
        'title': title,
        'artist': artist,
        'album': album,
        'picUrl': picUrl,
        'durationMs': durationMs,
        'playedAt': playedAt.toIso8601String(),
      };
}

/// 最近播放：
/// - 同一首歌只保留一条（重播时提到最前并刷新时间），避免列表被单曲灌满
/// - 不设条数上限（见下方说明）
/// - SettingsStore JSON 持久化（与收藏/歌单同一套约定，无需 SQLite）
class PlayHistoryService extends SafeNotifier {
  PlayHistoryService(this._store);
  final SettingsStore _store;
  static const _file = 'play_history.json';
  /// 不设条数上限。
  ///
  /// 曾经的 200 条上限没有实际理由：1882 首的 JSON 约 560KB，
  /// 比歌单文件（614KB）还小，而歌单一直跑得好好的。
  /// 这里还藏着一个隐患——`importJson` 用 `take(maxItems)` 会让
  /// WebDAV 恢复**静默截断**用户的历史，属于数据丢失。
  /// 记录由用户自己管理（单条删除 / 清空），不需要程序替他们决定。

  final List<HistoryItem> _items = [];
  bool _loaded = false;

  List<HistoryItem> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final data = await _store.load(_file);
    final list = (data['items'] as List?) ?? const [];
    _items
      ..clear()
      ..addAll([for (final m in list) HistoryItem.fromMap(m as Map)]);
    notifyListeners();
  }

  /// 给缺失封面的历史回填 picUrl。
  Future<int> backfillCovers() async {
    await ensureLoaded();
    final missing = _items.where((e) => (e.picUrl ?? '').isEmpty).toList();
    if (missing.isEmpty) return 0;
    final pics = await CoverBackfill.resolve([
      for (final e in missing)
        (
          sourceId: e.sourceId,
          musicId: e.musicId,
          title: e.title,
          artist: e.artist
        ),
    ]);
    if (pics.isEmpty) return 0;
    var hit = 0;
    for (var i = 0; i < _items.length; i++) {
      final p = pics['${_items[i].sourceId}/${_items[i].musicId}'];
      if (p == null || p.isEmpty) continue;
      final old = _items[i];
      _items[i] = HistoryItem(
        sourceId: old.sourceId,
        musicId: old.musicId,
        title: old.title,
        artist: old.artist,
        album: old.album,
        picUrl: p,
        durationMs: old.durationMs,
        playedAt: old.playedAt,
      );
      hit++;
    }
    if (hit > 0) {
      await _flush();
      notifyListeners();
    }
    return hit;
  }

  /// 记录一次播放。本地曲目用 sourceId='local'。
  Future<void> record({
    required String sourceId,
    required String musicId,
    required String title,
    required String artist,
    String? album,
    String? picUrl,
    int? durationMs,
  }) async {
    await ensureLoaded();
    if (musicId.isEmpty) return;
    final key = '$sourceId/$musicId';
    _items.removeWhere((e) => e.key == key);
    _items.insert(
      0,
      HistoryItem(
        sourceId: sourceId,
        musicId: musicId,
        title: title,
        artist: artist,
        album: album,
        picUrl: picUrl,
        durationMs: durationMs,
        playedAt: DateTime.now(),
      ),
    );
    await _flush();
    notifyListeners();
  }

  /// 批量并入外部条目（试听列表合并进「最近」）。
  ///
  /// 与 [importJson] 的区别：这里接受内存对象，并按 key 去重。
  /// [playedAt] 为 null 时用「当前时间往前推」的均匀分布，
  /// 保证这批条目排在已有历史之后但彼此有序（越靠前越新）。
  /// 返回实际新增条数。
  Future<int> importItems(List<HistoryItem> items) async {
    await ensureLoaded();
    final byKey = {for (final e in _items) e.key: e};
    var added = 0;
    for (final it in items) {
      if (it.musicId.isEmpty) continue;
      final existing = byKey[it.key];
      if (existing == null) {
        byKey[it.key] = it;
        added++;
      } else if (it.playedAt.isAfter(existing.playedAt)) {
        byKey[it.key] = it;
      }
    }
    if (added == 0) return 0;
    _items
      ..clear()
      ..addAll(byKey.values.toList()
        ..sort((a, b) => b.playedAt.compareTo(a.playedAt)));
    await _flush();
    notifyListeners();
    return added;
  }

  Future<void> remove(String sourceId, String musicId) async {
    await ensureLoaded();
    _items.removeWhere((e) => e.key == '$sourceId/$musicId');
    await _flush();
    notifyListeners();
  }

  Future<void> clear() async {
    await ensureLoaded();
    _items.clear();
    await _flush();
    notifyListeners();
  }

  /// 合并外部历史（WebDAV 恢复）：按 key 去重，同一首保留 playedAt 较新的。
  /// 返回新增条数。
  Future<int> importJson(String raw) async {
    await ensureLoaded();
    final data = jsonDecode(raw) as Map<Object?, Object?>;
    final list = (data['items'] as List?) ?? const [];
    final byKey = {for (final e in _items) e.key: e};
    var added = 0;
    for (final m in list) {
      if (m is! Map) continue;
      final it = HistoryItem.fromMap(m);
      if (it.musicId.isEmpty) continue;
      final existing = byKey[it.key];
      if (existing == null) {
        byKey[it.key] = it;
        added++;
      } else if (it.playedAt.isAfter(existing.playedAt)) {
        byKey[it.key] = it;
      }
    }
    if (added == 0) return 0;
    final merged = byKey.values.toList()
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    _items
      ..clear()
      ..addAll(merged);
    await _flush();
    notifyListeners();
    return added;
  }

  Future<void> _flush() =>
      _store.flush(_file, {'items': [for (final e in _items) e.toJson()]});
}
