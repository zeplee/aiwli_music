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
  List<double> eqGains = List.filled(eqBandHz.length, 0);
  String eqPreset = 'flat';

  Future<void> load() async {
    final m = await _store.load(_file);
    final q = m['quality'] as String?;
    for (final v in Quality.values) {
      if (v.name == q) quality = v;
    }
    eqEnabled = m['eqEnabled'] == true;
    eqPreset = m['eqPreset'] as String? ?? 'flat';
    final g = m['eqGains'] as List?;
    if (g != null && g.length == eqBandHz.length) {
      eqGains = g.map((e) => (e as num).toDouble()).toList();
    }
    notifyListeners();
  }

  Future<void> setQuality(Quality q) async {
    if (q == quality) return;
    quality = q;
    notifyListeners();
    await _store.flush(_file, {
      'quality': quality.name,
      'eqEnabled': eqEnabled,
      'eqPreset': eqPreset,
      'eqGains': eqGains,
    });
  }

  Future<void> setEq({bool? enabled, List<double>? gains, String? preset}) async {
    if (enabled != null) eqEnabled = enabled;
    if (gains != null && gains.length == eqBandHz.length) eqGains = gains;
    if (preset != null) eqPreset = preset;
    notifyListeners();
    await _store.flush(_file, {
      'quality': quality.name,
      'eqEnabled': eqEnabled,
      'eqPreset': eqPreset,
      'eqGains': eqGains,
    });
  }
}
