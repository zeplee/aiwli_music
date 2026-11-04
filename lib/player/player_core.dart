import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'audio_engine.dart';
import 'audio_focus_policy.dart';
import 'media_session_cast.dart';
import 'playback_resolver.dart' show ResolvedPlayback;
import 'models.dart';

/// 可播放条目：队列元素。resolvedUrl 为空表示尚未解析（M2 音源解析后填充）。
class PlayerItem {
  const PlayerItem({
    required this.title,
    required this.artist,
    required this.sourceId,
    required this.musicId,
    this.resolvedUrl,
    this.album,
    this.artUri,
    this.duration,
    this.raw,
    this.artBytes,
  });
  final String title;
  final String artist;
  final String sourceId;
  final String musicId;
  final String? resolvedUrl;
  final String? album;
  final Uri? artUri;
  final Duration? duration;

  /// 音源返回的原始对象（MusicFree 插件取链依赖私有字段，需原样透传）。
  final Map<Object?, Object?>? raw;

  /// 本地封面字节（on_audio_query 的 queryArtwork 返回内存图，非 URL）。
  /// 优先级高于 [artUri]：本地歌曲没有网络封面。
  final Uint8List? artBytes;

  TrackMetadata get metadata => TrackMetadata(
        title: title,
        artist: artist,
        duration: duration,
        artUri: artUri,
      );
}

/// 纯逻辑状态机（设计文档 §3.1）：不 import 任何插件，只依赖 AudioEngine 抽象。
/// 三个机制：_loadGeneration 防旧加载覆盖新切歌；切歌失败回滚；播放完成自动下一首。
class PlayerCore {
  PlayerCore({
    required AudioEngine engine,
    AudioFocusPolicy? focus,
    Future<ResolvedPlayback> Function(PlayerItem item, Set<String> excludeSources)?
        urlResolver,
    void Function(ResolvedPlayback resolved, Object error)? onSourceUnplayable,
    Future<void> Function(PlayerItem item)? prefetcher,
    void Function(PlayerItem item)? onTrackStarted,
    MediaSessionCast? cast,
  }) : _engine = engine,
        // ignore: prefer_initializing_formals
        _onTrackStarted = onTrackStarted,
        // ignore: prefer_initializing_formals
        _cast = cast,
        // ignore: prefer_initializing_formals
        _focus = focus,
        // ignore: prefer_initializing_formals
        _urlResolver = urlResolver,
        // ignore: prefer_initializing_formals
        _onSourceUnplayable = onSourceUnplayable,
        // ignore: prefer_initializing_formals
        _prefetcher = prefetcher {
    _engineSub = engine.snapshots.listen(_onEngineSnapshot);
    _focusSub = _focus?.events.listen(_onFocusEvent);
    _bindCast();
  }

  final AudioEngine _engine;
  final MediaSessionCast? _cast;
  StreamSubscription<CastCommand>? _castSub;
  final AudioFocusPolicy? _focus;
  final Future<ResolvedPlayback> Function(PlayerItem item, Set<String> excludeSources)?
      _urlResolver;
  final void Function(ResolvedPlayback resolved, Object error)? _onSourceUnplayable;

  /// 真正开始播放时回调（写播放历史用）。只在引擎播放成功后触发，
  /// 解析失败/死链不会污染历史。
  final void Function(PlayerItem item)? _onTrackStarted;

  /// 当前加载上下文：引擎的 open 失败是【异步】经 error 流上报的
  /// （mpv "Failed to open <死链>"），同步重试环收不到——
  /// 由 _onEngineSnapshot 驱动换源回退。
  ResolvedPlayback? _activeResolved;
  Set<String> _activeExcludes = const {};
  int _fallbackCount = 0;
  bool _fallbackInFlight = false;
  final Future<void> Function(PlayerItem item)? _prefetcher;
  StreamSubscription<FocusEvent>? _focusSub;
  bool _wasPlayingBeforeInterruption = false;

  // 中断恢复策略（ADR-003/009）：中断→暂停并记忆；恢复→按记忆续播；拔耳机→暂停
  void _onFocusEvent(FocusEvent e) {
    switch (e.type) {
      case FocusEventType.interruptionBegin:
        _wasPlayingBeforeInterruption = state.value.playing;
        state.value = state.value.copyWith(playing: false);
        unawaited(_engine.pause());
        break;
      case FocusEventType.interruptionEnd:
        if (_wasPlayingBeforeInterruption) {
          state.value = state.value.copyWith(playing: true);
          unawaited(_engine.play());
        }
        break;
      case FocusEventType.becomingNoisy:
        state.value = state.value.copyWith(playing: false);
        unawaited(_engine.pause());
        break;
      case FocusEventType.duckBegin:
        unawaited(_engine.setVolume(0.2));
        break;
      case FocusEventType.duckEnd:
        unawaited(_engine.setVolume(1.0));
        break;
    }
  }
  StreamSubscription<EngineSnapshot>? _engineSub;

  final ValueNotifier<PlayerUiState> state =
      ValueNotifier(const PlayerUiState());

  final List<PlayerItem> _queue = [];
  int _index = -1;
  RepeatMode _repeat = RepeatMode.off;
  bool _shuffle = false;
  int _loadGeneration = 0;
  bool _expectCompletion = false;

  PlayerItem? get current =>
      (_index >= 0 && _index < _queue.length) ? _queue[_index] : null;
  int get queueLength => _queue.length;
  int get currentIndex => _index;

  /// 只读队列快照（队列面板展示用）。
  List<PlayerItem> get queue => List.unmodifiable(_queue);

  /// 播放倍速（<1 慢放，>1 快放）。只影响音频，不影响歌词时间轴。
  double get speed => state.value.speed;
  Future<void> setSpeed(double v) async {
    final clamped = v.clamp(0.5, 2.0);
    state.value = state.value.copyWith(speed: clamped);
    await _engine.setSpeed(clamped);
    if (current != null) _pushToCast();
  }

  /// 从队列移除一条。若移除的是当前曲：正在播放则顺延到下一首，否则只更新索引。
  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final wasCurrent = index == _index;
    _queue.removeAt(index);
    if (_queue.isEmpty) {
      _index = -1;
      state.value = state.value.copyWith(playing: false, title: '', artist: '');
      return;
    }
    if (index < _index) {
      _index--;
    } else if (wasCurrent) {
      final next = _index.clamp(0, _queue.length - 1);
      await _loadAt(next);
      return;
    }
    _pushToCast();
  }


  /// 把系统媒体广播（锁屏/通知栏/耳机线控）接到播放核心：
  /// ① 播放状态变化 → 推送给系统（歌名、封面、进度）
  /// ② 系统控件操作 → 转成 core 的播放/暂停/切歌/拖动
  void _bindCast() {
    final cast = _cast;
    if (cast == null) return;
    cast.init();
    _castSub = cast.commands.listen((cmd) {
      switch (cmd.type) {
        case CastCommandType.play:
          play();
        case CastCommandType.pause:
          pause();
        case CastCommandType.next:
          next();
        case CastCommandType.previous:
          previous();
        case CastCommandType.seek:
          if (cmd.position != null) seek(cmd.position!);
        case CastCommandType.setRepeat:
        case CastCommandType.setShuffle:
          break; // 由各平台控件自行处理，App 端不反向同步
      }
    });
    state.addListener(_pushToCast);
    _pushToCast();
  }

  /// 状态 → 系统媒体中心。只在"曲目变了"或播控变了时推，
  /// 避免每 200ms 的进度 tick 反复打扰系统（进度由系统侧按 speed 外推）。
  String? _lastCastKey;
  void _pushToCast() {
    final cast = _cast;
    if (cast == null) return;
    final s = state.value;
    final item = current;
    final key = '${item?.sourceId}/${item?.musicId}|${s.playing}|${s.title}|${s.duration}';
    if (key == _lastCastKey) return;
    _lastCastKey = key;
    if (item != null) cast.updateNowPlaying(item.metadata);
    cast.updatePlayback(
      playing: s.playing,
      position: s.position,
      duration: s.duration,
    );
  }

  void _onEngineSnapshot(EngineSnapshot snap) {
    // 陈旧事件守卫：快速切歌时，旧歌的 mpv 异步错误/完成事件会在
    // 新歌 load 之后到达。音频已属于新歌，把这些事件直接丢弃，
    // 否则页面显示（错误文案/进度条/自动下一首）被旧歌污染——
    // 即"播放的音频和显示的页面不是同一首"。
    final cur = _engine.currentSource;
    if (cur != null &&
        _activeResolved != null &&
        cur != Uri.parse(_activeResolved!.url)) {
      return;
    }
    // 引擎异步错误（mpv "Failed to open <死链>"）→ 换源回退。
    // load() 本身不抛这类错，只能在 error 流里接。
    if (snap.processing == EngineProcessing.error &&
        snap.error != null &&
        _activeResolved != null &&
        !_fallbackInFlight) {
      final resolved = _activeResolved!;
      if (resolved.sourceId != 'local' && resolved.sourceId != 'url') {
        unawaited(_fallbackOnEngineError(snap));
        state.value = state.value.copyWith(
          processing: EngineProcessing.loading,
          error: null,
        );
        return;
      }
    }
    state.value = state.value.copyWith(
      processing: snap.processing,
      playing: snap.playing,
      position: snap.position,
      duration: snap.duration,
      buffered: snap.buffered,
      // 引擎快照没有错误 = 当前健康；必须清掉旧错误，
      // 否则「播放正常但底部一直红字」。
      error: snap.error,
      clearError: snap.error == null,
    );
    if (snap.processing == EngineProcessing.completed && _expectCompletion) {
      _expectCompletion = false;
      if (_endOfTrackPause) {
        // 定时关闭（播完当前首）：暂停而非自动下一首
        state.value = state.value.copyWith(playing: false);
        return;
      }
      unawaited(next(auto: true));
    }
  }

  Future<void> setQueue(List<PlayerItem> items, {int index = 0}) async {
    _queue
      ..clear()
      ..addAll(items);
    if (items.isEmpty) return;
    await _loadAt(index.clamp(0, items.length - 1));
  }

  Future<void> playAt(int index) => _loadAt(index);

  Future<void> _loadAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _index = index;
    final item = _queue[index];
    final gen = ++_loadGeneration;
    state.value = state.value.copyWith(
      processing: EngineProcessing.loading,
      playing: false,
      title: item.title,
      artist: item.artist,
      duration: item.duration,
      position: Duration.zero,
      error: null,
    );
    try {
      ResolvedPlayback? resolved;
      var url = item.resolvedUrl;
      final failedWinners = <String>{}; // 已验证打不开的脚本实例 id
      const maxRounds = 3;
      _fallbackCount = 0;
      _fallbackInFlight = false;

      for (var round = 0; round < maxRounds; round++) {
        if (url == null || url.isEmpty) {
          final resolver = _urlResolver;
          if (resolver == null) throw Exception('无可用播放地址');
          // round > 0：排除已打不开的源，强制走换源
          resolved = await resolver(item, failedWinners);
          url = resolved.url;
          _activeResolved = resolved;
          _activeExcludes = {...failedWinners};
        }
        if (gen != _loadGeneration) return;
        try {
          await _engine.load(Uri.parse(url));
          break; // 打开成功，跳出重试环
        } catch (loadErr) {
          // URL 拿到了但打不开（死链/域名失效/5xx）：
          // ① 拉黑胜出源 30 分钟 ② 作废该曲缓存（否则重试永远命中同一条死链）
          // ③ 排除后重新 resolve
          if (resolved != null) _onSourceUnplayable?.call(resolved, loadErr);
          failedWinners.add(resolved?.winnerId ?? item.sourceId);
          if (round == maxRounds - 1) rethrow;
          state.value = state.value
              .copyWith(processing: EngineProcessing.loading, error: null);
          url = null; // 强制下轮重新 resolve（带排除集）
        }
      }
      if (gen != _loadGeneration) return; // 已被更新的一次切歌覆盖
      await _engine.play();
      _expectCompletion = true;
      _onTrackStarted?.call(item);
      _prefetchNext();
    } catch (e) {
      if (gen != _loadGeneration) return;
      state.value = state.value.copyWith(
        processing: EngineProcessing.error,
        error: '加载失败: $e',
        playing: false,
      );
    }
  }

  /// 引擎异步错误（mpv "Failed to open <死链>"）→ 换源回退。
  /// load() 本身不抛这类错，只能在 error 流里接。
  Future<void> _fallbackOnEngineError(EngineSnapshot snap) async {
    if (_fallbackInFlight) return;
    final resolved = _activeResolved;
    if (resolved == null) return;
    if (resolved.sourceId == 'local' || resolved.sourceId == 'url') return;
    if (_fallbackCount >= 2) {
      state.value = state.value.copyWith(
        processing: EngineProcessing.error,
        error: '加载失败: ${snap.error ?? '音源不可用'}（已尝试 ${_fallbackCount + 1} 个源）',
        playing: false,
      );
      return;
    }
    _fallbackInFlight = true;
    _fallbackCount++;
    final gen = _loadGeneration;
    final excludes = {..._activeExcludes, resolved.winnerId};
    _onSourceUnplayable?.call(resolved, snap.error ?? 'open failed');
    state.value = state.value.copyWith(
      processing: EngineProcessing.loading,
      error: null,
      playing: false,
    );
    final item = _index >= 0 && _index < _queue.length
        ? _queue[_index]
        : null;
    if (item == null) return;
    try {
      final next = await _urlResolver?.call(item, excludes);
      if (gen != _loadGeneration) return;
      if (next == null || next.url.isEmpty) {
        state.value = state.value.copyWith(
          processing: EngineProcessing.error,
          error: '加载失败: 换源后仍无可用地址',
          playing: false,
        );
        return;
      }
      _activeResolved = next;
      _activeExcludes = excludes;
      await _engine.load(Uri.parse(next.url));
      if (gen != _loadGeneration) return;
      await _engine.play();
      _expectCompletion = true;
      // 回退成功：清掉旧 URL 留下的错误文本，并解除回退上下文——
      // 防止旧 URL 的迟到 mpv 错误再触发一轮无谓回退。
      _activeResolved = null;
      state.value = state.value.copyWith(
        processing: EngineProcessing.ready,
        error: null,
        playing: true,
      );
      _prefetchNext();
    } catch (e) {
      if (gen != _loadGeneration) return;
      state.value = state.value.copyWith(
        processing: EngineProcessing.error,
        error: '加载失败: $e（换源后）',
        playing: false,
      );
    } finally {
      _fallbackInFlight = false;
    }
  }

  Future<void> play() async {
    if (current == null && _queue.isNotEmpty) return _loadAt(0);
    await _focus?.activate();
    state.value = state.value.copyWith(playing: true);
    await _engine.play();
  }

  Future<void> pause() async {
    state.value = state.value.copyWith(playing: false);
    await _engine.pause();
  }

  Future<void> seek(Duration pos) => _engine.seek(pos);

  /// 后台预取下一首的播放地址（写入 resolver 的 URL 缓存）。
  /// 切歌时命中缓存即可瞬时出声，不必重新取链。
  void _prefetchNext() {
    final pf = _prefetcher;
    if (pf == null || _queue.length < 2) return;
    final nextIndex = _index + 1;
    if (nextIndex >= _queue.length) return;
    final item = _queue[nextIndex];
    if (item.resolvedUrl?.isNotEmpty == true) return;
    // 不 await：后台进行，失败无影响
    unawaited(pf(item));
  }

  Future<void> next({bool auto = false}) async {
    if (_queue.isEmpty) return;
    if (_repeat == RepeatMode.one && auto) return _loadAt(_index);
    if (_shuffle && _queue.length > 1) {
      var r = _index;
      while (r == _index) {
        r = Random().nextInt(_queue.length);
      }
      return _loadAt(r);
    }
    var nextIndex = _index + 1;
    if (nextIndex >= _queue.length) {
      if (_repeat == RepeatMode.all || !auto) {
        nextIndex = 0;
      } else {
        state.value = state.value.copyWith(playing: false);
        return;
      }
    }
    await _loadAt(nextIndex);
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    final target = _index - 1 < 0 ? _queue.length - 1 : _index - 1;
    await _loadAt(target);
  }

  void setRepeat(RepeatMode mode) {
    _repeat = mode;
    state.value = state.value.copyWith(repeatMode: mode);
  }

  void setShuffle(bool on) {
    _shuffle = on;
    state.value = state.value.copyWith(shuffleOn: on);
  }

  bool _endOfTrackPause = false;

  /// 定时关闭（播完当前首）：置位后 auto 完成时暂停而非切下一首。
  void setEndOfTrackPause(bool v) => _endOfTrackPause = v;

  /// 只解除订阅，**不销毁引擎**。
  ///
  /// 引擎/Player 是进程级原生资源，且 core 为单例；若在此 dispose 引擎，
  /// 任何仍持有本 core 的调用都会抛 `[Player] has been disposed`。
  Future<void> dispose() async {
    await _engineSub?.cancel();
    await _focusSub?.cancel();
    state.removeListener(_pushToCast);
    await _castSub?.cancel();
  }
}
