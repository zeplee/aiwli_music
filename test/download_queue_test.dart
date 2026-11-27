import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:aiwli_music/core/services/download_queue.dart';

void main() {
  late DownloadQueue q;

  DownloadQueue build(
    Future<void> Function(DownloadJob job, DownloadCancel cancel) run, {
    int maxConcurrent = 2,
  }) =>
      DownloadQueue(run: run, maxConcurrent: maxConcurrent, onChanged: () {});

  test('入队去重：同 key 未完成时不会重复排队', () {
    q = build((job, cancel) async {});
    final first = q.enqueue('kw/1', title: '歌', artist: '手');
    final second = q.enqueue('kw/1', title: '歌', artist: '手');
    expect(first, isNotNull);
    expect(second, isNull);
    expect(q.jobs.length, 1);
  });

  test('并发上限受控，完成一个才补下一个', () async {
    final gates = <String, Completer<void>>{};
    q = build((job, cancel) async {
      gates[job.key] = Completer<void>();
      await gates[job.key]!.future;
      job.status = DownloadStatus.downloading;
    }, maxConcurrent: 2);

    q.enqueue('a', title: 'A', artist: '-');
    q.enqueue('b', title: 'B', artist: '-');
    q.enqueue('c', title: 'C', artist: '-');
    await pump();
    expect(q.activeCount, 2);
    expect(gates.containsKey('c'), isFalse, reason: '第三个还没启动');

    gates['a']!.complete();
    await pump();
    expect(q.activeCount, 2);
    expect(gates.containsKey('c'), isTrue, reason: '腾出槽位后第三个启动');

    gates['b']!.complete();
    gates['c']!.complete();
    await pump();
    expect(q.activeCount, 0);
  });

  test('pause 真中断流式下载（cancel 回调触发），状态为已暂停', () async {
    late DownloadCancel token;
    q = build((job, cancel) async {
      token = cancel;
      await Future<void>.delayed(const Duration(seconds: 1));
      job.status = DownloadStatus.done;
    });

    final job = q.enqueue('a', title: 'A', artist: '-')!;
    await pump();
    q.pause(job);
    expect(token.cancelled, isTrue, reason: '必须触发 cancel 才能中断 dio');
    expect(job.status, DownloadStatus.paused);
    expect(q.activeCount, 0);
  });

  test('resume / retry 状态迁移正确', () async {
    var attempt = 0;
    final gates = <int, Completer<void>>{};
    final pausing = build((job, cancel) async {
      final id = ++attempt;
      gates[id] = Completer<void>();
      await gates[id]!.future;
      job.status = DownloadStatus.downloading;
    });
    final job = pausing.enqueue('a', title: 'A', artist: '-')!;
    await pump();
    pausing.pause(job);
    expect(job.status, DownloadStatus.paused);
    pausing.resume(job);
    await pump();
    expect(attempt, 2, reason: 'resume 会重新执行');
    gates[1]!.complete();
    gates[2]!.complete();
    await pump();

    // 模拟失败后重试
    final failing = build((job, cancel) async => throw StateError('boom'));
    final bad = failing.enqueue('b', title: 'B', artist: '-')!;
    await pump();
    expect(bad.status, DownloadStatus.failed);
    failing.retry(bad);
    await pump();
    expect(bad.status, DownloadStatus.failed, reason: '执行器仍失败');
    expect(failing.history.contains(bad), isTrue);
  });

  test('完成与失败都进 history，clearFinished 只清记录', () async {
    q = build((job, cancel) async {
      if (job.key == 'bad') throw StateError('fail');
      job.status = DownloadStatus.done;
    });
    q.enqueue('ok', title: 'OK', artist: '-');
    q.enqueue('bad', title: 'Bad', artist: '-');
    await pump();
    expect(q.history.length, 2);
    expect(q.jobs.where((j) => j.finished).length, 2);

    q.clearFinished();
    expect(q.jobs, isEmpty);
    expect(q.history.length, 2, reason: 'clearFinished 不清空历史');
  });

  test('remove 取消在途任务且不留历史', () async {
    q = build((job, cancel) async {
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    final job = q.enqueue('a', title: 'A', artist: '-')!;
    await pump();
    q.remove(job);
    expect(job.status, DownloadStatus.resolving);
    expect(q.jobs, isEmpty);
    expect(q.history, isEmpty);
  });
}

Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 20));
