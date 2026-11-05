import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/core/services/play_history_service.dart';
import 'package:aiwli_music/core/storage/settings_store.dart';

class _MemStore extends SettingsStore {
  _MemStore();
  final Map<String, Map<String, Object?>> data = {};

  @override
  Future<Map<String, Object?>> load(String fileName) async =>
      Map.of(data[fileName] ?? const {});

  // 生产代码改用 loadOrNull 区分「不存在」与「损坏」，
  // 测试替身必须一并覆盖，否则会走真实文件系统（需要 Flutter binding）。
  @override
  Future<Map<String, Object?>?> loadOrNull(String fileName) async =>
      Map.of(data[fileName] ?? const {});

  @override
  Future<void> flush(String fileName, Map<String, Object?> payload) async {
    data[fileName] = Map.of(payload);
  }
}

/// WebDAV 恢复时合并历史：按 key 去重、保留较新的 playedAt、不丢本地条目。
void main() {
  group('PlayHistoryService.importJson', () {
    test('新条目被导入', () async {
      final svc = PlayHistoryService(_MemStore());
      await svc.record(
          sourceId: 'kw', musicId: '1', title: 'A', artist: 'x');
      final added = await svc.importJson(jsonEncode({
        'items': [
          {
            'sourceId': 'wy',
            'musicId': '99',
            'title': 'B',
            'artist': 'y',
            'playedAt': DateTime.now().toIso8601String(),
          }
        ]
      }));
      expect(added, 1);
      expect(svc.items.length, 2);
    });

    test('同一首不重复，保留较新的时间', () async {
      final store = _MemStore();
      final svc = PlayHistoryService(store);
      final older = DateTime.now().subtract(const Duration(days: 1));
      await svc.importJson(jsonEncode({
        'items': [
          {
            'sourceId': 'kw',
            'musicId': '1',
            'title': 'A',
            'artist': 'x',
            'playedAt': older.toIso8601String(),
          }
        ]
      }));
      // 本地再记一次（时间更新）
      await svc.record(
          sourceId: 'kw', musicId: '1', title: 'A', artist: 'x');
      final added = await svc.importJson(jsonEncode({
        'items': [
          {
            'sourceId': 'kw',
            'musicId': '1',
            'title': 'A',
            'artist': 'x',
            'playedAt': older.toIso8601String(),
          }
        ]
      }));
      expect(added, 0, reason: '已存在且本地更新，不应算新增');
      expect(svc.items.length, 1);
      expect(svc.items.single.playedAt.isAfter(older), isTrue);
    });

    test('导入后按时间倒序排列', () async {
      final svc = PlayHistoryService(_MemStore());
      final now = DateTime.now();
      await svc.importJson(jsonEncode({
        'items': [
          {
            'sourceId': 'kw',
            'musicId': 'old',
            'title': 'O',
            'artist': 'a',
            'playedAt': now.subtract(const Duration(days: 3)).toIso8601String(),
          },
          {
            'sourceId': 'kw',
            'musicId': 'new',
            'title': 'N',
            'artist': 'b',
            'playedAt': now.toIso8601String(),
          },
        ]
      }));
      expect(svc.items.first.musicId, 'new');
      expect(svc.items.last.musicId, 'old');
    });

    test('坏数据不崩：空 musicId / 非法类型被跳过', () async {
      final svc = PlayHistoryService(_MemStore());
      final added = await svc.importJson(jsonEncode({
        'items': [
          {'sourceId': 'kw', 'musicId': '', 'title': 'X', 'artist': 'y'},
          'not-a-map',
          123,
        ]
      }));
      expect(added, 0);
      expect(svc.items, isEmpty);
    });

    test('导入受 maxItems 上限约束', () async {
      final svc = PlayHistoryService(_MemStore());
      final now = DateTime.now();
      await svc.importJson(jsonEncode({
        'items': [
          for (var i = 0; i < PlayHistoryService.maxItems + 20; i++)
            {
              'sourceId': 'kw',
              'musicId': '$i',
              'title': 'T$i',
              'artist': 'a',
              'playedAt': now.subtract(Duration(minutes: i)).toIso8601String(),
            }
        ]
      }));
      expect(svc.items.length, PlayHistoryService.maxItems);
    });
  });
}