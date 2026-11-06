import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/core/services/play_history_service.dart';
import 'package:aiwli_music/core/storage/settings_store.dart';

/// 内存 store（不落盘）。
class _MemStore implements SettingsStore {
  final Map<String, Map<String, Object?>> _d = {};
  @override
  Future<Map<String, Object?>> load(String name) async => _d[name] ?? {};
  @override
  Future<Map<String, Object?>?> loadOrNull(String name) async => _d[name];
  @override
  Future<void> flush(String name, Map<String, Object?> data) async =>
      _d[name] = data;
}

/// 「试听列表并入最近」的回归测试。
///
/// 背景：lx 同步来的「试听列表」本质是试听历史，与「最近」Tab 语义重复。
/// 合并时最大的风险是把上千首用户数据弄丢，所以这里锁死三件事：
///   1. 1882 首级的大批量导入**不被截断**
///   2. 与已有历史重复的条目只保留一条（不产生重复项）
///   3. 重复合并是幂等的（不会越并越多）
void main() {
  test('大批量导入不截断（试听列表 1882 首量级）', () async {
    final svc = PlayHistoryService(_MemStore());
    final base = DateTime.now();
    final items = [
      for (var i = 0; i < 1882; i++)
        HistoryItem(
          sourceId: 'tx',
          musicId: 'tx_$i',
          title: 'T$i',
          artist: 'a',
          playedAt: base.subtract(Duration(seconds: i)),
        ),
    ];

    final added = await svc.importItems(items);

    expect(added, 1882, reason: '全部都必须进历史，一条都不能丢');
    expect(svc.items.length, 1882);
    // 最新的排在最前（base 是新的，i 越大越旧）
    expect(svc.items.first.musicId, 'tx_0');
    expect(svc.items.last.musicId, 'tx_1881');
  });

  test('与已有历史去重，保留 playedAt 较新的那条', () async {
    final svc = PlayHistoryService(_MemStore());
    final old = DateTime.now().subtract(const Duration(days: 1));
    await svc.record(sourceId: 'tx', musicId: 'A', title: '旧标题', artist: 'a');

    final added = await svc.importItems([
      HistoryItem(
        sourceId: 'tx',
        musicId: 'A',
        title: '新标题',
        artist: 'a',
        playedAt: DateTime.now(),
      ),
      HistoryItem(
        sourceId: 'tx',
        musicId: 'B',
        title: '全新',
        artist: 'b',
        playedAt: DateTime.now(),
      ),
    ]);

    expect(added, 1, reason: 'A 已存在不算新增，只有 B 是新的');
    expect(svc.items.length, 2, reason: '不能出现两条 A');
    final a = svc.items.firstWhere((e) => e.musicId == 'A');
    expect(a.title, '新标题', reason: '保留较新的记录');
    expect(a.playedAt.isAfter(old), isTrue);
  });

  test('重复合并是幂等的（第二次新增 0 条）', () async {
    final store = _MemStore();
    final svc = PlayHistoryService(store);
    final base = DateTime.now();
    final items = [
      for (var i = 0; i < 50; i++)
        HistoryItem(
          sourceId: 'tx',
          musicId: 'tx_$i',
          title: 'T$i',
          artist: 'a',
          playedAt: base.subtract(Duration(seconds: i)),
        ),
    ];

    expect(await svc.importItems(items), 50);

    // 同一批再并一次（模拟迁移标记丢失）
    final again = await svc.importItems(items);
    expect(again, 0, reason: '不能重复累加');
    expect(svc.items.length, 50);
  });

  test('musicId 为空的脏数据被跳过', () async {
    final svc = PlayHistoryService(_MemStore());
    final added = await svc.importItems([
      HistoryItem(
        sourceId: 'tx',
        musicId: '',
        title: '无 id',
        artist: 'a',
        playedAt: DateTime.now(),
      ),
      HistoryItem(
        sourceId: 'tx',
        musicId: 'ok',
        title: '正常',
        artist: 'b',
        playedAt: DateTime.now(),
      ),
    ]);
    expect(added, 1);
    expect(svc.items.length, 1);
  });

  test('合并后持久化，重开实例仍在', () async {
    final store = _MemStore();
    final a = PlayHistoryService(store);
    await a.importItems([
      for (var i = 0; i < 100; i++)
        HistoryItem(
          sourceId: 'tx',
          musicId: 'tx_$i',
          title: 'T$i',
          artist: 'x',
          playedAt: DateTime.now().subtract(Duration(seconds: i)),
        ),
    ]);

    final b = PlayHistoryService(store);
    await b.ensureLoaded();
    expect(b.items.length, 100, reason: '大文件也要能完整读回');
  });
}