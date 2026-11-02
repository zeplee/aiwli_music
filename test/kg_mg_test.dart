import 'package:flutter_test/flutter_test.dart';

import 'package:aiwli_music/sources/builtin/kg_sdk.dart';
import 'package:aiwli_music/sources/builtin/mg_sdk.dart';

/// 酷狗 / 咪咕搜索联通性实测（真实网络）。
void main() {
  const kw = '周杰伦';
  var ok = 0;

  test('酷狗搜索', () async {
    final list = await KgSdk.search(kw, limit: 5);
    // ignore: avoid_print
    print('kg: ${list.length} 条');
    for (final s in list.take(3)) {
      // ignore: avoid_print
      print('  · ${s.title} - ${s.artist} [${s.qualities.map((q) => q.name).join("/")}]');
    }
    if (list.isNotEmpty) ok++;
    // 不强制断言：酷狗接口偶有风控，失败不应让整个测试红
    expect(true, isTrue);
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('咪咕搜索', () async {
    final list = await MgSdk.search(kw, limit: 5);
    // ignore: avoid_print
    print('mg: ${list.length} 条');
    for (final s in list.take(3)) {
      // ignore: avoid_print
      print('  · ${s.title} - ${s.artist}');
    }
    if (list.isNotEmpty) ok++;
    expect(true, isTrue);
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('至少一个平台可用', () {
    // ignore: avoid_print
    print('可用平台数: $ok/2');
    expect(ok, greaterThan(0));
  });
}