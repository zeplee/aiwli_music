import '../models/quality.dart';
import '../storage/settings_store.dart';
import 'safe_notifier.dart';

/// 应用设置（音质档位 + 均衡器），JSON 持久化到 settings.json。
class AppSettings extends SafeNotifier {
  AppSettings(this._store);
  final SettingsStore _store;

  static const _file = 'settings.json';
  static const eqBandHz = <int>[
    31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000,
  ];
  static const double eqMinDb = -12, eqMaxDb = 12;

  Quality quality = Quality.high;
  bool eqEnabled = false;
  /// 歌词翻译 / 罗马音显示开关（网易源提供时才有意义）。
  bool lyricTranslation = true;
  bool lyricRoman = true;

  /// 歌词字号档位（参考栖弦 lyric_settings_sheet：字号独立于系统字号，
  /// 便于车载/大屏单独放大）。1=小 2=中 3=大 4=特大。
  int lyricSizeLevel = 2;

  /// 本地音乐扫描目录白名单（空列表 = 扫描全部目录）。
  /// 参考栖弦 settings 的 directory_picker_tile：让用户指定只看某个文件夹。
  List<String> localMusicDirs = [];

  /// 歌词对齐：true = 左对齐（参考栖弦 TextAlign.start），false = 居中。
  bool lyricAlignStart = false;

  /// 封面页左下角显示三行迷你歌词（参考栖弦 showMiniLyrics）。
  ///
  /// 好处：不切页也能看到当前唱到哪，尤其车载/桌面看封面时。
  /// 默认关：封面是视觉主体，歌词叠上去会抢注意力，交给用户决定。
  bool showMiniLyrics = false;

  /// 主题模式：system = 跟随系统，light = 白天，dark = 夜间。
  ///
  /// 默认 system：现代系统自带日落后切换，跟着走最省心；
  /// 用户想固定昼夜时在设置里改。
  String themeMode = 'system';

  /// 该档位对应的主歌词字号。
  double get lyricFontSize => switch (lyricSizeLevel) {
        1 => 15,
        3 => 23,
        4 => 28,
        _ => 19,
      };
  List<double> eqGains = List.filled(eqBandHz.length, 0);
  String eqPreset = 'flat';

  Future<void> load() async {
    final m = await _store.load(_file);
    final q = m['quality'] as String?;
    for (final v in Quality.values) {
      if (v.name == q) quality = v;
    }
    eqEnabled = m['eqEnabled'] == true;
    sleepTimerMinutes = (m['sleepTimerMinutes'] as num?)?.toInt() ?? 30;
    songSort = m['songSort'] as String? ?? 'title';
    songSortAscending = m['songSortAscending'] != false;
    lyricTranslation = m['lyricTranslation'] != false;
    lyricRoman = m['lyricRoman'] != false;
    lyricSizeLevel = (m['lyricSizeLevel'] as num?)?.toInt() ?? 2;
    lyricAlignStart = m['lyricAlignStart'] == true;
    showMiniLyrics = m['showMiniLyrics'] == true;
    final tm = m['themeMode']?.toString();
    if (tm == 'system' || tm == 'light' || tm == 'dark') themeMode = tm!;
    final dirs = m['localMusicDirs'] as List?;
    if (dirs != null) {
      localMusicDirs = dirs.whereType<String>().toList();
    }
    eqPreset = m['eqPreset'] as String? ?? 'flat';
    final g = m['eqGains'] as List?;
    if (g != null && g.length == eqBandHz.length) {
      eqGains = g.map((e) => (e as num).toDouble()).toList();
    }
    notifyListeners();
  }

  /// 一次性把全部设置落盘（任何单项变更都走这里，避免漏字段）。
  Future<void> _flush() => _store.flush(_file, {
        'quality': quality.name,
        'eqEnabled': eqEnabled,
        'eqPreset': eqPreset,
        'eqGains': eqGains,
        'lyricTranslation': lyricTranslation,
        'lyricRoman': lyricRoman,
        'lyricSizeLevel': lyricSizeLevel,
        'lyricAlignStart': lyricAlignStart,
        'showMiniLyrics': showMiniLyrics,
        'themeMode': themeMode,
        'localMusicDirs': localMusicDirs,
        'sleepTimerMinutes': sleepTimerMinutes,
        'songSort': songSort,
        'songSortAscending': songSortAscending,
      });

  /// 设置主题模式（system / light / dark），立即生效并落盘。
  Future<void> setThemeMode(String mode) async {
    if (mode != 'system' && mode != 'light' && mode != 'dark') return;
    themeMode = mode;
    notifyListeners();
    await _flush();
  }

  Future<void> setLyricPrefs(
      {bool? translation,
      bool? roman,
      int? sizeLevel,
      bool? alignStart,
      bool? miniLyrics}) async {
    if (translation != null) lyricTranslation = translation;
    if (roman != null) lyricRoman = roman;
    if (sizeLevel != null) lyricSizeLevel = sizeLevel.clamp(1, 4);
    if (alignStart != null) lyricAlignStart = alignStart;
    if (miniLyrics != null) showMiniLyrics = miniLyrics;
    notifyListeners();
    await _flush();
  }

  /// 睡眠定时默认时长（分钟），0 表示不记忆。
  int sleepTimerMinutes = 30;

  /// 音乐库排序偏好（对齐参考工程：排序方式也需跨会话记忆）。
  String songSort = 'title';
  bool songSortAscending = true;

  /// 设置本地音乐扫描目录（传空列表 = 扫描全部）。
  Future<void> setLocalMusicDirs(List<String> dirs) async {
    localMusicDirs = List<String>.from(dirs);
    notifyListeners();
    await _flush();
  }

  Future<void> setSongSort(String sort, bool ascending) async {
    songSort = sort;
    songSortAscending = ascending;
    notifyListeners();
    await _flush();
  }

  Future<void> setSleepTimerMinutes(int v) async {
    sleepTimerMinutes = v;
    notifyListeners();
    await _flush();
  }

  Future<void> setQuality(Quality q) async {
    if (q == quality) return;
    quality = q;
    notifyListeners();
    await _flush();
  }

  Future<void> setEq({bool? enabled, List<double>? gains, String? preset}) async {
    if (enabled != null) eqEnabled = enabled;
    if (gains != null && gains.length == eqBandHz.length) eqGains = gains;
    if (preset != null) eqPreset = preset;
    notifyListeners();
    await _flush();
  }
}
