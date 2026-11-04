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
/// - 上限 [maxItems] 条，超出丢弃最旧的
/// - SettingsStore JSON 持久化（与收藏/歌单同一套约定，无需 SQLite）
class PlayHistoryService extends SafeNotifier {
  PlayHistoryService(this._store);
  final SettingsStore _store;
  static const _file = 'play_history.json';
  static const int maxItems = 200;

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
    if (_items.length > maxItems) {
      _items.removeRange(maxItems, _items.length);
    }
    await _flush();
    notifyListeners();
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

  Future<void> _flush() =>
      _store.flush(_file, {'items': [for (final e in _items) e.toJson()]});
}
