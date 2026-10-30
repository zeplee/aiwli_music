import '../core/models/music.dart';
import '../core/models/quality.dart';
import 'manifest.dart';

/// 音源统一接口（lx 脚本与 MusicFree 插件都归一到此，ADR-004）。
abstract interface class MusicSource {
  SourceManifest get manifest;

  Future<List<MusicInfo>> searchMusic(String keyword, {int page = 1});
  Future<String> getMusicUrl(String musicId, Quality quality);
  Future<String?> getLyric(String musicId);
  Future<Uri?> getCover(String musicId);
}
