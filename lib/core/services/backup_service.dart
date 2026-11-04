import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../models/quality.dart';
import 'logger.dart';
import 'playlists.dart';

/// 全量备份 v3：收藏 + 播放历史 + 歌单 + 音源脚本 + 播放设置。
/// 不含 WebDAV 配置本身（含密码）。
class BackupService {
  BackupService(this._ref);
  final Ref _ref;

  String buildBackupJson() {
    final playlists = _ref.read(playlistsProvider);
    final registry = _ref.read(sourceRegistryProvider);
    final settings = _ref.read(appSettingsProvider);
    return const JsonEncoder.withIndent('  ').convert({
      'version': 3,
      'app': 'AiwliMusic',
      'createdAt': DateTime.now().toIso8601String(),
      'playlists': {
        'playlists': [
          for (final p in playlists.playlists) p.toJson(),
        ],
      },
      'sources': {
        'activeId': registry.activeId,
        'sources': [
          for (final s in registry.installed) s.toJson(),
        ],
      },
      // 播放历史：换机/重装后仍能「继续聆听」
      'history': {
        'items': [
          for (final h in _ref.read(playHistoryProvider).items) h.toJson(),
        ],
      },
      'settings': {
        'quality': settings.quality.name,
        'eqEnabled': settings.eqEnabled,
        'eqPreset': settings.eqPreset,
        'eqGains': settings.eqGains,
        'lyricTranslation': settings.lyricTranslation,
        'lyricRoman': settings.lyricRoman,
      },
    });
  }

  Future<void> upload() async {
    final json = buildBackupJson();
    await _ref.read(webDavServiceProvider).uploadBackup(json);
  }

  /// 恢复（合并）：收藏去重合并、歌单按 id 合并、缺失音源重新导入、设置覆盖。
  /// 返回人类可读摘要。
  Future<String> restore(String raw) async {
    final data = jsonDecode(raw) as Map<Object?, Object?>;
    final version = (data['version'] as num?)?.toInt() ?? 1;
    final parts = <String>[];

    // —— 收藏：老备份（v1/v2 的 favorites 段）并入「我的收藏」系统歌单 ——
    final favRaw =
        (data['favorites'] as Map?) ?? {'items': data['items'] ?? const []};
    final favList = (favRaw['items'] as List?) ?? const [];
    if (favList.isNotEmpty) {
      final entries = <PlaylistEntry>[];
      for (final m in favList) {
        if (m is! Map) continue;
        final sourceId = m['sourceId']?.toString() ?? '';
        final musicId = m['musicId']?.toString() ?? '';
        if (musicId.isEmpty) continue;
        entries.add(PlaylistEntry(
          sourceId: sourceId,
          musicId: musicId,
          title: m['title']?.toString() ?? '',
          artist: m['artist']?.toString() ?? '',
          album: m['album'] as String?,
          picUrl: m['picUrl'] as String?,
          durationMs: (m['durationMs'] as num?)?.toInt(),
        ));
      }
      if (entries.isNotEmpty) {
        final added =
            await _ref.read(playlistsProvider).mergeIntoFavorites(entries);
        if (added > 0) parts.add('收藏 +$added');
      }
    }

    // —— 播放历史（按 key 合并，保留较新的 playedAt）——
    final histRaw = (data['history'] as Map?)?['items'] as List?;
    if (histRaw != null && histRaw.isNotEmpty) {
      final added = await _ref
          .read(playHistoryProvider)
          .importJson(jsonEncode({'items': histRaw}));
      if (added > 0) parts.add('播放历史 +$added');
    }

    // —— 歌单（按 id 合并）——
    final plRaw = (data['playlists'] as Map?)?['playlists'] as List?;
    if (plRaw != null && plRaw.isNotEmpty) {
      final svc = _ref.read(playlistsProvider);
      var added = 0, replaced = 0;
      for (final e in plRaw) {
        final p = Playlist.fromJson(e as Map);
        if (p.id.isEmpty || p.entries.isEmpty) continue;
        final exists = svc.playlists.any((x) => x.id == p.id);
        if (exists) {
          svc.delete(p.id);
          replaced++;
        } else {
          added++;
        }
        svc.playlists = [...svc.playlists, p];
      }
      svc.unawaitedPersist();
      if (added > 0) parts.add('歌单 +$added');
      if (replaced > 0) parts.add('歌单更新 $replaced');
    }

    // —— 音源脚本（缺失才导入，脚本以 id 判等）——
    final srcRaw = (data['sources'] as Map?)?['sources'] as List?;
    if (srcRaw != null && srcRaw.isNotEmpty) {
      final registry = _ref.read(sourceRegistryProvider);
      var imported = 0;
      for (final e in srcRaw) {
        final m = (e as Map).cast<Object?, Object?>();
        final script = m['script'] as String? ?? '';
        final id = m['id'] as String? ?? '';
        if (script.isEmpty || id.isEmpty) continue;
        if (registry.installed.any((s) => s.id == id)) continue;
        final src = await registry.importScript(script);
        final enabled = m['enabled'] == true;
        if (!enabled) await registry.setEnabled(src.id, false);
        imported++;
      }
      final activeId = (data['sources'] as Map?)?['activeId'] as String?;
      if (activeId != null &&
          activeId.isNotEmpty &&
          registry.installed.any((s) => s.id == activeId && s.enabled)) {
        await registry.setActive(activeId);
      }
      if (imported > 0) parts.add('音源 +$imported');
    }

    // —— 设置（覆盖）——
    final st = (data['settings'] as Map?)?.cast<Object?, Object?>();
    if (st != null) {
      final settings = _ref.read(appSettingsProvider);
      final qName = st['quality'] as String?;
      for (final q in Quality.values) {
        if (q.name == qName) await settings.setQuality(q);
      }
      final gains =
          (st['eqGains'] as List?)?.map((e) => (e as num).toDouble()).toList();
      await settings.setEq(
        enabled: st['eqEnabled'] == true,
        gains: gains,
        preset: st['eqPreset'] as String?,
      );
      if (st['lyricTranslation'] != null || st['lyricRoman'] != null) {
        await settings.setLyricPrefs(
          translation: st['lyricTranslation'] as bool?,
          roman: st['lyricRoman'] as bool?,
        );
      }
      parts.add('设置 ✓');
    }

    AppLog.i('Backup',
        '恢复完成 v$version: ${parts.isEmpty ? '无变化' : parts.join('，')}');
    return parts.isEmpty ? '本地已是最新，无变化' : '已恢复：${parts.join('，')}';
  }
}

/// 文本歌单（lx 风格）：每行 "[歌手 - ]标题"。
class TextPlaylistLine {
  TextPlaylistLine(this.title, this.artist);
  final String title;
  final String? artist;
}

List<TextPlaylistLine> parseTextPlaylist(String content) {
  final out = <TextPlaylistLine>[];
  for (final raw in content.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('[')) continue;
    final dash = line.indexOf(' - ');
    if (dash > 0) {
      out.add(TextPlaylistLine(line.substring(dash + 3).trim(),
          line.substring(0, dash).trim()));
    } else {
      out.add(TextPlaylistLine(line, null));
    }
  }
  return out;
}
