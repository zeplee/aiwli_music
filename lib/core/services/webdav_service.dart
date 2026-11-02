import 'dart:convert';

import 'package:webdav_client/webdav_client.dart' as webdav;

import '../../core/services/logger.dart';
import '../storage/settings_store.dart';
import 'safe_notifier.dart';

/// WebDAV 配置（持久化）。
class WebDavConfig {
  const WebDavConfig({
    required this.serverUrl,
    required this.username,
    required this.password,
    this.remoteDir = '/aiwli_music',
  });
  final String serverUrl;
  final String username;
  final String password;
  final String remoteDir;

  bool get isConfigured => serverUrl.trim().isNotEmpty;

  Map<String, Object?> toJson() => {
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
        'remoteDir': remoteDir,
      };

  static WebDavConfig fromMap(Map<Object?, Object?> m) => WebDavConfig(
        serverUrl: m['serverUrl'] as String? ?? '',
        username: m['username'] as String? ?? '',
        password: m['password'] as String? ?? '',
        remoteDir: m['remoteDir'] as String? ?? '/aiwli_music',
      );
}

/// WebDAV 同步：收藏夹备份（上传）与恢复（下载）。
class WebDavService extends SafeNotifier {
  WebDavService(this._store);
  final SettingsStore _store;
  static const _configFile = 'webdav.json';
  static const _backupName = 'aiwli_backup.json';

  WebDavConfig config = const WebDavConfig(
      serverUrl: '', username: '', password: '', remoteDir: '/aiwli_music');
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final data = await _store.load(_configFile);
    config = WebDavConfig.fromMap(data);
    notifyListeners();
  }

  Future<void> saveConfig(WebDavConfig c) async {
    config = c;
    _loaded = true;
    await _store.flush(_configFile, c.toJson());
    notifyListeners();
  }

  webdav.Client? _client() {
    if (!config.isConfigured) return null;
    return webdav.newClient(
      config.serverUrl,
      user: config.username,
      password: config.password,
      debug: false,
    );
  }

  /// 上传备份：收藏 JSON → WebDAV。
  Future<void> uploadBackup(String json) async {
    final client = _client();
    if (client == null) throw Exception('WebDAV 未配置');
    try {
      await client.mkdirAll(config.remoteDir);
    } catch (_) {}
    await client.write(
      '${config.remoteDir.endsWith('/') ? config.remoteDir : '${config.remoteDir}/'}$_backupName',
      utf8.encode(json),
      onProgress: (c, t) {},
    );
  }

  /// 下载备份：返回 JSON 字符串（不存在则抛错）。
  Future<String> downloadBackup() async {
    final client = _client();
    if (client == null) throw Exception('WebDAV 未配置');
    final path =
        '${config.remoteDir.endsWith('/') ? config.remoteDir : '${config.remoteDir}/'}$_backupName';
    final bytes = await client.read(path, onProgress: (c, t) {});
    return utf8.decode(bytes);
  }

  @override
  void dispose() {
    AppLog.d('WebDav', 'service disposed');
    super.dispose();
  }
}
