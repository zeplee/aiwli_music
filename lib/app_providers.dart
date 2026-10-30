import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/lyric/lrc_parser.dart';
import 'core/models/lyric.dart';
import 'core/models/music.dart';
import 'core/models/quality.dart';
import 'core/services/favorites_service.dart';
import 'core/services/logger.dart';
import 'core/services/safe_notifier.dart';
import 'core/services/webdav_service.dart';
import 'package:flutter_media_store/flutter_media_store.dart';
import 'core/storage/settings_store.dart';
import 'player/player_core.dart';
import 'player/providers.dart';
import 'sources/registry.dart';

// ============ 组合根（唯一允许跨域 import 的装配层）============

final settingsStoreProvider =
    Provider<SettingsStore>((ref) => const SettingsStore());

final dioProvider = Provider<Dio>((ref) => Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.plain,
    )));

final flutterMediaStoreProvider =
    Provider<FlutterMediaStore>((ref) => FlutterMediaStore());


final sourceRegistryProvider = ChangeNotifierProvider<SourceRegistry>(
    (ref) => SourceRegistry(ref.watch(settingsStoreProvider)));

/// URL 解析：local 直用；其余走活跃 lx 脚本取链（壳内零内置源）。
Future<String> resolveUrl(Ref ref, PlayerItem item) async {
  if (item.sourceId == 'local') {
    final url = item.resolvedUrl;
    if (url == null || url.isEmpty) throw Exception('本地条目缺地址');
    return url;
  }
  final registry = ref.read(sourceRegistryProvider);
  final lx = registry.activeRuntime;
  if (lx == null) throw Exception('未启用音源，无法取链接');
  return lx.getMusicUrl(
    MusicInfo(
      sourceId: item.sourceId,
      musicId: item.musicId,
      title: item.title,
      artist: item.artist,
    ),
    Quality.high,
  );
}

final playerCoreProvider = Provider<PlayerCore>((ref) {
  final core = PlayerCore(
    engine: ref.watch(engineProvider),
    focus: ref.watch(focusPolicyProvider),
    urlResolver: (item) => resolveUrl(ref, item),
  );
  ref.onDispose(core.dispose);
  return core;
});

// ============ 歌词 ============

class LyricState {
  const LyricState({this.doc, this.loading = false, this.error});
  final LyricDocument? doc;
  final bool loading;
  final String? error;
}

class LyricService extends SafeNotifier {
  LyricService(this._ref);
  final Ref _ref;
  final _parser = const LrcParser();
  final Map<String, LyricDocument> _cache = {};

  LyricState current = const LyricState();
  String? _currentKey;

  Future<void> fetchFor(String sourceId, String musicId) async {
    final key = '$sourceId/$musicId';
    _currentKey = key;
    final cached = _cache[key];
    if (cached != null) {
      current = LyricState(doc: cached);
      notifyListeners();
      return;
    }
    current = const LyricState(loading: true);
    notifyListeners();
    try {
      String? lrc;
      final registry = _ref.read(sourceRegistryProvider);
      final lx = registry.activeRuntime;
      if (sourceId != 'local' && lx != null) {
        lrc = await lx.getLyricFromScript(MusicInfo(
            sourceId: sourceId, musicId: musicId, title: '', artist: ''));
      }
      if (_currentKey != key) return;
      if (lrc == null || lrc.isEmpty) {
        current = const LyricState(error: '暂无歌词');
      } else {
        final doc = _parser.parse(lrc);
        _cache[key] = doc;
        current = LyricState(doc: doc);
      }
    } catch (_) {
      if (_currentKey == key) current = const LyricState(error: '歌词获取失败');
    }
    notifyListeners();
  }
}

final lyricServiceProvider =
    ChangeNotifierProvider<LyricService>((ref) => LyricService(ref));

// ============ 下载（dio 流式 → MediaStore 落库）============

class DownloadTask {
  DownloadTask({required this.title, required this.artist});
  final String title;
  final String artist;
  int received = 0;
  int total = 0;
  String status = '排队中';
}

class DownloadManager extends SafeNotifier {
  DownloadManager(this._ref);
  final Ref _ref;
  final List<DownloadTask> tasks = [];
  final Set<String> _activeKeys = {};

  Future<void> start(PlayerItem item) async {
    final key = '${item.sourceId}/${item.musicId}';
    if (_activeKeys.contains(key)) return;
    _activeKeys.add(key);
    final task = DownloadTask(title: item.title, artist: item.artist)
      ..status = '取链接…';
    tasks.insert(0, task);
    notifyListeners();

    try {
      final url = await resolveUrl(_ref, item);
      task.status = '下载中';
      notifyListeners();

      final dio = _ref.read(dioProvider);
      final resp = await dio.get<ResponseBody>(url,
          options: Options(responseType: ResponseType.stream));
      final body = resp.data!;
      final bytesBuilder = BytesBuilder(copy: false);
      await for (final chunk in body.stream) {
        bytesBuilder.add(chunk);
        task
          ..received = bytesBuilder.length
          ..total = bytesBuilder.length;
        notifyListeners();
      }
      final bytes = bytesBuilder.takeBytes();

      await _ref.read(flutterMediaStoreProvider).saveFile(
            fileData: bytes,
            mimeType: 'audio/mpeg',
            rootFolderName: 'Music',
            folderName: 'AiwliMusic',
            fileName:
                '${item.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.mp3',
            onSuccess: (uri, path) => AppLog.i(
                'Download', '落库成功 ${item.title} uri=$uri'),
            onError: (msg) => AppLog.e('Download', '落库失败 ${item.title}', msg),
          );
      task
        ..status = '完成 ✓'
        ..total = bytes.length
        ..received = bytes.length;
    } catch (e) {
      task.status = '失败: ${e.toString().substring(0, 60)}';
      AppLog.e('Download', '失败 ${item.title}', e);
    }
    _activeKeys.remove(key);
    notifyListeners();
  }
}

final downloadManagerProvider =
    ChangeNotifierProvider<DownloadManager>((ref) => DownloadManager(ref));

// ============ 收藏 / WebDAV ============

final favoritesProvider = ChangeNotifierProvider<FavoritesService>((ref) {
  final svc = FavoritesService(ref.watch(settingsStoreProvider));
  svc.ensureLoaded();
  ref.onDispose(svc.dispose);
  return svc;
});

final webDavServiceProvider = ChangeNotifierProvider<WebDavService>((ref) {
  final svc = WebDavService(ref.watch(settingsStoreProvider));
  svc.ensureLoaded();
  ref.onDispose(svc.dispose);
  return svc;
});
