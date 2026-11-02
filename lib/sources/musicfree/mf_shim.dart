/// MusicFree 插件 → lx 协议 的 JS 适配层（纯 JS，注入到同一个 QuickJS 宿主）。
///
/// 原理：MusicFree 插件是 CommonJS 模块，`module.exports` 暴露
/// `search/getMediaSource/getLyric/getAlbumInfo...`；lx 脚本则是事件模型
/// （`lx.on('request')` 返回 `musicUrl`）。
/// 本适配层在沙箱内置 `require/module/exports/env`，把插件加载进来后用
/// lx 的 `inited` + `request` 事件桥接到插件方法，于是**同一套宿主代码**
/// 可以同时服务两种协议。
class MusicFreeShim {
  MusicFreeShim._();

  /// 注入到 QuickJS 的引导代码（在插件源码之前执行）。
  /// 依赖宿主已注入的 globalThis.lx（含 utils.crypto / buffer）。
  static const String bootstrap = r'''
// ---------- CommonJS 运行时（最小实现）----------
globalThis.__mfModules = {};
globalThis.__mfCache = {};

// axios 垫片：走 lx.request（宿主 Dio），返回 {data,status,headers,config}
globalThis.__mfAxios = function (config) {
  config = config || {};
  var method = (config.method || 'GET').toUpperCase();
  var url = config.url || '';
  var params = config.params || {};
  var qs = [];
  for (var k in params) {
    if (params[k] === undefined || params[k] === null) continue;
    qs.push(encodeURIComponent(k) + '=' + encodeURIComponent(params[k]));
  }
  if (qs.length) url += (url.indexOf('?') >= 0 ? '&' : '?') + qs.join('&');
  var body = config.data;
  if (body && typeof body === 'object' && !config.__raw) {
    try { body = JSON.stringify(body); } catch (e) {}
  }
  return new Promise(function (resolve, reject) {
    var headers = config.headers || {};
    lx.request(url, {
      method: method,
      headers: headers,
      body: body,
      timeout: config.timeout || 15000,
    }, function (err, resp) {
      if (err) { return reject(new Error(String(err))); }
      var text = resp && resp.body;
      var data = text;
      var ct = '';
      try {
        var hh = (resp && resp.headers) || {};
        for (var hk in hh) { if (hk.toLowerCase() === 'content-type') ct = String(hh[hk]); }
      } catch (e) {}
      if (/json/i.test(ct) || (typeof text === 'string' && /^\s*[\{\[]/.test(text))) {
        try { data = JSON.parse(text); } catch (e) {}
      }
      resolve({
        data: data, status: (resp && resp.status) || 200,
        headers: (resp && resp.headers) || {}, config: config,
      });
    });
  });
};
globalThis.__mfAxios.get = function (url, config) {
  return globalThis.__mfAxios(Object.assign({}, config || {}, { url: url, method: 'GET' }));
};
globalThis.__mfAxios.post = function (url, data, config) {
  return globalThis.__mfAxios(Object.assign({}, config || {}, { url: url, data: data, method: 'POST' }));
};
['put', 'delete', 'head', 'patch'].forEach(function (m) {
  globalThis.__mfAxios[m] = function (url, config) {
    return globalThis.__mfAxios(Object.assign({}, config || {}, { url: url, method: m.toUpperCase() }));
  };
});
globalThis.__mfAxios.create = function (cfg) {
  var base = (cfg && cfg.baseURL) || '';
  var inst = function (c) { return globalThis.__mfAxios(Object.assign({}, cfg || {}, c || {}, { url: base + ((c || {}).url || '') })); };
  inst.get = function (u, c) { return globalThis.__mfAxios(Object.assign({}, cfg || {}, c || {}, { url: base + u, method: 'GET' })); };
  inst.post = function (u, d, c) { return globalThis.__mfAxios(Object.assign({}, cfg || {}, c || {}, { url: base + u, data: d, method: 'POST' })); };
  return inst;
};
globalThis.__mfAxios.defaults = { headers: { common: {} } };

// crypto-js 最小垫片（插件常用的几个 API）
globalThis.__mfCryptoJs = (function () {
  function utf8Bytes(s) { return lx.utils.buffer.from(s, 'utf8'); }
  function words(bytes) {
    var w = [], i;
    for (i = 0; i < bytes.length * 8; i += 8) {
      w[i >> 5] |= (bytes[i / 8] & 0xff) << (24 - i % 32);
    }
    return w;
  }
  function bytesOfWords(w) {
    var b = [], i;
    for (i = 0; i < w.length * 32; i += 8) {
      b.push((w[i >> 5] >>> (24 - i % 32)) & 0xff);
    }
    return b;
  }
  var MD5 = {
    // 直接复用宿主的 md5（hex），再用 word 形式暴露
    hash: function (s) { return lx.utils.crypto.md5(String(s)); },
  };
  var AES = {
    encrypt: function (msg, key, cfg) {
      var k = cryptoKeyBytes(key), iv = cfg && cfg.iv ? cryptoKeyBytes(cfg.iv) : [];
      var mode = 'aes-' + (cfg && cfg.mode ? cfg.mode : '128') + '-cbc';
      var mbytes = (msg && typeof msg === 'object' && msg.__bytes) ? msg.__bytes : utf8Bytes(String(msg));
      var out = lx.utils.crypto.aesEncrypt(mbytes, mode, k, iv);
      return { toString: function () { return lx.utils.buffer.bufToString(out, 'base64'); } };
    },
    decrypt: function (cipher, key, cfg) {
      var k = cryptoKeyBytes(key), iv = cfg && cfg.iv ? cryptoKeyBytes(cfg.iv) : [];
      var mode = 'aes-' + (cfg && cfg.mode ? cfg.mode : '128') + '-cbc';
      var bytes = lx.utils.buffer.from(String(cipher), 'base64');
      var out = lx.utils.crypto.aesDecrypt(bytes, mode, k, iv);
      return { toString: function (enc) { return lx.utils.buffer.bufToString(out, enc || 'utf8'); } };
    },
  };
  function cryptoKeyBytes(key) {
    if (key && typeof key === 'object') {
      if (key.__bytes) return key.__bytes.slice(0, key.sigBytes || key.__bytes.length);
      if (key.words) return bytesOfWords(key.words).slice(0, key.sigBytes || 16);
    }
    return utf8Bytes(String(key));
  }
  function enc(s) {
    var b = utf8Bytes(String(s));
    return {
      toString: function () { return String(s); },
      words: words(b),
      sigBytes: b.length,
      __isWordArray: true,
      __bytes: b,
    };
  }
  return {
    MD5: function (s) { return enc(MD5.hash(s)); },
    HmacMD5: function (s) { return enc(MD5.hash(String(s))); },
    enc: {
      Utf8: {
        stringify: function (w) { return w && w.__bytes ? lx.utils.buffer.bufToString(w.__bytes, 'utf8') : String(w); },
        parse: function (s) { return enc(s); },
      },
      Base64: {
        stringify: function (w) { return w && w.__isWordArray ? lx.utils.buffer.bufToString(bytesOfWords(w.words).slice(0, w.sigBytes), 'base64') : String(w); },
        parse: function (s) { var b = lx.utils.buffer.from(String(s), 'base64'); return { words: words(b), sigBytes: b.length, __isWordArray: true }; },
      },
      Hex: {
        stringify: function (w) { return w && w.__isWordArray ? lx.utils.buffer.bufToString(bytesOfWords(w.words).slice(0, w.sigBytes), 'hex') : String(w); },
        parse: function (s) { var b = lx.utils.buffer.from(String(s), 'hex'); return { words: words(b), sigBytes: b.length, __isWordArray: true }; },
      },
      Latin1: {
        stringify: function (s) { return String(s); },
        parse: function (s) { return enc(s); },
      },
    },
    AES: AES,
    mode: { CBC: 'cbc', ECB: 'ecb' },
    pad: { Pkcs7: { pad: function () {}, unpad: function () {} } },
    lib: { WordArray: { create: function (w, n) { return { words: w || [], sigBytes: n || 0, __isWordArray: true }; } } },
  };
})();

// he 最小垫片
globalThis.__mfHe = {
  decode: function (s) {
    return String(s)
      .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&apos;/g, "'")
      .replace(/&#(\d+);/g, function (_, d) { return String.fromCharCode(parseInt(d, 10)); })
      .replace(/&#x([0-9a-f]+);/gi, function (_, h) { return String.fromCharCode(parseInt(h, 16)); });
  },
  encode: function (s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  },
  escape: function (s) { return globalThis.__mfHe.encode(s); },
};

// qs 最小垫片
globalThis.__mfQs = {
  stringify: function (obj) {
    var out = [];
    for (var k in obj) {
      var v = obj[k];
      if (v === undefined || v === null) continue;
      out.push(encodeURIComponent(k) + '=' + encodeURIComponent(Array.isArray(v) ? v.join(',') : String(v)));
    }
    return out.join('&');
  },
  parse: function (s) {
    var out = {};
    String(s || '').split('&').forEach(function (kv) {
      if (!kv) return;
      var i = kv.indexOf('=');
      var k = decodeURIComponent(i < 0 ? kv : kv.slice(0, i));
      out[k] = i < 0 ? '' : decodeURIComponent(kv.slice(i + 1));
    });
    return out;
  },
};

// dayjs 最小垫片
globalThis.__mfDayjs = function (d) {
  var t = d ? new Date(d) : new Date();
  var pad = function (n) { return (n < 10 ? '0' : '') + n; };
  return {
    year: function () { return t.getFullYear(); },
    month: function () { return t.getMonth() + 1; },
    date: function () { return t.getDate(); },
    valueOf: function () { return t.getTime(); },
    format: function (f) {
      return String(f || 'YYYY-MM-DD')
        .replace(/YYYY/g, t.getFullYear())
        .replace(/MM/g, pad(t.getMonth() + 1))
        .replace(/DD/g, pad(t.getDate()))
        .replace(/HH/g, pad(t.getHours()))
        .replace(/mm/g, pad(t.getMinutes()))
        .replace(/ss/g, pad(t.getSeconds()));
    },
    toDate: function () { return t; },
  };
};
globalThis.__mfDayjs.unix = function (s) { return globalThis.__mfDayjs(new Date(s * 1000)); };

// cheerio 垫片（插件用来解析 HTML 的部分常见用法）
globalThis.__mfCheerio = { load: function (html) { return globalThis.__mfCheerioApi(String(html)); } };
globalThis.__mfCheerioApi = function (html) {
  var pick = function (sel) {
    var m = String(sel).match(/^([a-zA-Z0-9]*)[.#]?([^ ]*)"?/);
    return { text: function () { return ''; }, attr: function () { return undefined; },
             find: function () { return pick(sel); }, each: function () {}, length: 0,
             html: function () { return ''; }, map: function () { return []; }, get: function () { return []; } };
  };
  return function (sel) { return pick(String(sel)); };
};
globalThis.__mfCheerio.load = globalThis.__mfCheerio.load;

// @react-native-cookies/cookies 垫片
globalThis.__mfCookies = {
  get: function () { return Promise.resolve({}); },
  set: function () { return Promise.resolve(); },
  clearAll: function () { return Promise.resolve(); },
  flush: function () { return Promise.resolve(); },
};

// ---------- require / module / exports ----------
function __mfSelfDefault(mod) { if (mod && !mod.default) mod.default = mod; return mod; }
globalThis.__mfAxios = __mfSelfDefault(globalThis.__mfAxios);
globalThis.__mfCryptoJs = __mfSelfDefault(globalThis.__mfCryptoJs);
globalThis.__mfHe = __mfSelfDefault(globalThis.__mfHe);
globalThis.__mfQs = __mfSelfDefault(globalThis.__mfQs);
globalThis.__mfDayjs = __mfSelfDefault(globalThis.__mfDayjs);
globalThis.__mfCheerio = __mfSelfDefault(globalThis.__mfCheerio);

globalThis.__mfRequire = function (name) {
  var n = String(name);
  if (n === 'axios') return globalThis.__mfAxios;
  if (n === 'crypto-js') return globalThis.__mfCryptoJs;
  if (n === 'he') return globalThis.__mfHe;
  if (n === 'qs') return globalThis.__mfQs;
  if (n === 'dayjs') return globalThis.__mfDayjs;
  if (n === 'cheerio') return globalThis.__mfCheerio;
  if (n === '@react-native-cookies/cookies') return globalThis.__mfCookies;
  if (n === 'big-integer' || n === 'bigint') {
    return function (v) {
      return {
        toString: function () { return String(v); },
        add: function (o) { return globalThis.__mfRequire('big-integer')(String(Number(v) + Number(o))); },
        multiply: function (o) { return globalThis.__mfRequire('big-integer')(String(Number(v) * Number(o))); },
      };
    };
  }
  if (n === 'webdav') return {};
  if (globalThis.__mfModules[n]) return globalThis.__mfModules[n];
  throw new Error('未实现的模块: ' + n);
};

// env（MusicFree 用户变量机制）
globalThis.env = globalThis.env || {
  getUserVariables: function () { return globalThis.__mfUserVariables || {}; },
  getUserVariable: function (k) { return (globalThis.__mfUserVariables || {})[k]; },
  os: 'android', version: '0.5.0', lang: 'zh-CN',
};

// ---------- 加载 MusicFree 插件 ----------
globalThis.__mfLoadPlugin = function (code, platformHint) {
  var module = { exports: {} };
  var exports = module.exports;
  var fn = new Function('module', 'exports', 'require', 'env', 'console', code);
  fn(module, exports, globalThis.__mfRequire, globalThis.env, console);
  var plugin = module.exports;
  // Parcel/ESM 产物：方法挂在 default 上（__esModule）。仅在顶层缺方法时才取 default。
  if (plugin && typeof plugin === 'object' && plugin.default &&
      typeof plugin.search !== 'function') {
    var d = plugin.default;
    if (d && typeof d === 'object') {
      var merged = Object.assign({}, plugin);
      Object.keys(d).forEach(function (k) {
        if (k !== 'default') merged[k] = d[k];
      });
      if (typeof merged.search !== 'function' && typeof d.search === 'function') {
        merged.search = d.search;
      }
      plugin = merged;
    }
  }
  globalThis.__mfPlugin = plugin;
  return {
    platform: plugin.platform || platformHint || 'MusicFree',
    version: String(plugin.version || ''),
    author: String(plugin.author || ''),
    hasSearch: typeof plugin.search === 'function',
    hasMedia: typeof plugin.getMediaSource === 'function',
    hasLyric: typeof plugin.getLyric === 'function',
    supportedSearchType: plugin.supportedSearchType || ['music'],
  };
};

// ---------- 插件方法 → lx 事件 ----------
globalThis.__mfPickMusic = function (r) {
  if (Array.isArray(r)) return r;
  if (r && Array.isArray(r.data)) return r.data;
  return [];
};

globalThis.__mfSearch = function (text, page) {
  var p = globalThis.__mfPlugin;
  if (!p || typeof p.search !== 'function') return Promise.resolve([]);
  var types = p.supportedSearchType || ['music'];
  var type = types.indexOf('music') >= 0 ? 'music' : types[0];
  return Promise.resolve(p.search(text, page || 1, type)).then(globalThis.__mfPickMusic).catch(function (e) {
    return [];
  });
};

globalThis.__mfMediaUrl = function (musicInfo, quality) {
  var p = globalThis.__mfPlugin;
  if (!p || typeof p.getMediaSource !== 'function') return Promise.reject(new Error('插件不支持取链'));
  return Promise.resolve(p.getMediaSource(musicInfo, quality || '128k')).then(function (r) {
    var u = typeof r === 'string' ? r : (r && r.url);
    if (!u) throw new Error('插件未返回播放地址');
    return u;
  });
};

globalThis.__mfLyric = function (musicInfo) {
  var p = globalThis.__mfPlugin;
  if (!p || typeof p.getLyric !== 'function') return Promise.resolve(null);
  return Promise.resolve(p.getLyric(musicInfo)).then(function (r) {
    if (!r) return null;
    return typeof r === 'string' ? r : (r.rawLrc || r.lyric || null);
  }).catch(function () { return null; });
};
''';
}