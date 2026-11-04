import 'dart:convert';


import '../storage/settings_store.dart';
import 'cover_backfill.dart';
import 'safe_notifier.dart';

/// 收藏的歌曲（持久化 + WebDAV 备份数据源）。
class FavoriteItem {
  const FavoriteItem({
    required this.sourceId,
    required this.musicId,
    required this.title,
    required this.artist,
    this.album,
    this.picUrl,
    this.durationMs,
    this.favoritedAt,
  });

  factory FavoriteItem.fromMap(Map<Object?, Object?> m) => FavoriteItem(
        sourceId: m['sourceId'] as String? ?? '',
        musicId: m['musicId'] as String? ?? '',
        title: m['title'] as String? ?? '',
        artist: m['artist'] as String? ?? '',
        album: m['album'] as String?,
        picUrl: m['picUrl'] as String?,
        durationMs: (m['durationMs'] as num?)?.toInt(),
        favoritedAt: m['favoritedAt'] == null
            ? null
            : DateTime.tryParse(m['favoritedAt'] as String),
      );

  final String sourceId;
  final String musicId;
  final String title;
  final String artist;
  final String? album;

  /// 封面 URL（各平台 CDN 直链）。
  final String? picUrl;
  final int? durationMs;
  final DateTime? favoritedAt;

  Map<String, Object?> toJson() => {
        'sourceId': sourceId,
        'musicId': musicId,
        'title': title,
        'artist': artist,
        'album': album,
        'picUrl': picUrl,
        'durationMs': durationMs,
        'favoritedAt': favoritedAt?.toIso8601String(),
      };

  String get key => '$sourceId/$musicId';
}

/// 收藏夹：ChangeNotifier，SettingsStore JSON 持久化，WebDAV 备份的数据源。
class FavoritesService extends SafeNotifier {
  FavoritesService(this._store);
  final SettingsStore _store;
  static const _file = 'favorites.json';

  final List<FavoriteItem> _items = [];
  bool _loaded = false;

  List<FavoriteItem> get items => List.unmodifiable(_items);
  bool isFavorite(String sourceId, String musicId) =>
      _items.any((i) => i.key == '$sourceId/$musicId');

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final data = await _store.load(_file);
    final list = (data['items'] as List?) ?? const [];
    _items
      ..clear()
      ..addAll([for (final m in list) FavoriteItem.fromMap(m as Map)]);
    notifyListeners();
  }

  /// 给缺失封面的条目回填 picUrl（旧数据一次性补齐）。
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
      _items[i] = FavoriteItem(
        sourceId: old.sourceId,
        musicId: old.musicId,
        title: old.title,
        artist: old.artist,
        album: old.album,
        picUrl: p,
        durationMs: old.durationMs,
        favoritedAt: old.favoritedAt,
      );
      hit++;
    }
    if (hit > 0) {
      await _store.flush(_file, {'items': [for (final e in _items) e.toJson()]});
      notifyListeners();
    }
    return hit;
  }

  Future<void> toggle({
    required String sourceId,
    required String musicId,
    required String title,
    required String artist,
    String? album,
    String? picUrl,
    int? durationMs,
  }) async {
    await ensureLoaded();
    final key = '$sourceId/$musicId';
    final i = _items.indexWhere((e) => e.key == key);
    if (i >= 0) {
      _items.removeAt(i);
    } else {
      _items.insert(0, FavoriteItem(
        sourceId: sourceId,
        musicId: musicId,
        title: title,
        artist: artist,
        album: album,
        picUrl: picUrl,
        durationMs: durationMs,
        favoritedAt: DateTime.now(),
      ));
    }
    await _store.flush(_file, {'items': [for (final e in _items) e.toJson()]});
    notifyListeners();
  }

  /// WebDAV 恢复：整表替换。
  Future<void> restore(List<FavoriteItem> items) async {
    _items
      ..clear()
      ..addAll(items);
    await _store.flush(_file, {'items': [for (final e in _items) e.toJson()]});
    notifyListeners();
  }

  String exportJson() {
    _loaded = true;
    return jsonEncode({'items': [for (final e in _items) e.toJson()]});
  }

  Future<int> importJson(String raw) async {
    final data = jsonDecode(raw) as Map<Object?, Object?>;
    final list = (data['items'] as List?) ?? const [];
    final incoming = [
      for (final m in list) FavoriteItem.fromMap(m as Map<Object?, Object?>)
    ];
    var added = 0;
    for (final item in incoming) {
      if (!_items.any((e) => e.key == item.key)) {
        _items.add(item);
        added++;
      }
    }
    await _store.flush(_file, {'items': [for (final e in _items) e.toJson()]});
    notifyListeners();
    return added;
  }
}
