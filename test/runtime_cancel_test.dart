import 'package:flutter_test/flutter_test.dart';
import 'package:aiwli_music/sources/runtime/runtime_host.dart';

void main() {
  test('cancelInFlight 在没有在途请求时是安全的空操作', () async {
    final rt = LxRuntime('test', '');
    expect(() => rt.cancelInFlight(), returnsNormally);
    await rt.dispose();
  });

  test('cancelInFlight 后立即 dispatch 不会等满串行保护的 16s', () async {
    final rt = LxRuntime('test2', '');
    // 空脚本的 dispatch 会因为无桥接结果而超时（这里用 200ms 短超时），
    // 关键断言是：cancelInFlight 之后第二次 dispatch 能立即开始（<1s），
    // 而不是被串行保护阻塞 16s。
    final first = rt.dispatch(
      {'action': 'musicUrl', 'info': {}},
      timeout: const Duration(milliseconds: 200),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    rt.cancelInFlight();
    await first;

    final sw = Stopwatch()..start();
    await rt.dispatch(
      {'action': 'musicUrl', 'info': {}},
      timeout: const Duration(milliseconds: 200),
    );
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(1000),
        reason: '第二次 dispatch 不该被串行队列阻塞 16s');
    await rt.dispose();
  });
}
