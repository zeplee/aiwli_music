enum SourceCapability {
  searchMusic, searchAlbum, searchArtist, searchPlaylist,
  musicUrl, lyric, pic, albumInfo, artistInfo, playlistImport, topList,
}

enum SourceKind { lxScript, musicFreePlugin }

class SourceManifest {
  const SourceManifest({
    required this.id,
    required this.name,
    required this.kind,
    required this.capabilities,
    this.version,
    this.author,
  });
  final String id;
  final String name;
  final SourceKind kind;
  final Set<SourceCapability> capabilities;
  final String? version;
  final String? author;
}
