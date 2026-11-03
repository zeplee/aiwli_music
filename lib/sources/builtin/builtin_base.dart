import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import '../../core/models/music.dart';
import '../../core/models/quality.dart';
import '../../core/services/http_client.dart';

/// 内置平台搜索 SDK 的共同底座。
///
/// 说明：本文件只做**搜索**（取歌名/歌手/专辑/时长/音质标签），不含任何取链逻辑。
/// 播放地址一律由用户导入的音源脚本提供（壳不分发音源）。
class BuiltinHttp {
  BuiltinHttp._();

  static final Dio _dio = Http.create();

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static Future<dynamic> getJson(String url,
      {Map<String, String>? headers, ResponseType type = ResponseType.json}) async {
    final resp = await _dio.get<dynamic>(
      url,
      options: Options(
        headers: {
          'User-Agent': _ua,
          'Referer': 'https://www.kuwo.cn/',
          ...?headers,
        },
        responseType: type,
        validateStatus: (c) => c != null && c < 500,
      ),
    );
    return resp.data;
  }

  /// 原始请求（返回 String，交给调用方自行解码）。
  static Future<dynamic> getRaw(
    String url, {
    String method = 'GET',
    String? body,
    Map<String, String>? headers,
  }) async {
    final resp = await _dio.request<dynamic>(
      url,
      data: body,
      options: Options(
        method: method,
        headers: {'User-Agent': _ua, ...?headers},
        responseType: ResponseType.plain,
        validateStatus: (c) => c != null && c < 500,
      ),
    );
    return resp.data;
  }

  static Future<dynamic> postJson(
    String url, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  }) async {
    final resp = await _dio.post<dynamic>(
      url,
      data: data,
      options: Options(
        headers: {
          'User-Agent': _ua,
          'Content-Type': 'application/x-www-form-urlencoded',
          ...?headers,
        },
        validateStatus: (c) => c != null && c < 500,
      ),
    );
    return resp.data;
  }
}

/// 音质标签（搜索阶段只是展示用，真实可用性由脚本决定）。
List<Quality> parseQualitys(dynamic raw) {
  final out = <Quality>{Quality.standard};
  if (raw is List) {
    for (final q in raw) {
      final s = q is Map ? '${q['type'] ?? ''}' : '$q';
      if (s.contains('flac') && s.contains('24')) {
        out.add(Quality.hires);
      } else if (s.contains('flac')) {
        out.add(Quality.lossless);
      } else if (s.contains('320')) {
        out.add(Quality.high);
      }
    }
  } else if (raw is Map) {
    for (final k in raw.keys) {
      out.addAll(parseQualitys([k]));
    }
  }
  return out.toList()
    ..sort((a, b) => a.index.compareTo(b.index));
}

/// 多歌手拼接（"A / B"），与展示层约定一致。
String joinSingers(dynamic raw) {
  if (raw is List) {
    final names = <String>[];
    for (final a in raw) {
      if (a is Map) {
        final n = a['name'] ?? a['artistName'] ?? a['singerName'];
        if (n != null && '$n'.trim().isNotEmpty) names.add('$n'.trim());
      } else if (a != null && '$a'.trim().isNotEmpty) {
        names.add('$a'.trim());
      }
    }
    if (names.isNotEmpty) return names.join(' / ');
  }
  if (raw is String) {
    return raw.replaceAll('&', ' / ').replaceAll('、', ' / ');
  }
  return '未知歌手';
}

/// HTML 实体解码（部分接口标题带 &amp; 等）。
/// 复用工程已有的 html 包，避免新增依赖。
String decodeText(dynamic raw) {
  final s = raw == null ? '' : '$raw';
  if (!s.contains('&')) return s.trim();
  try {
    return html_parser.parseFragment(s).text?.trim() ?? s.trim();
  } catch (_) {
    return s.trim();
  }
}

/// "mm:ss" → Duration。
Duration? parseInterval(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) return Duration(seconds: raw);
  final s = '$raw';
  final m = RegExp(r'^(\d+):(\d+)$').firstMatch(s);
  if (m != null) {
    return Duration(minutes: int.parse(m.group(1)!), seconds: int.parse(m.group(2)!));
  }
  final secs = int.tryParse(s);
  return secs == null ? null : Duration(seconds: secs);
}

/// 组装统一 MusicInfo。
MusicInfo buildSong({
  required String sourceId,
  required String musicId,
  required String title,
  required String artist,
  String? album,
  String? albumId,
  String? picUrl,
  Duration? duration,
  List<Quality>? qualities,
}) {
  return MusicInfo(
    sourceId: sourceId,
    musicId: musicId,
    title: decodeText(title),
    artist: decodeText(artist),
    album: Album(
        name: (album == null || album.isEmpty) ? '' : decodeText(album),
        id: albumId ?? '',
        picUrl: (picUrl == null || picUrl.isEmpty) ? null : picUrl),
    duration: duration,
    qualities: qualities ?? const [Quality.standard],
  );
}

/// JSON 安全解析（部分接口返回非 JSON 时返回 null 而不是抛异常）。
dynamic tryDecodeJson(dynamic data) {
  if (data == null) return null;
  if (data is Map || data is List) return data;
  if (data is String) {
    try {
      return jsonDecode(data);
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// 宽松 base64 解码（QQ 歌词接口返回）。
String utf8DecodeBase64(String input) {
  var s = input.replaceAll(RegExp(r'\s'), '');
  s = s.replaceAll('-', '+').replaceAll('_', '/');
  while (s.length % 4 != 0) {
    s += '=';
  }
  return utf8.decode(base64Decode(s));
}
