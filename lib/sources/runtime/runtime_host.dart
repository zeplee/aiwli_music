import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto_md5;
import 'package:dio/dio.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/padded_block_cipher/padded_block_cipher_impl.dart';
import 'package:pointycastle/paddings/pkcs7.dart';

import '../../core/services/http_client.dart';
import '../../core/services/logger.dart';

/// lx 桥结果。
class LxActionResult {
  const LxActionResult({required this.ok, this.result, this.error});
  final bool ok;
  final Object? result;
  final String? error;
}

/// lx 运行时（spike 验证版转正）：注入 globalThis.lx，串行调度，超时重建。
/// 已知约束（spike H6）：同步 evaluate 无法中断死循环 → 超时后整个实例废弃重建。
class LxRuntime {
  LxRuntime(this.sourceId, this.script, {Dio? dio}) : _dio = dio ?? Http.create() {
    _createEngine();
    _inject();
    _registerChannels();
  }

  final String sourceId;
  final String script;
  final Dio _dio;

  JavascriptRuntime? _rt;
  Completer<Map<Object?, Object?>?>? _resultCompleter;
  final Completer<Map<Object?, Object?>?> initedCompleter = Completer();
  final List<StreamSubscription<dynamic>> _dioSubs = [];

  Map<Object?, Object?>? get inited => _initedPayload;
  Map<Object?, Object?>? _initedPayload;

  void _createEngine() {
    _rt = getJavascriptRuntime(xhr: false); // Android→QuickJS；macOS/iOS→JSC
  }

  // ---------- JS 注入 ----------
  static const String _jsBridge = r'''
globalThis.__lxEvents = {};
globalThis.__lxInited = null;
globalThis.__lxReqSeq = 0;
globalThis.lx = {
  version: '2.0.0',
  env: 'mobile',
  EVENT_NAMES: { inited: 'inited', request: 'request', updateAlert: 'updateAlert' },
  on: (name, fn) => { globalThis.__lxEvents[name] = fn; },
  send: (name, data) => {
    if (name === 'inited') globalThis.__lxInited = data;
    try { sendMessage('LxBridge', JSON.stringify({ name: name, data: data })); } catch (e) {}
  },
  request: (url, opts, cb) => {
    globalThis.__lxReqSeq += 1;
    const id = globalThis.__lxReqSeq;
    globalThis['__lxHttpCb' + id] = cb;
    sendMessage('LxHttp', JSON.stringify({ id: id, url: url, opts: opts || {} }));
    return () => {};
  },
  utils: {
    buffer: {
      from: (input, enc) => {
        const e = enc || 'utf8';
        if (typeof input === 'string') {
          return sendMessage('LxBuffer', JSON.stringify({ op: 'fromString', input: input, enc: e }));
        }
        return Array.from(input);
      },
      bufToString: (buf, enc) => {
        const e = enc || 'utf8';
        const bytes = (buf && typeof buf === 'object') ? Array.from(buf) : null;
        return sendMessage('LxBuffer', JSON.stringify({ op: 'toString', bytes: bytes, raw: (typeof buf === 'string' ? buf : null), enc: e }));
      },
      concat: (list) => { let out = []; for (const b of list) out = out.concat(Array.from(b)); return out; },
    },
    crypto: {
      md5: (s) => sendMessage('LxCrypto', JSON.stringify({ op: 'md5', input: String(s) })),
      aesEncrypt: (data, alg, key, iv) => sendMessage('LxCrypto', JSON.stringify({
        op: 'aesEncrypt', data: Array.from(data), alg: String(alg),
        key: Array.from(key), iv: Array.from(iv) })),
      aesDecrypt: (data, alg, key, iv) => sendMessage('LxCrypto', JSON.stringify({
        op: 'aesDecrypt', data: Array.from(data), alg: String(alg),
        key: Array.from(key), iv: Array.from(iv) })),
      rsaEncrypt: (k, s) => sendMessage('LxCrypto', JSON.stringify({ op: 'rsaEncrypt', key: String(k), input: String(s) })),
      randomBytes: (n) => sendMessage('LxCrypto', JSON.stringify({ op: 'randomBytes', n: n })),
    },
    zlib: {
      deflate: () => sendMessage('LxCrypto', JSON.stringify({ op: 'stub', fn: 'deflate' })),
      inflate: () => sendMessage('LxCrypto', JSON.stringify({ op: 'stub', fn: 'inflate' })),
    },
  },
};
globalThis.__lxHttpDone = (id, err, resp) => {
  const cb = globalThis['__lxHttpCb' + id];
  delete globalThis['__lxHttpCb' + id];
  if (cb) cb(err, resp);
};
globalThis.__lxDispatch = (payload) => {
  const h = globalThis.__lxEvents[payload.action === 'musicUrl' ? 'request' : 'request'];
  if (!h) { sendMessage('LxResult', JSON.stringify({ ok: false, error: 'no handler' })); return; }
  Promise.resolve().then(() => h(payload)).then(
    (r) => sendMessage('LxResult', JSON.stringify({ ok: true, result: (r === undefined ? null : r) })),
    (e) => sendMessage('LxResult', JSON.stringify({ ok: false, error: String(e) })));
};
if (typeof console !== 'undefined') {
  var __noop = function() {};
  ['group','groupEnd','groupCollapsed','debug','table','dir','time','timeEnd','trace','assert','count','countReset','clear'].forEach(function(k){
    if (typeof console[k] === 'undefined') console[k] = __noop;
  });
}
''';

  void _inject() {
    final rt = _rt!;
    // console 扩展补齐（spike 实测真实脚本需要 group 等）
    rt.evaluate(r'''
      if (typeof console !== 'undefined') {
        var __lxNoop = function() {};
        ['group','groupEnd','groupCollapsed','debug','table','dir','time','timeEnd','trace','assert','count','countReset','clear'].forEach(function(k){
          if (typeof console[k] === 'undefined') console[k] = __lxNoop;
        });
      }
    ''');
    rt.evaluate(_jsBridge);
    rt.evaluate(script);
    AppLog.i('LxRuntime', '[$sourceId] 脚本已注入 (${script.length} chars)');
  }

  // ---------- 通道 ----------
  void _registerChannels() {
    final rt = _rt!;
    rt.setupBridge('LxBridge', _onLxBridge);
    rt.setupBridge('LxHttp', _onLxHttp);
    Object? bufFn(dynamic args) => _buffer(_asMap(args));
    Object? cryptoFn(dynamic args) => _crypto(_asMap(args));
    rt.setupBridge('LxBuffer', bufFn);
    rt.setupBridge('LxCrypto', cryptoFn);
    rt.setupBridge('LxResult', _onResult);
  }

  static Map<dynamic, dynamic> _asMap(dynamic args) => args is String
      ? jsonDecode(args) as Map<dynamic, dynamic>
      : args as Map<dynamic, dynamic>;

  void _onLxBridge(dynamic args) {
    final m = _asMap(args);
    if (m['name'] == 'inited' && !initedCompleter.isCompleted) {
      _initedPayload = (m['data'] as Map?)?.cast<Object?, Object?>();
      initedCompleter.complete(_initedPayload);
    }
  }

  void _onLxHttp(dynamic args) {
    final m = _asMap(args);
    unawaited(_http(m['id'] as int, m['url'] as String,
        (m['opts'] as Map?)?.cast<String, dynamic>() ?? {}));
  }

  void _onResult(dynamic args) {
    final r = _asMap(args);
    _resultCompleter?.complete(r);
    _resultCompleter = null;
  }

  Future<void> _http(int id, String url, Map<dynamic, dynamic> opts) async {
    try {
      final resp = await _dio.request<Object>(
        url,
        options: Options(
          method: (opts['method'] as String?) ?? 'GET',
          headers:
              ((opts['headers'] as Map?) ?? const {}).cast<String, dynamic>(),
          responseType: ResponseType.plain,
          // 音源上游常有自签/过期证书问题，debug 期放宽由上层决定
          validateStatus: (code) => code != null && code < 500,
        ),
        data: opts['body'],
        onReceiveProgress: null,
      );
      final body = resp.data is String ? resp.data as String : jsonEncode(resp.data);
      _eval('__lxHttpDone($id, null, ${jsonEncode({
            'body': body,
            'status': resp.statusCode,
          })})');
    } catch (e) {
      _eval('__lxHttpDone($id, ${jsonEncode(e.toString())}, null)');
    }
  }

  Object? _buffer(Map<dynamic, dynamic> m) {
    switch (m['op'] as String) {
      case 'fromString':
        final input = m['input'] as String;
        final enc = m['enc'] as String;
        if (enc == 'utf8') return input.codeUnits;
        if (enc == 'base64') return base64Decode(input);
        if (enc == 'hex') {
          final out = <int>[];
          for (var i = 0; i + 1 < input.length; i += 2) {
            out.add(int.parse(input.substring(i, i + 2), radix: 16));
          }
          return out;
        }
        return input.codeUnits;
      case 'toString':
        final enc = m['enc'] as String;
        if (m['raw'] is String && enc == 'utf8') return m['raw'];
        final bytes = (m['bytes'] as List?)?.cast<int>() ?? const <int>[];
        if (enc == 'base64') return base64Encode(bytes);
        if (enc == 'hex') {
          return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        }
        if (enc == 'utf8') return String.fromCharCodes(bytes);
        return null;
    }
    return null;
  }

  Object? _crypto(Map<dynamic, dynamic> m) {
    switch (m['op'] as String) {
      case 'md5':
        return crypto_md5.md5.convert(latin1.encode(m['input'] as String)).toString();
      case 'aesEncrypt':
        return _aes(m, true);
      case 'aesDecrypt':
        return _aes(m, false);
      case 'randomBytes':
        final n = (m['n'] as num).toInt();
        return List<int>.generate(n, (i) => (i * 37 + 11) % 256);
      case 'stub':
        return 'STUB';
    }
    return null;
  }

  Object _aes(Map<dynamic, dynamic> m, bool enc) {
    final data = Uint8List.fromList((m['data'] as List).cast<int>());
    final key = Uint8List.fromList((m['key'] as List).cast<int>());
    final iv = Uint8List.fromList((m['iv'] as List).cast<int>());
    final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()));
    cipher.init(
        enc,
        PaddedBlockCipherParameters(
            ParametersWithIV<KeyParameter>(KeyParameter(key), iv), null));
    final out = cipher.process(data);
    if (enc) return out.toList(); // buffer 语义
    return String.fromCharCodes(out);
  }

  void _eval(String code) {
    try {
      _rt?.evaluate(code);
    } catch (e) {
      AppLog.w('LxRuntime', '[$sourceId] eval 失败: $e');
    }
  }

  void drainOnce() {
    try {
      _rt?.executePendingJob();
    } catch (_) {}
    try {
      _rt?.evaluate('0');
    } catch (_) {}
  }

  /// 触发 action（musicUrl / lyric / pic），等待 Promise settle。
  Future<LxActionResult> dispatch(
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_resultCompleter != null) {
      // 串行保护：上一个调用未完成时排队等待
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    final fresh = Completer<Map<Object?, Object?>?>();
    _resultCompleter = fresh;
    _eval('__lxDispatch(${jsonEncode(payload)})');
    final timer = Timer.periodic(const Duration(milliseconds: 10), (_) => drainOnce());
    try {
      final r = await fresh.future.timeout(timeout);
      return LxActionResult(
        ok: r?['ok'] == true,
        result: r?['result'],
        error: r?['error'] as String?,
      );
    } on TimeoutException {
      // H6 结论：同步引擎无法中断 → 废弃实例并重建
      AppLog.w('LxRuntime', '[$sourceId] dispatch 超时，重建实例');
      await _recreate();
      return LxActionResult(ok: false, error: 'timeout: 脚本调用超时');
    } finally {
      timer.cancel();
      _resultCompleter = null;
    }
  }

  Future<void> _recreate() async {
    try {
      _rt?.dispose();
    } catch (_) {}
    _initedPayload = null;
    _createEngine();
    _inject();
    _registerChannels();
    // 重新等待 inited（大部分脚本注入即 init）
    try {
      await initedFuture(timeout: const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<Map<Object?, Object?>?> initedFuture({Duration timeout = const Duration(seconds: 8)}) {
    return initedCompleter.future.timeout(timeout, onTimeout: () => null);
  }

  Future<void> dispose() async {
    for (final s in _dioSubs) {
      await s.cancel();
    }
    try {
      _rt?.dispose();
    } catch (_) {}
  }
}

