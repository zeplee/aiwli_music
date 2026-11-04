import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/lyric/lrc_parser.dart';
import 'core/models/lyric.dart';
import 'core/models/music.dart';
import 'core/services/app_settings.dart';
import 'core/services/backup_service.dart';
import 'core/services/logger.dart';
import 'core/services/play_history_service.dart';
import 'core/services/playlists.dart';
import 'core/services/search_history_service.dart';
import 'core/services/safe_notifier.dart';
import 'core/services/sleep_timer.dart';
import 'core/services/webdav_service.dart';
import 'package:flutter_media_store/flutter_media_store.dart';
import 'core/storage/settings_store.dart';
import 'player/playback_resolver.dart';
import 'player/player_core.dart';
import 'platform/platform_cast.dart';
import 'player/providers.dart';
import 'sources/builtin/lyric_sdk.dart';
import 'sources/builtin/comment_sdk.dart';
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

/// URL 解析：local 直用；其余按「曲目所属源」取链，失败自动换源。
///
/// [excludeSources]：播放器已试过但打不开的源（死链/域名失效），
/// resolver 会排除它们并强制换源（配合死源黑名单 30 分钟）。
Future<ResolvedPlayback> resolveUrl(
    Ref ref, PlayerItem item, Set<String> excludeSources) async {
  if (item.sourceId == 'local' || item.sourceId == 'url') {
    final url = item.resolvedUrl;
    if (url == null || url.isEmpty) throw Exception('本地条目缺地址');
    return ResolvedPlayback(
      url: url,
      sourceId: item.sourceId,
      winnerId: item.sourceId,
      sourceLabel: '本地',
      musicId: item.musicId,
      title: item.title,
      artist: item.artist,
    );
  }
  return ref.read(playbackResolverProvider).resolve(
    title: item.title,
    artist: item.artist,
    sourceId: item.sourceId,
    musicId: item.musicId,
    quality: ref.read(appSettingsProvider).quality,
    raw: item.raw,
    excludeIds: excludeSources,
  );
}

/// 全局唯一的取链器：URL 缓存 + 「平台→成功源」记忆都在它身上，
/// 必须是单例，否则每次访问都要重新建，缓存形同虚设。
PlaybackResolver? _resolverSingleton;

final playbackResolverProvider = Provider<PlaybackResolver>((ref) {
  // 注意：不能 watch(sourceRegistryProvider)——registry 每次 notifyListeners
  // 都会把本 provider 重建，URL 缓存与成功源记忆随之清零（现场日志证实：
  // 同一首歌 27 秒后缓存未命中）。registry 实例本身不重建，直接持有。
  return _resolverSingleton ??=
      PlaybackResolver(ref.read(sourceRegistryProvider));
});

/// 进程级 PlayerCore 单例。
///
/// 之前用 `ref.watch(...)` 建立依赖：任何上游 provider 重建都会导致本
/// provider 被 dispose 并新建 core，而 UI / 播放页仍持有旧 core，
/// 旧 core 的引擎又已被回收 → `Assertion failed: "[Player] has been disposed"`。
/// 改为 `ref.read` + 单一实例，生命周期跟随进程。
PlayerCore? _coreSingleton;

final playerCoreProvider = Provider<PlayerCore>((ref) {
  final existing = _coreSingleton;
  if (existing != null) return existing;

  final resolver = ref.read(playbackResolverProvider);
  final core = PlayerCore(
    engine: ref.read(engineProvider),
    // 系统媒体广播（锁屏/通知栏/耳机线控）。原生实现全在插件内，
    // 各平台分支只在这里选一次（ADR-014）。
    cast: createCast(),
    focus: ref.read(focusPolicyProvider),
    urlResolver: (item, exclude) => resolveUrl(ref, item, exclude),
    onSourceUnplayable: (resolved, error) {
      resolver.reportUnplayable(resolved.winnerId, error: error);
      // 该源名下缓存可能都是死链，一并作废
      resolver.invalidateCacheAll(resolved.winnerId);
    },
    // 真正开始播放时写一条播放历史（解析失败/死链不会进历史）
    onTrackStarted: (item) {
      ref.read(playHistoryProvider).record(
            sourceId: item.sourceId,
            musicId: item.musicId,
            title: item.title,
            artist: item.artist,
            album: item.album,
            picUrl: item.artUri?.toString(),
            durationMs: item.duration?.inMilliseconds,
          );
    },
    // 预取下一首：播放当前曲目时后台解析下一首，切歌时直接命中缓存
    prefetcher: (item) async {
      if (item.sourceId == 'local' || item.sourceId == 'url') return;
      try {
        await resolver.resolve(
          title: item.title,
          artist: item.artist,
          sourceId: item.sourceId,
          musicId: item.musicId,
          quality: ref.read(appSettingsProvider).quality,
          raw: item.raw,
        );
      } catch (_) {
        // 预取失败无所谓，真正播放时会重试
      }
    },
  );
  _coreSingleton = core;
  return core;
});

// ============ 应用设置（音质 + 均衡器）============

final appSettingsProvider = ChangeNotifierProvider<AppSettings>((ref) {
  final s = AppSettings(ref.watch(settingsStoreProvider));
  s.load();
  ref.onDispose(s.dispose);
  return s;
});

// ============ 定时关闭 ============

final sleepTimerProvider = ChangeNotifierProvider<SleepTimerService>((ref) {
  final core = ref.read(playerCoreProvider);
  final s = SleepTimerService(
    onExpire: () => core.pause(),
    onEndOfTrackChanged: core.setEndOfTrackPause,
  );
  ref.onDispose(s.dispose);
  return s;
});

// ============ 歌单 ============

final playlistsProvider = ChangeNotifierProvider<PlaylistService>((ref) {
  final store = ref.watch(settingsStoreProvider);
  final s = PlaylistService(store);
  // load 完成后再迁移旧 favorites.json（幂等：已迁移则无条目可并）
  s.load().then((_) => migrateLegacyFavorites(s, store));
  ref.onDispose(s.dispose);
  return s;
});

final backupProvider = Provider<BackupService>((ref) => BackupService(ref));

// ============ 歌词 ============

class LyricState {
  const LyricState({
    this.doc,
    this.loading = false,
    this.error,
    this.translation,
    this.roman,
  });
  final LyricDocument? doc;
  final bool loading;
  final String? error;

  /// 翻译歌词（网易 tlyric）。
  final LyricDocument? translation;

  /// 罗马音歌词（网易 romalrc）。
  final LyricDocument? roman;

  bool get hasTranslation => translation != null;
  bool get hasRoman => roman != null;
}

class LyricService extends SafeNotifier {
  LyricService(this._ref);
  final Ref _ref;
  final _parser = const LrcParser();
  final Map<String, LyricDocument> _cache = {};

  LyricState current = const LyricState();
  String? _currentKey;

  Future<void> fetchFor(String sourceId, String musicId,
      {String title = '', String artist = ''}) async {
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
      String? translation;
      String? roman;
      // ① 脚本声明 lyric 能力 → 脚本优先
      if (sourceId != 'local') {
        final lx = _ref.read(sourceRegistryProvider).activeRuntime;
        if (lx != null) {
          try {
            lrc = await lx.getLyricFromScript(MusicInfo(
                sourceId: sourceId, musicId: musicId, title: '', artist: ''));
          } catch (_) {}
        }
      }
      // ② 脚本没有/为空 → 内置多平台歌词（含翻译、罗马音）
      if (lrc == null || lrc.trim().isEmpty) {
        final r = await LyricSdk.fetch(
            sourceId: sourceId,
            musicId: musicId,
            title: title,
            artist: artist);
        if (r != null) {
          lrc = r.lyric;
          translation = r.translation;
          roman = r.roman;
        }
      }
      if (_currentKey != key) return;
      if (lrc == null || lrc.trim().isEmpty) {
        current = const LyricState(error: '暂无歌词');
      } else {
        final doc = _parser.parse(lrc);
        _cache[key] = doc;
        current = LyricState(
          doc: doc,
          translation: (translation == null || translation.isEmpty)
              ? null
              : _parser.parse(translation),
          roman: (roman == null || roman.isEmpty)
              ? null
              : _parser.parse(roman),
        );
      }
      AppLog.i('LyricService', '$key -> ${lrc?.length ?? 0} chars');
    } catch (_) {
      if (_currentKey == key) current = const LyricState(error: '歌词获取失败');
    }
    notifyListeners();
  }
}

final lyricServiceProvider =
    ChangeNotifierProvider<LyricService>((ref) => LyricService(ref));

// ============ 评论 ============

class CommentState {
  const CommentState({this.items = const [], this.loading = false, this.error});
  final List<CommentItem> items;
  final bool loading;
  final String? error;
}

class CommentService extends SafeNotifier {
  CommentService(Ref ref);
  final Map<String, List<CommentItem>> _cache = {};
  CommentState current = const CommentState();
  String? _key;

  Future<void> fetchFor(String sourceId, String musicId,
      {String title = '', String artist = ''}) async {
    final key = '$sourceId/$musicId';
    if (key == _key && current.items.isNotEmpty) return;
    _key = key;
    final cached = _cache[key];
    if (cached != null) {
      current = CommentState(items: cached);
      notifyListeners();
      return;
    }
    current = const CommentState(loading: true);
    notifyListeners();
    try {
      final list = await CommentSdk.fetch(
          sourceId: sourceId, musicId: musicId, title: title, artist: artist);
      if (_key != key) return;
      _cache[key] = list;
      current = CommentState(
          items: list, error: list.isEmpty ? '当前音源暂无可获取的评论' : null);
    } catch (e) {
      if (_key == key) current = CommentState(error: '评论获取失败: $e');
    }
    notifyListeners();
  }
}

final commentServiceProvider =
    ChangeNotifierProvider<CommentService>((ref) => CommentService(ref));

// ============ 下载（dio 流式 → MediaStore 落库）============

class DownloadTask {
  DownloadTask({required this.title, required this.artist});
  final String title;
  final String artist;
  int received = 0;
  int total = 0;
  String status = '排队中';

  /// 落库成功后回填：媒体库 uri（content://）与磁盘路径。
  /// 有 uri 就能直接当本地曲目播放，不必再去系统音乐 App 里找。
  String? savedUri;
  String? savedPath;
  bool get playable => savedUri != null && savedUri!.isNotEmpty;
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
      final resolved = await resolveUrl(_ref, item, const {});
      final url = resolved.url;
      task.status = '下载中';
      notifyListeners();

      final dio = _ref.read(dioProvider);
      final resp = await dio.get<ResponseBody>(url,
          options: Options(responseType: ResponseType.stream));
      final body = resp.data!;
      // 服务端给了 Content-Length 才有「总大小」，否则只能显示已下载字节
      final total = int.tryParse(
              resp.headers.value(Headers.contentLengthHeader) ?? '') ??
          0;
      if (total > 0) {
        task.total = total;
      }
      final bytesBuilder = BytesBuilder(copy: false);
      var lastNotify = 0;
      await for (final chunk in body.stream) {
        bytesBuilder.add(chunk);
        task.received = bytesBuilder.length;
        // 限频：约 150ms 一次，避免每 8KB 就重建整棵树
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastNotify > 150) {
          lastNotify = now;
          notifyListeners();
        }
      }
      final bytes = bytesBuilder.takeBytes();

      await _ref.read(flutterMediaStoreProvider).saveFile(
            fileData: bytes,
            mimeType: 'audio/mpeg',
            rootFolderName: 'Music',
            folderName: 'AiwliMusic',
            fileName:
                '${item.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.mp3',
            onSuccess: (uri, path) {
              task.savedUri = uri;
              task.savedPath = path;
              AppLog.i('Download', '落库成功 ${item.title} uri=$uri path=$path');
              notifyListeners();
            },
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

final playHistoryProvider = ChangeNotifierProvider<PlayHistoryService>((ref) {
  final svc = PlayHistoryService(ref.watch(settingsStoreProvider));
  svc.ensureLoaded().then((_) => svc.backfillCovers());
  ref.onDispose(svc.dispose);
  return svc;
});

final searchHistoryProvider =
    ChangeNotifierProvider<SearchHistoryService>((ref) {
  final svc = SearchHistoryService(ref.watch(settingsStoreProvider));
  svc.ensureLoaded();
  ref.onDispose(svc.dispose);
  return svc;
});

/// 一次性迁移：把旧版独立的 favorites.json 并入「我的收藏」系统歌单。
///
/// 背景：收藏与歌单曾是两套并行模型（两套存储、两套 UI、备份要写两份）。
/// 参考工程（lx / 栖弦）都只有歌单，没有独立收藏。故合并为
/// 「我的收藏」= 一个不可删除、置顶的系统歌单，爱心按钮 = 往它里面加/删。
///
/// 迁移完把 favorites.json 改名备份，避免重复迁移。
Future<void> migrateLegacyFavorites(PlaylistService playlists,
    SettingsStore store) async {
  final data = await store.load('favorites.json');
  final list = (data['items'] as List?) ?? const [];
  if (list.isEmpty) return;

  final entries = <PlaylistEntry>[];
  for (final m in list) {
    if (m is! Map) continue;
    final musicId = m['musicId']?.toString() ?? '';
    if (musicId.isEmpty) continue;
    entries.add(PlaylistEntry(
      sourceId: m['sourceId']?.toString() ?? '',
      musicId: musicId,
      title: m['title']?.toString() ?? '',
      artist: m['artist']?.toString() ?? '',
      album: m['album'] as String?,
      picUrl: m['picUrl'] as String?,
      durationMs: (m['durationMs'] as num?)?.toInt(),
    ));
  }

  if (entries.isNotEmpty) {
    final added = await playlists.mergeIntoFavorites(entries);
    AppLog.i('Migrate', '收藏并入歌单：$added/${entries.length} 首');
  }

  // 用户可能早就自建过一个叫「我的收藏」的歌单（lx 导入常见）。
  // 现在系统歌单接管这个名字，两者内容往往完全重复。
  // 处理：把它的条目并入系统歌单（去重），再把重名的普通歌单改名为
  // 「我的收藏（旧）」保留数据，避免用户以为歌单丢了。
  final dup = playlists.playlists.where(
      (p) => !p.system && p.name == '我的收藏');
  for (final old in dup.toList()) {
    final merged = await playlists.mergeIntoFavorites(old.entries);
    playlists.rename(old.id, '我的收藏（旧）');
    AppLog.i('Migrate',
        '重名歌单「我的收藏」(${old.entries.length} 首) 并入系统歌单 $merged 首，原名改为「我的收藏（旧）」');
  }
  // 标记已迁移（保留原文件内容便于回滚，但不再读取）
  await store.flush('favorites.json.migrated', {'at': DateTime.now().toIso8601String()});
}

final webDavServiceProvider = ChangeNotifierProvider<WebDavService>((ref) {
  final svc = WebDavService(ref.watch(settingsStoreProvider));
  svc.ensureLoaded();
  ref.onDispose(svc.dispose);
  return svc;
});
