@Tags(['network'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/sources/builtin/kw_sdk.dart';
import 'package:aiwli_music/sources/builtin/tx_sdk.dart';
import 'package:aiwli_music/sources/builtin/wy_sdk.dart';

/// 内置搜索 SDK 联通性实测（真实网络）。
///
/// 默认跳过（见 dart_test.yaml），需要实测时：
///   flutter test --tags network test/builtin_sdk_test.dart
void main() {
  const kw = '周杰伦';

  test('酷我搜索', () async {
    final list = await KwSdk.search(kw, limit: 5);
    // ignore: avoid_print
    print('kw: ${list.length} 条');
    for (final s in list.take(3)) {
      // ignore: avoid_print
      print('  · ${s.title} - ${s.artist} [${s.qualities.map((q) => q.name).join("/")}]');
    }
    expect(list, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('QQ 搜索', () async {
    final list = await TxSdk.search(kw, limit: 5);
    // ignore: avoid_print
    print('tx: ${list.length} 条');
    for (final s in list.take(3)) {
      // ignore: avoid_print
      print('  · ${s.title} - ${s.artist}');
    }
    expect(list, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('网易搜索', () async {
    final list = await WySdk.search(kw, limit: 5);
    // ignore: avoid_print
    print('wy: ${list.length} 条');
    for (final s in list.take(3)) {
      // ignore: avoid_print
      print('  · ${s.title} - ${s.artist}');
    }
    expect(list, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
