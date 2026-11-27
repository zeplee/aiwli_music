import 'dart:async';

/// 下载任务状态。
enum DownloadStatus { queued, resolving, downloading, paused, failed, done }

/// 下载任务（纯数据，不含 Flutter / Riverpod 依赖）。
class DownloadJob {
  DownloadJob({
    required this.key,
    required this.title,
    required this.artist,
  });

  final String key;
  final String title;
  final String artist;

  DownloadStatus status = DownloadStatus.queued;
  int received = 0;
  int total = 0;
  String? savedUri;
  String? savedPath;
  String? error;
  DateTime createdAt = DateTime.now();

  bool get playable => savedUri != null && savedUri!.isNotEmpty;
  bool get finished =>
      status == DownloadStatus.done || status == DownloadStatus.failed;
}

/// 下载队列状态机（纯 Dart，可独立实例化、可注入执行器）。
///
/// 只管并发控制与状态迁移，不碰网络/存储；真正下载由 [run] 提供，
/// 这样测试可以完全离线地断言 pause/resume/retry 行为。
class DownloadQueue {
  DownloadQueue({
    required this.run,
    this.maxConcurrent = 2,
    this.onChanged,
  });

  /// 执行一个任务。cancel 触发时实现应中断流式下载并抛
  /// [DownloadCancelled]，否则会被误判为失败。
  final Future<void> Function(DownloadJob job, DownloadCancel cancel) run;
  final int maxConcurrent;
  final void Function()? onChanged;

  final List<DownloadJob> jobs = [];
  final List<DownloadJob> history = [];
  final Map<String, DownloadCancel> _tokens = {};
  final Set<String> _active = {};

  void _notify() => onChanged?.call();

  /// 入队；同一首歌（key 相同）不重复排队。
  DownloadJob? enqueue(String key, {required String title, required String artist}) {
    if (jobs.any((j) => j.key == key && !j.finished)) return null;
    final job = DownloadJob(key: key, title: title, artist: artist);
    jobs.insert(0, job);
    history.removeWhere((j) => j.key == key);
    _notify();
    _pump();
    return job;
  }

  void pause(DownloadJob job) {
    if (job.status != DownloadStatus.downloading &&
        job.status != DownloadStatus.resolving &&
        job.status != DownloadStatus.queued) {
      return;
    }
    _tokens[job.key]?.cancel();
    job.status = DownloadStatus.paused;
    _active.remove(job.key);
    _notify();
    _pump();
  }

  void resume(DownloadJob job) {
    if (job.status != DownloadStatus.paused) return;
    job.status = DownloadStatus.queued;
    job.error = null;
    _notify();
    _pump();
  }

  void retry(DownloadJob job) {
    if (job.status != DownloadStatus.failed &&
        job.status != DownloadStatus.paused) {
      return;
    }
    job.status = DownloadStatus.queued;
    job.error = null;
    job.received = 0;
    if (!jobs.contains(job)) jobs.insert(0, job);
    history.remove(job);
    _notify();
    _pump();
  }

  void remove(DownloadJob job) {
    _tokens[job.key]?.cancel();
    _tokens.remove(job.key);
    _active.remove(job.key);
    jobs.remove(job);
    history.remove(job);
    _notify();
    _pump();
  }

  void clearFinished() {
    for (final j in jobs.where((j) => j.finished).toList()) {
      _tokens[j.key]?.cancel();
      jobs.remove(j);
      if (!history.contains(j)) history.insert(0, j);
    }
    _notify();
  }

  void _pump() {
    while (_active.length < maxConcurrent) {
      DownloadJob? next;
      for (final j in jobs) {
        if (j.status == DownloadStatus.queued) {
          next = j;
          break;
        }
      }
      if (next == null) return;
      _start(next);
    }
  }

  void _start(DownloadJob job) {
    final token = DownloadCancel();
    _tokens[job.key] = token;
    _active.add(job.key);
    job.status = DownloadStatus.resolving;
    _notify();
    unawaited(() async {
      try {
        await run(job, token);
        if (token.cancelled) return; // pause/remove 已改过状态
        job.status = DownloadStatus.done;
      } on DownloadCancelled {
        return;
      } catch (e) {
        if (token.cancelled) return;
        job.status = DownloadStatus.failed;
        job.error = '$e';
      } finally {
        _tokens.remove(job.key);
        _active.remove(job.key);
        if (job.finished && !history.contains(job)) history.insert(0, job);
        _notify();
        _pump();
      }
    }());
  }

  int get activeCount => _active.length;
}

class DownloadCancel {
  bool cancelled = false;
  void Function()? onCancel;
  void cancel() {
    cancelled = true;
    onCancel?.call();
  }
}

class DownloadCancelled implements Exception {
  const DownloadCancelled();
}
