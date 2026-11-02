import 'quality.dart';

class Artist {
  const Artist({required this.name, this.id = ''});
  final String name;
  final String id;
}

class Album {
  const Album({required this.name, this.id = '', this.picUrl});
  final String name;
  final String id;
  final String? picUrl;
}

/// 一首由某个音源提供的歌曲（跨源统一视图）。
class MusicInfo {
  const MusicInfo({
    required this.sourceId,
    required this.musicId,
    required this.title,
    required this.artist,
    this.album,
    this.duration,
    this.qualities = const [Quality.standard],
  });
  final String sourceId; // 所属音源 id（如 'kw'）
  final String musicId; // 源内歌曲 id
  final String title;
  final String artist; // 展示用拼接（多歌手 " / "）
  final Album? album;
  final Duration? duration;
  final List<Quality> qualities;
}

/// 可播放曲目引用（PlayerCore 队列元素，见设计文档 §3.1）。
class TrackSource {
  const TrackSource({
    required this.sourceId,
    required this.musicId,
    required this.title,
    required this.artist,
    this.duration,
  });
  final String sourceId;
  final String musicId;
  final String title;
  final String artist;
  final Duration? duration;
}

/// 榜单元数据（由音源脚本 boardList 能力提供，壳内零内置榜单）。
class MusicBoard {
  const MusicBoard({required this.id, required this.name});
  final String id;
  final String name;
}
