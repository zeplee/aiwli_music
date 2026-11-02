import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

import '../../../app_providers.dart';
import '../../../core/services/webdav_service.dart';

/// WebDAV 同步：服务器配置 + 收藏备份/恢复。
class WebDavPage extends ConsumerStatefulWidget {
  const WebDavPage({super.key});

  @override
  ConsumerState<WebDavPage> createState() => _WebDavPageState();
}

class _WebDavPageState extends ConsumerState<WebDavPage> {
  late final TextEditingController _url;
  late final TextEditingController _user;
  late final TextEditingController _pass;
  late final TextEditingController _dir;
  bool _busy = false;
  String? _message;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    final c = ref.read(webDavServiceProvider).config;
    _url = TextEditingController(text: c.serverUrl);
    _user = TextEditingController(text: c.username);
    _pass = TextEditingController(text: c.password);
    _dir = TextEditingController(text: c.remoteDir);
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    _dir.dispose();
    super.dispose();
  }

  WebDavConfig _configFromFields() => WebDavConfig(
        serverUrl: _url.text.trim(),
        username: _user.text.trim(),
        password: _pass.text,
        remoteDir: _dir.text.trim().isEmpty
            ? '/aiwli_music'
            : _dir.text.trim(),
      );

  Future<void> _run(Future<String> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(webDavServiceProvider).saveConfig(_configFromFields());
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final msg = await action();
      if (!mounted) return;
      setState(() {
        _message = msg;
        _isError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = '失败: $e';
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
      messenger.hideCurrentSnackBar();
    }
  }

  // 保存临时配置供各操作使用（不点保存也会生效，但持久化仍需点保存）
  void _applyFieldsToService() {
    ref.read(webDavServiceProvider).saveConfig(_configFromFields());
  }

  Future<String> _testConnection() async {
    _applyFieldsToService();
    final client = webdav.newClient(
      _url.text.trim(),
      user: _user.text.trim(),
      password: _pass.text,
    );
    try {
      await client.ping();
      // 顺手建好远端目录，避免恢复/上传时 409 Conflict
      await ref.read(webDavServiceProvider).ensureRemoteDir();
      return '连接成功，远端目录 ${ref.read(webDavServiceProvider).normalizedDir} 已就绪';
    } finally {}
  }

  Future<String> _upload() async {
    _applyFieldsToService();
    await ref.read(favoritesProvider).ensureLoaded();
    await ref.read(playlistsProvider).load();
    await ref.read(backupProvider).upload();
    final favorites = ref.read(favoritesProvider);
    final playlists = ref.read(playlistsProvider);
    final sources = ref.read(sourceRegistryProvider);
    return '已上传全量备份：收藏 ${favorites.items.length} 首、'
        '歌单 ${playlists.playlists.length} 个、音源 ${sources.installed.length} 个、设置 ✓';
  }

  Future<String> _restore() async {
    _applyFieldsToService();
    final raw = await ref.read(webDavServiceProvider).downloadBackup();
    return ref.read(backupProvider).restore(raw);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV 同步')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'https://dav.jianguoyun.com/dav/',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              decoration: const InputDecoration(
                  labelText: '账号', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: '密码 / 应用密码',
                  border: OutlineInputBorder(),
                  isDense: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dir,
              decoration: const InputDecoration(
                  labelText: '远程目录（默认 /aiwli_music）', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _run(_testConnection),
              icon: const Icon(Icons.wifi_tethering, size: 18),
              label: const Text('测试连接'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _run(_upload),
              icon: const Icon(Icons.cloud_upload, size: 18),
              label: const Text('上传全量备份'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _run(_restore),
              icon: const Icon(Icons.cloud_download, size: 18),
              label: const Text('恢复备份（合并到本地）'),
            ),
            if (_busy) const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_message!,
                    style: TextStyle(
                        color: _isError ? scheme.error : scheme.primary,
                        fontSize: 13)),
              ),
            const SizedBox(height: 24),
            Text('说明',
                style: TextStyle(
                    color: scheme.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 4),
            Text('备份内容为收藏列表（JSON）。坚果云等服务的应用密码请在对应网站生成。',
                style: TextStyle(
                    color: scheme.onSurfaceVariant, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
