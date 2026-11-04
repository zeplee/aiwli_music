import '../storage/settings_store.dart';
import 'safe_notifier.dart';

/// 搜索历史：最近搜过的关键词（去重、最新在前、有上限）。
class SearchHistoryService extends SafeNotifier {
  SearchHistoryService(this._store);
  final SettingsStore _store;
  static const _file = 'search_history.json';
  static const int maxItems = 20;

  final List<String> _items = [];
  bool _loaded = false;

  List<String> get items => List.unmodifiable(_items);

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final data = await _store.load(_file);
    final list = (data['items'] as List?) ?? const [];
    _items
      ..clear()
      ..addAll(list.whereType<String>().where((s) => s.trim().isNotEmpty));
    notifyListeners();
  }

  Future<void> add(String keyword) async {
    await ensureLoaded();
    final q = keyword.trim();
    if (q.isEmpty) return;
    _items.removeWhere((e) => e.toLowerCase() == q.toLowerCase());
    _items.insert(0, q);
    if (_items.length > maxItems) {
      _items.removeRange(maxItems, _items.length);
    }
    await _flush();
    notifyListeners();
  }

  Future<void> remove(String keyword) async {
    await ensureLoaded();
    _items.removeWhere((e) => e == keyword);
    await _flush();
    notifyListeners();
  }

  Future<void> clear() async {
    await ensureLoaded();
    _items.clear();
    await _flush();
    notifyListeners();
  }

  Future<void> _flush() => _store.flush(_file, {'items': _items});
}
