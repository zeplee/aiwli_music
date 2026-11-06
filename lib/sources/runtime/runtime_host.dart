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
import '../musicfree/mf_shim.dart';

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
  LxRuntime(this.sourceId, this.script, {Dio? dio, this.musicFree = false})
      // 脚本取链走的是第三方免费接口，经常挂死不返回。
      // 默认 15s 会让「失败源」拖慢整体——收到 5s，快速失败交给上层换源。
      : _dio = dio ?? Http.create(timeout: const Duration(seconds: 5)) {
    _createEngine();
    // 顺序至关重要：必须先注册 bridge 通道，再注入脚本。
    // lx 脚本在 evaluate 期间就会同步调用 lx.send('inited', ...)；
    // 若通道未注册，该消息被丢弃（日志 "No channel LxBridge registered"），
    // initedCompleter 永不完成 → 每个脚本白等满 8s 超时。
    _registerChannels();
    _inject();
  }

  final String sourceId;
  final String script;

  /// true 表示 script 是 MusicFree 插件（CommonJS），走 __mfLoadPlugin 包装。
  final bool musicFree;
  final Dio _dio;

  JavascriptRuntime? _rt;
  Completer<Map<Object?, Object?>?>? _resultCompleter;
  Completer<Map<Object?, Object?>?> initedCompleter =
      Completer<Map<Object?, Object?>?>();

  /// 重建实例时重置 inited 等待（否则复用已完成的 completer，
  /// 新实例的 inited 事件无处安放）。
  void _resetInited() {
    if (initedCompleter.isCompleted) {
      initedCompleter = Completer<Map<Object?, Object?>?>();
    }
  }
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
  currentScriptInfo: { name: '', version: '', author: '', description: '', homepage: '' },
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
    // lx.currentScriptInfo：部分混淆脚本在初始化时读取自身信息做更新检查，
    // 缺失会静默 TypeError（实测野草/野花/小熊猫）。用 @name/@version/@author 填充。
    // （内联解析避免 runtime → lx_source 反向依赖）
    String name = '', version = '', author = '';
    final head = script.length > 4000 ? script.substring(0, 4000) : script;
    for (final line in head.split('\n')) {
      final nameM = RegExp(r'@name\s+(.+)').firstMatch(line);
      final verM = RegExp(r'@version\s+(.+)').firstMatch(line);
      final authorM = RegExp(r'@author\s+(.+)').firstMatch(line);
      if (nameM != null) name = nameM.group(1)!.trim();
      if (verM != null) version = verM.group(1)!.trim();
      if (authorM != null) author = authorM.group(1)!.trim();
    }
    rt.evaluate('globalThis.lx.currentScriptInfo = '
        '{ name: ${jsonEncode(name)}, version: ${jsonEncode(version)}, '
        'author: ${jsonEncode(author)}, description: "", homepage: "" };');
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
    if (musicFree) {
      // MusicFree 插件：注入 CommonJS 垫片 → 加载插件 → 伪造 inited 事件
      rt.evaluate(MusicFreeShim.bootstrap);
      final meta = rt.evaluate('__mfLoadPlugin(${jsonEncode(script)});');
      final m = meta.stringResult;
      // MF 插件原本只声明自己那个 `mf-xxx` 标识，导致它对**内置榜单**
      // 的曲目（sourceId=kw/tx/wy/kg/mg）完全不参与取链：
      // `supportsPlatform('kw')` 永远 false。
      //
      // 但 MF 插件的取链签名是 `getMediaSource(musicItem, quality)`——
      // 根本不吃平台参数，插件自己就是单一平台的实现。所以它天然能处理
      // 对应标准平台的曲目，只是声明没对上。
      //
      // 这里额外补一个标准平台 key（由 id/名称推断），让内置榜单能借用。
      final platform = guessMusicFreePlatform(sourceId, script);
      final srcs = <String, Map<String, Object?>>{
        sourceId: {
          'name': sourceId,
          'actions': ['musicUrl', 'musicSearch'],
        },
      };
      if (platform != null) {
        srcs[platform] = {
          'name': '$sourceId (=> $platform)',
          'actions': ['musicUrl'],
        };
      }
      _initedPayload = {
        'sources': srcs,
        'musicFreeMeta': m,
      };
      if (!initedCompleter.isCompleted) initedCompleter.complete(_initedPayload);
      AppLog.i('LxRuntime', '[$sourceId] MusicFree 插件已加载: $m');
    } else {
      rt.evaluate(script);
      AppLog.i('LxRuntime', '[$sourceId] 脚本已注入 (${script.length} chars)');
    }
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
    rt.setupBridge('LxBigInt', (args) => _bigInt(_asMap(args)));
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

  /// MusicFree 插件 big-integer 垫片的后端：Dart 原生 BigInt。
  /// Android 打包的 QuickJS 未启用 BigInt，JS 侧无法自算，逐次过桥。
  Object? _bigInt(Map<dynamic, dynamic> m) {
    final op = '${m['op'] ?? ''}';
    final radix = (m['aradix'] as num?)?.toInt() ?? 10;
    final aS = '${m['a'] ?? ''}';
    final bS = '${m['b'] ?? ''}';
    final cS = '${m['c'] ?? ''}';
    BigInt pa() => BigInt.parse(aS.isEmpty ? '0' : aS, radix: radix);
    BigInt pb() => BigInt.parse(bS.isEmpty ? '0' : bS, radix: radix);
    try {
      switch (op) {
        case 'add':
          return (pa() + pb()).toRadixString(radix);
        case 'minus':
          return (pa() - pb()).toRadixString(radix);
        case 'multiply':
          return (pa() * pb()).toRadixString(radix);
        case 'divide':
          return (pa() ~/ pb()).toRadixString(radix);
        case 'mod':
          // big-integer 语义：余数符号跟随被除数（Dart remainder 同）
          return pa().remainder(pb()).toRadixString(radix);
        case 'modPow':
          final c = BigInt.parse(cS.isEmpty ? '1' : cS, radix: radix);
          return pa().modPow(pb(), c).toRadixString(radix);
        case 'cmp':
          final x = pa();
          final y = pb();
          return x < y ? '-1' : x > y ? '1' : '0';
        case 'convert':
          final toR = (m['c'] as num?)?.toInt() ?? 10;
          return BigInt.parse(aS.isEmpty ? '0' : aS, radix: radix)
              .toRadixString(toR);
      }
    } catch (e) {
      AppLog.w('LxBigInt', 'op=$op a=$aS b=$bS err=$e');
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
    // 串行保护：上一个调用未完成时等它结束（80ms 猜测会导致
    // 旧请求仍在飞时新请求就开始注入，两次注入互相顶掉 completer）。
    final previous = _resultCompleter;
    if (previous != null) {
      try {
        await previous.future.timeout(const Duration(seconds: 16));
      } catch (_) {/* 上一个失败也要等完，避免并发注入 */}
    }
    final fresh = Completer<Map<Object?, Object?>?>();
    _resultCompleter = fresh;
    _eval(musicFree ? _mfDispatchExpr(payload) : '__lxDispatch(${jsonEncode(payload)})');
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

  /// MusicFree 插件的 dispatch：把 lx 请求映射到插件方法。
  /// musicSearch → __mfSearch(text) → songs[]
  /// musicUrl    → __mfMediaUrl(musicInfo) → url
  /// lyric       → __mfLyric(musicInfo) → lrc
  String _mfDispatchExpr(Map<String, dynamic> p) {
    final action = p['action'] as String? ?? '';
    final info = (p['info'] as Map?)?.cast<Object?, Object?>() ?? const {};
    switch (action) {
      case 'musicSearch':
        final text = (info['text'] ?? info['word'] ?? '').toString();
        final page = (info['page'] as num?)?.toInt() ?? 1;
        return '''__mfSearch(${jsonEncode(text)}, $page).then(
          function (list) { sendMessage('LxResult', JSON.stringify({ ok: true, result: list })); },
          function (e) { sendMessage('LxResult', JSON.stringify({ ok: false, error: String(e) })); });''';
      case 'musicUrl':
        final mi = (info['musicInfo'] as Map?)?.cast<Object?, Object?>() ?? const {};
        return '''__mfMediaUrl(${jsonEncode(mi)}, ${jsonEncode('128k')}).then(
          function (u) { sendMessage('LxResult', JSON.stringify({ ok: true, result: u })); },
          function (e) { sendMessage('LxResult', JSON.stringify({ ok: false, error: String(e) })); });''';
      case 'lyric':
        final mi = (info['musicInfo'] as Map?)?.cast<Object?, Object?>() ?? const {};
        return '''__mfLyric(${jsonEncode(mi)}).then(
          function (l) { sendMessage('LxResult', JSON.stringify({ ok: true, result: l })); },
          function (e) { sendMessage('LxResult', JSON.stringify({ ok: false, error: String(e) })); });''';
    }
    return "sendMessage('LxResult', JSON.stringify({ ok: false, error: '不支持的 action: $action' }));";
  }

  Future<void> _recreate() async {
    try {
      _rt?.dispose();
    } catch (_) {}
    _initedPayload = null;
    _resetInited();
    _createEngine();
    _registerChannels();
    _inject();
    // 重新等待 inited（大部分脚本注入即 init）
    try {
      await initedFuture(timeout: const Duration(seconds: 5));
    } catch (_) {}
  }

  /// 取消在途的 dispatch：完成其 completer（失败态）并重建实例。
  ///
  /// 并发取链场景：某个源已胜出，其余源的请求还挂在串行队列里，
  /// 若任其自然超时会触发 6s 等待 + 639KB 重建级联。立即复位最划算。
  void cancelPending() {
    final c = _resultCompleter;
    _resultCompleter = null;
    c?.complete(<Object?, Object?>{'ok': false, 'error': 'cancelled'});
    unawaited(_recreate());
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



/// 从 MusicFree 插件的 id / 源码推断它服务的标准平台。
///
/// 背景：MF 插件的 `getMediaSource(musicItem, quality)` 不接受平台参数，
/// 一个插件就是一个平台的实现。它的 id 形如 `mf-酷我-念心音源`，
/// 但宿主只把它当成平台标识，导致内置榜单（sourceId=kw）借不到它。
///
/// 判定策略（从严到宽，命中即返回）：
///   1. id/名称里出现明确的中文或英文平台词
///   2. 源码里出现该平台专属的接口域名（比名称更可靠）
/// 识别不出就返回 null——宁可不映射，也不要把网易插件当酷我用。
String? guessMusicFreePlatform(String id, String script) {
  final key = id.toLowerCase();

  // 平台专属域名：比名称可靠，优先用它
  const domainHints = <String, List<String>>{
    'kw': ['kuwo.cn', 'kwapi'],
    'wy': ['music.163.com', '126.net'],
    'tx': ['y.qq.com', 'gtimg.cn'],
    'kg': ['kugou.com'],
    'mg': ['migu.cn', 'nf.migu'],
  };
  for (final e in domainHints.entries) {
    for (final d in e.value) {
      if (script.contains(d)) return e.key;
    }
  }

  // 名称/ID 关键词（中英都覆盖；顺序重要：qq 与 wy 不能同时命中）
  const nameHints = <String, List<String>>{
    'kw': ['酷我', 'kuwo'],
    'wy': ['网易', 'netease', '163'],
    'tx': ['qq', 'qq音乐', 'tencent'],
    'kg': ['酷狗', 'kugou'],
    'mg': ['咪咕', 'migu'],
  };
  for (final e in nameHints.entries) {
    for (final k in e.value) {
      if (key.contains(k)) return e.key;
    }
  }
  return null;
}
