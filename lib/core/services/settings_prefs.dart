import '../models/quality.dart';

/// 搜索源平台白名单（与 BuiltinSearch.order 一致）。
const List<String> kSearchSources = ['kw', 'tx', 'wy', 'kg', 'mg'];

/// 点击搜索结果的行为。
const List<String> kSearchResultActions = ['play', 'replaceQueue'];

/// 下载文件命名方式。
const List<String> kDownloadNameStyles = ['artist_title', 'title_artist'];

/// 搜索与下载偏好（纯 Dart，可独立实例化、可单独测试）。
///
/// 所有字段都带白名单/枚举校验，损坏值不会污染其他字段；
/// [toJson] 只导出这 5 项，不含 WebDAV 密码等敏感信息。
class SettingsPrefs {
  const SettingsPrefs({
    this.defaultSearchSource = 'wy',
    this.enabledSearchSources = const {'kw', 'tx', 'wy', 'kg', 'mg'},
    this.searchResultAction = 'play',
    this.downloadQuality = Quality.standard,
    this.downloadFileNameStyle = 'artist_title',
  });

  final String defaultSearchSource;
  final Set<String> enabledSearchSources;
  final String searchResultAction;
  final Quality downloadQuality;
  final String downloadFileNameStyle;

  static const _defaultEnabled = <String>{'kw', 'tx', 'wy', 'kg', 'mg'};

  /// 从持久化数据构造。非法值逐字段回退默认值，不抛异常。
  static SettingsPrefs fromMap(Map<Object?, Object?> m) => SettingsPrefs(
        defaultSearchSource: _validated(
          m['defaultSearchSource'],
          kSearchSources,
          'wy',
        ),
        enabledSearchSources: _validatedSources(m['enabledSearchSources']),
        searchResultAction: _validated(
          m['searchResultAction'],
          kSearchResultActions,
          'play',
        ),
        downloadQuality: _validatedQuality(m['downloadQuality']),
        downloadFileNameStyle: _validated(
          m['downloadFileNameStyle'],
          kDownloadNameStyles,
          'artist_title',
        ),
      );

  Map<String, Object?> toJson() => {
        'defaultSearchSource': defaultSearchSource,
        'enabledSearchSources': enabledSearchSources.toList()..sort(),
        'searchResultAction': searchResultAction,
        'downloadQuality': downloadQuality.name,
        'downloadFileNameStyle': downloadFileNameStyle,
      };

  /// 导入配置：逐字段校验，非法值跳过并收集说明；合法值立即生效。
  /// 返回被跳过的字段说明列表（空 = 全部应用）。
  static List<String> applyFromJson(
    Map<Object?, Object?> json,
    void Function(SettingsPrefs prefs) apply,
  ) {
    final warnings = <String>[];
    var p = const SettingsPrefs();

    final src = json['defaultSearchSource'];
    if (src is String && kSearchSources.contains(src)) {
      p = p.copyWith(defaultSearchSource: src);
    } else if (src != null) {
      warnings.add('默认搜索平台值非法，已跳过');
    }

    final sources = json['enabledSearchSources'];
    if (sources is List) {
      final valid = sources
          .whereType<String>()
          .where(kSearchSources.contains)
          .toSet();
      if (valid.isNotEmpty) {
        p = p.copyWith(enabledSearchSources: valid);
      } else {
        warnings.add('已启用搜索源为空或非法，已跳过');
      }
    } else if (sources != null) {
      warnings.add('已启用搜索源格式非法，已跳过');
    }

    final action = json['searchResultAction'];
    if (action is String && kSearchResultActions.contains(action)) {
      p = p.copyWith(searchResultAction: action);
    } else if (action != null) {
      warnings.add('点击结果行为值非法，已跳过');
    }

    final q = json['downloadQuality'];
    if (q is String && Quality.values.any((e) => e.name == q)) {
      p = p.copyWith(
          downloadQuality: Quality.values.firstWhere((e) => e.name == q));
    } else if (q != null) {
      warnings.add('下载音质值非法，已跳过');
    }

    final style = json['downloadFileNameStyle'];
    if (style is String && kDownloadNameStyles.contains(style)) {
      p = p.copyWith(downloadFileNameStyle: style);
    } else if (style != null) {
      warnings.add('下载命名方式值非法，已跳过');
    }

    // 约束：默认搜索平台必须在已启用集合内，且至少保留 1 个源。
    final enabled = {...p.enabledSearchSources};
    if (!enabled.contains(p.defaultSearchSource)) {
      enabled.add(p.defaultSearchSource);
    }
    p = p.copyWith(enabledSearchSources: enabled);

    apply(p);
    return warnings;
  }

  SettingsPrefs copyWith({
    String? defaultSearchSource,
    Set<String>? enabledSearchSources,
    String? searchResultAction,
    Quality? downloadQuality,
    String? downloadFileNameStyle,
  }) =>
      SettingsPrefs(
        defaultSearchSource:
            defaultSearchSource ?? this.defaultSearchSource,
        enabledSearchSources:
            enabledSearchSources ?? this.enabledSearchSources,
        searchResultAction: searchResultAction ?? this.searchResultAction,
        downloadQuality: downloadQuality ?? this.downloadQuality,
        downloadFileNameStyle:
            downloadFileNameStyle ?? this.downloadFileNameStyle,
      );

  static String _validated(Object? raw, List<String> allowed, String fallback) =>
      raw is String && allowed.contains(raw) ? raw : fallback;

  static Set<String> _validatedSources(Object? raw) {
    if (raw is! List) return _defaultEnabled;
    final valid = raw.whereType<String>().where(kSearchSources.contains).toSet();
    return valid.isEmpty ? _defaultEnabled : valid;
  }

  static Quality _validatedQuality(Object? raw) {
    if (raw is! String) return Quality.standard;
    for (final q in Quality.values) {
      if (q.name == raw) return q;
    }
    return Quality.standard;
  }
}
