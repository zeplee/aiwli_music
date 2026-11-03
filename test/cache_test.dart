import 'package:flutter_test/flutter_test.dart';

/// 验证缓存语义（与 PlaybackResolver 内的实现一致）。
void main() {
  test('缓存 TTL 与容量控制', () {
    final cache = <String, ({String url, DateTime expireAt})>{};
    const ttl = Duration(minutes: 10);

    void put(String k, String url) {
      cache[k] = (url: url, expireAt: DateTime.now().add(ttl));
      if (cache.length > 200) cache.remove(cache.keys.first);
    }

    String? get(String k) {
      final hit = cache[k];
      if (hit == null) return null;
      if (DateTime.now().isAfter(hit.expireAt)) {
        cache.remove(k);
        return null;
      }
      return hit.url;
    }

    put('kw|1', 'https://a');
    expect(get('kw|1'), 'https://a', reason: '未过期应命中');
    expect(get('kw|2'), isNull, reason: '不存在应未命中');

    // 过期
    cache['kw|3'] = (url: 'https://c', expireAt: DateTime.now().subtract(const Duration(seconds: 1)));
    expect(get('kw|3'), isNull, reason: '过期应失效');
    expect(cache.containsKey('kw|3'), isFalse, reason: '过期应被清理');

    // 容量
    for (var i = 0; i < 250; i++) {
      put('k$i', 'u$i');
    }
    expect(cache.length, lessThanOrEqualTo(200), reason: '容量上限 200');
  });

  test('同平台同曲二次取链应命中缓存（模拟）', () async {
    final cache = <String, String>{};
    var networkCalls = 0;

    Future<String> resolve(String src, String id) async {
      final key = '$src|$id';
      final hit = cache[key];
      if (hit != null) return hit;
      networkCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      const url = 'https://cdn/x.mp3';
      cache[key] = url;
      return url;
    }

    await resolve('kw', '1');
    await resolve('kw', '1'); // 第二次应命中
    await resolve('kw', '2'); // 不同曲目

    expect(networkCalls, 2, reason: '首次+新曲=2 次网络，重复曲目应命中缓存');
  });
}
