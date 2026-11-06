import 'dart:async';


import '../core/services/logger.dart';
import '../core/storage/settings_store.dart';
import 'lx/lx_source.dart';
import '../core/services/safe_notifier.dart';

/// 已安装 lx 源条目（持久化载体）。
class InstalledSource {
  const InstalledSource({
    required this.id,
    required this.name,
    required this.script,
    required this.enabled,
    this.musicFree = false,
  });
  final String id; // 稳定 id：name 的 slug
  final String name;
  final String script;
  final bool enabled;

  /// true = MusicFree 插件（CommonJS），false = lx 源脚本。
  final bool musicFree;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'script': script,
        'enabled': enabled,
        if (musicFree) 'musicFree': true,
      };

  static InstalledSource fromJson(Map<Object?, Object?> m) => InstalledSource(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? '未命名源',
        script: m['script'] as String? ?? '',
        enabled: m['enabled'] == true,
        musicFree: m['musicFree'] == true,
      );
}

/// 源注册表：导入/启停/删除 + 持久化 + 活跃源运行时。
class SourceRegistry extends SafeNotifier {
  SourceRegistry(this._store) {
    _restore();
  }

  final SettingsStore _store;
  static const _file = 'sources.json';

  final List<InstalledSource> _installed = [];
  final Map<String, LxSource> _runtimes = {};
  String? _activeId;

  List<InstalledSource> get installed => List.unmodifiable(_installed);
  String? get activeId => _activeId;
  bool get hasActiveSource =>
      _installed.any((s) => s.enabled && s.id == _activeId);

  LxSource? runtimeOf(String id) => _runtimes[id];

  LxSource? get activeRuntime {
    for (final s in _installed) {
      if (s.enabled && s.id == _activeId) return _runtimes[s.id];
    }
    return null;
  }

  /// 所有已启用且已构建运行时的源（用于多源并发搜索）。
  /// 是否真能搜索需调用方 await waitInited 后检查 actions。
  List<LxSource> get enabledRuntimes => [
        for (final s in _installed)
          if (s.enabled && _runtimes.containsKey(s.id)) _runtimes[s.id]!,
      ];

  String _slug(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fa5]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  /// 导入脚本文本；重复名称覆盖。
  Future<InstalledSource> importScript(String script) async {
    final meta = LxManifestParser.parse(script);
    final id = _slug(meta.name);
    final existing = _installed.indexWhere((s) => s.id == id);
    final src = InstalledSource(
        id: id,
        name: meta.name + (meta.version.isEmpty ? '' : ' ${meta.version}'),
        script: script,
        enabled: true);
    if (existing >= 0) {
      _installed[existing] = src;
    } else {
      _installed.add(src);
    }
    // 活跃源默认取第一个启用的
    _activeId ??= id;
    await _rebuildRuntime(src);
    await _persist();
    notifyListeners();
    AppLog.i('SourceRegistry', '导入源 ${src.name} ($id)');
    return src;
  }

  /// 导入 MusicFree 插件（CommonJS 模块）。名称取插件 platform 字段。
  Future<InstalledSource> importMusicFreePlugin(String code,
      {String? platformHint}) async {
    final platform = _parseMfPlatform(code) ?? platformHint ?? 'MusicFree 插件';
    final id = 'mf-${_slug(platform)}';
    final src = InstalledSource(
      id: id,
      name: platform,
      script: code,
      enabled: true,
      musicFree: true,
    );
    final existing = _installed.indexWhere((s) => s.id == id);
    if (existing >= 0) {
      _installed[existing] = src;
    } else {
      _installed.add(src);
    }
    _activeId ??= id;
    await _rebuildRuntime(src);
    await _persist();
    notifyListeners();
    AppLog.i('SourceRegistry', '导入 MusicFree 插件 $platform ($id)');
    return src;
  }

  /// 从插件源码中读取 platform（兼容 _0x 混淆时的字符串字面量）。
  static String? _parseMfPlatform(String code) {
    final m = RegExp(r'''platform['"]?\s*[:=]\s*['"]([^'"]{1,40})['"]''')
        .firstMatch(code);
    return m?.group(1);
  }

  Future<void> setActive(String id) async {
    _activeId = id;
    await _persist();
    notifyListeners();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final i = _installed.indexWhere((s) => s.id == id);
    if (i < 0) return;
    _installed[i] = InstalledSource(
        id: _installed[i].id,
        name: _installed[i].name,
        script: _installed[i].script,
        enabled: enabled);
    if (!enabled && _activeId == id) {
      _activeId = null;
      for (final s in _installed) {
        if (s.enabled) _activeId = s.id;
      }
    }
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _installed.removeWhere((s) => s.id == id);
    await _runtimes.remove(id)?.dispose();
    if (_activeId == id) _activeId = null;
    await _persist();
    notifyListeners();
  }

  Future<void> _rebuildRuntime(InstalledSource src) async {
    await _runtimes.remove(src.id)?.dispose();
    if (!src.enabled) return;
    _runtimes[src.id] = LxSource(
        id: src.id, name: src.name, script: src.script, musicFree: src.musicFree);
    // 后台预热 inited，不阻塞 UI
    unawaited(_runtimes[src.id]!.waitInited().then((ok) {
      // 记录声明的平台与 action：排查「为什么取链只试了一个源」时，
      // 这一行是唯一能说明"该脚本是否支持这个平台"的证据。
      final rt = _runtimes[src.id];
      AppLog.i(
          'SourceRegistry',
          '源 ${src.name} inited=$ok '
              'platforms=${rt?.platforms.join(",")} '
              'actions=${rt?.actions.join(",")}');
    }));
  }

  Future<void> _persist() async {
    await _store.flush(_file, {
      'activeId': _activeId,
      'sources': [for (final s in _installed) s.toJson()],
    });
  }

  void _restore() {
    // 同步读在 provider 初始化时不可行，改为异步补载
    _store.load(_file).then((data) {
      final list = (data['sources'] as List?) ?? const [];
      _installed
        ..clear()
        ..addAll([for (final m in list) InstalledSource.fromJson(m as Map)]);
      _activeId = data['activeId'] as String?;
      for (final s in _installed) {
        if (s.enabled) unawaited(_rebuildRuntime(s));
      }
      notifyListeners();
      AppLog.i('SourceRegistry', '恢复 ${_installed.length} 个已安装源');
    });
  }
}