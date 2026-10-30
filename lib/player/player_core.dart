import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'audio_engine.dart';
import 'audio_focus_policy.dart';
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
  });
  final String title;
  final String artist;
  final String sourceId;
  final String musicId;
  final String? resolvedUrl;
  final String? album;
  final Uri? artUri;
  final Duration? duration;

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
    Future<String> Function(PlayerItem item)? urlResolver,
  }) : _engine = engine,
        // ignore: prefer_initializing_formals
        _focus = focus,
        // ignore: prefer_initializing_formals
        _urlResolver = urlResolver {
    _engineSub = engine.snapshots.listen(_onEngineSnapshot);
    _focusSub = _focus?.events.listen(_onFocusEvent);
  }

  final AudioEngine _engine;
  final AudioFocusPolicy? _focus;
  final Future<String> Function(PlayerItem item)? _urlResolver;
  StreamSubscription<FocusEvent>? _focusSub;
  bool _wasPlayingBeforeInterruption = false;

  // 栖弦体验（ADR-003/009）：中断→暂停并记忆；恢复→按记忆续播；拔耳机→暂停
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

  void _onEngineSnapshot(EngineSnapshot snap) {
    state.value = state.value.copyWith(
      processing: snap.processing,
      playing: snap.playing,
      position: snap.position,
      duration: snap.duration,
      error: snap.error,
    );
    if (snap.processing == EngineProcessing.completed && _expectCompletion) {
      _expectCompletion = false;
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
      var url = item.resolvedUrl;
      if (url == null || url.isEmpty) {
        final resolver = _urlResolver;
        if (resolver == null) throw Exception('无可用播放地址');
        url = await resolver(item);
      }
      if (gen != _loadGeneration) return;
      await _engine.load(Uri.parse(url));
      if (gen != _loadGeneration) return; // 已被更新的一次切歌覆盖
      await _engine.play();
      _expectCompletion = true;
    } catch (e) {
      if (gen != _loadGeneration) return;
      state.value = state.value.copyWith(
        processing: EngineProcessing.error,
        error: '加载失败: $e',
        playing: false,
      );
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

  Future<void> dispose() async {
    await _engineSub?.cancel();
    await _focusSub?.cancel();
    await _engine.dispose();
  }
}
