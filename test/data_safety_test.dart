import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/core/services/app_paths.dart';
import 'package:aiwli_music/core/services/playlists.dart';
import 'package:aiwli_music/core/storage/settings_store.dart';

/// 数据安全回归测试。
///
/// 真机事故（已取证）：playlists.json 里出现**两个 JSON 拼接**：
///   ..."folder":"梁登宵"}]}509","title":"咱们结婚吧"...
/// 原因：File.writeAsString 先截断再写，两个并发 flush 交错。
/// 后果：下次 load 解析失败 → 返回空 → **用户的歌单被清空**。
///
/// 本测试锁死三道防线：
///   1. 并发 flush 同一文件不产生损坏（原子写 + 串行化）
///   2. 历史损坏文件能被抢救出最后一个完整对象
///   3. 无法抢救时不返回空、且**禁止覆盖写盘**
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('aiwli_store_');
    AppPaths.overrideSupportDirForTesting(tmp.path);
  });

  tearDown(() {
    AppPaths.overrideSupportDirForTesting(null);
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('并发写同一文件不会产生"两个 JSON 拼接"', () async {
    const store = SettingsStore();
    const fileName = 'concurrent_probe.json';
    final target = File('${tmp.path}/$fileName');

    await Future.wait([
      for (var i = 0; i < 20; i++)
        store.flush(fileName, {
          'seq': i,
          'payload': List.generate(200, (j) => 'row-$i-$j').join(','),
        }),
    ]);

    final text = await target.readAsString();
    final parsed = jsonDecode(text); // 损坏会在这里抛
    expect(parsed, isA<Map>());
    expect(parsed['seq'], isA<int>());
  });

  test('真实损坏样本能被抢救（取最后一个完整对象）', () async {
    const store = SettingsStore();
    const fileName = 'rescue_probe.json';
    final target = File('${tmp.path}/$fileName');
    // 复刻真机损坏形态：完整 JSON + 后面粘了残片
    await target.writeAsString(
        '{"playlists":[{"id":"a","name":"试听列表","createdAtMs":1,"entries":[]}]}'
        '509","title":"残片","artist":"x"}');

    final r = await store.loadOrNull(fileName);
    expect(r, isNotNull, reason: '应能抢救出完整部分，不能返回空');
    final list = r!['playlists'] as List;
    expect(list.length, 1);
    expect((list.first as Map)['name'], '试听列表');
  });

  test('完全无法抢救时返回 null（而不是空 Map）', () async {
    const store = SettingsStore();
    const fileName = 'corrupt_probe.json';
    await File('${tmp.path}/$fileName').writeAsString('@@@ 垃圾内容 @@@');

    final r = await store.loadOrNull(fileName);
    expect(r, isNull, reason: '损坏必须返回 null，让调用方放弃写盘');
  });

  test('损坏文件时 PlaylistService 拒绝覆盖写盘（保护原数据）', () async {
    const store = SettingsStore();
    final target = File('${tmp.path}/playlists.json');
    await target.writeAsString('@@@ not json at all @@@');
    final before = await target.readAsString();

    final svc = PlaylistService(store);
    await svc.load();

    expect(svc.loadCorrupted, isTrue);
    svc.create('不应被写入的歌单');
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final after = await target.readAsString();
    expect(after, before, reason: '损坏状态下绝不能覆盖原文件');
  });

  test('正常写入后能完整读回（不丢歌单）', () async {
    const store = SettingsStore();
    final svc = PlaylistService(store);
    await svc.load();
    final p = svc.create('我的测试歌单');
    svc.addEntries(p.id, const [
      PlaylistEntry(sourceId: 'kw', musicId: '1', title: 'A', artist: 'x'),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // 新实例重新读，确认落盘完整
    final svc2 = PlaylistService(store);
    await svc2.load();
    expect(svc2.loadCorrupted, isFalse);
    final found = svc2.playlists.where((x) => x.id == p.id).firstOrNull;
    expect(found, isNotNull);
    expect(found!.entries.length, 1);
  });
}