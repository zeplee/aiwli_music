# M2 Spike 执行手册：验证 flutter_js 能否跑通真实 lx 音源脚本

**版本** v1.0 · 2026-10-27
**性质**：**前置验证实验**，不是产品代码。
**目的**：用 3 天内回答一个二元问题——**QuickJS 能否执行真实世界的 lx 音源脚本**。
**输出**：`docs/spike-lx.md`（实验报告）+ 一个可丢弃的最小工程。
**决策影响**：决定主路径（纯 flutter_js）还是双轨（Android 原生 + 桌面 flutter_js），见 ADR-006。

> **不要跳过这一步。** 后续 M2 有 2 周工作量，全部建立在"QuickJS 可跑"这个假设上。假设错了，两周白费。

---

## 1. 要验证的假设清单

按风险从高到低排序，**每一条都要有明确结论**：

| # | 假设 | 失败后果 | 验证方式 |
|---|---|---|---|
| H1 | QuickJS 能解析并执行真实 lx 脚本（含 ES6+、正则、模板字符串） | 整个方案不成立 | 执行 3 个真实脚本，观察 `inited` |
| H2 | `lx.request` 桥能正确回调（含 `err`/`resp.body` 语义） | 无法取到任何 URL | 桥接后发起真实 HTTP 请求 |
| H3 | `lx.utils.buffer` polyfill 能覆盖真实脚本用法 | 大量脚本失败 | 统计脚本中 buffer 的 API 使用，逐个补 |
| H4 | `lx.utils.crypto`（md5/aes/rsa）桥可用 | 需要签名的平台全部失败 | 对已知算法做对照测试 |
| H5 | Promise 链在 QuickJS 中正确 resolve（含嵌套 then、async/await） | 返回空/挂死 | 用带 async 的脚本验证 |
| H6 | 15s 超时能中断死循环脚本且不影响宿主 | UI 卡死 | 故意写死循环脚本 |
| H7 | 多实例并发不串台 | 数据错乱 | 同时加载 2 个脚本交叉调用 |
| H8 | `\<` `\>` 转义修复足够（是否还有其他 V8/QuickJS 差异） | 部分脚本语法错误 | 收集失败脚本的错误类型归类 |

---

## 2. 环境准备

```bash
# 最小工程，不要用产品工程
flutter create --platforms=android,macos,windows,linux,ios spike_lx
cd spike_lx
```

`pubspec.yaml` 只需三项：
```yaml
dependencies:
  flutter: {sdk: flutter}
  flutter_js: 0.8.7
  dio: ^5.11.1
```

> 桌面端验证优先在 **macOS**（开发机）与 **Windows**（如可访问）做。Android 用于对照。

---

## 3. 测试脚本集（必须准备 3 个，覆盖不同复杂度）

### 3.1 脚本 A：最小可行（验证 H1/H2/H5）

```js
/**
 * @name Spike-最小
 * @version 1.0.0
 */
const { EVENT_NAMES, request, on, send } = globalThis.lx

const get = (url) => new Promise((resolve, reject) => {
  request(url, { method: 'GET' }, (err, resp) => {
    if (err) return reject(err)
    resolve(resp.body)
  })
})

on(EVENT_NAMES.request, ({ source, action, info }) => {
  if (action !== 'musicUrl') return Promise.resolve('')
  return get('https://httpbin.org/json').then(body => {
    const data = JSON.parse(body)
    return 'https://example.com/' + (data.slideshow ? 'ok' : 'no') + '.mp3'
  })
})

send(EVENT_NAMES.inited, {
  openDevTools: false,
  sources: {
    kw: { name: 'SpikeKW', type: 'music', actions: ['musicUrl'], qualitys: ['128k', '320k'] },
  },
})
```

**预期**：`inited` 事件到达；调用 `on` 后返回一个 URL 字符串。

### 3.2 脚本 B：buffer + crypto（验证 H3/H4）

**要求**：从社区取一个**真实在用的**、且明确使用了 `lx.utils.buffer` 与签名的脚本。
若取不到，用下面这个等效替代（模拟真实签名流程）：

```js
/**
 * @name Spike-Buffer-Crypto
 * @version 1.0.0
 */
const { EVENT_NAMES, request, on, send, utils } = globalThis.lx

function sign(payload) {
  const buf = utils.buffer.from(payload, 'utf8')
  const b64 = utils.buffer.bufToString(buf, 'base64')
  const ts = Date.now().toString()
  const md5 = utils.crypto.md5(b64 + ts)
  const aes = utils.crypto.aesEncrypt(
    utils.buffer.from(md5, 'utf8'),
    'aes-128-cbc',
    utils.buffer.from('0123456789abcdef', 'utf8'),
    utils.buffer.from('abcdef0123456789', 'utf8'),
  )
  return {
    hex: utils.buffer.bufToString(aes, 'hex'),
    b64,
    md5,
  }
}

on(EVENT_NAMES.request, ({ action }) => {
  if (action !== 'musicUrl') return Promise.resolve('')
  return new Promise(resolve => {
    const s = sign('songmid=123&quality=320')
    request('https://httpbin.org/anything', {
      method: 'POST',
      headers: { 'X-Sign': s.hex, 'X-MD5': s.md5 },
      body: JSON.stringify({ b64: s.b64 }),
    }, (err, resp) => {
      if (err) return resolve('')
      resolve('https://example.com/signed.mp3?h=' + s.hex)
    })
  })
})

send(EVENT_NAMES.inited, {
  openDevTools: false,
  sources: {
    kw: { name: 'SpikeB64', type: 'music', actions: ['musicUrl'], qualitys: ['320k'] },
  },
})
```

**预期**：`buffer.from/bufToString`、`md5`、`aesEncrypt` 全部不报错；`hex` 与 `b64` 输出**与 Node 端计算结果一致**（用真实 lx-music-desktop 或 node 脚本对照）。

> **H4 的关键**：算法输出必须**逐字节一致**——签名算法错一位，平台就返回 403。这是最容易"看起来跑通但实际全错"的地方，务必对照验证。

### 3.3 脚本 C：真实第三方脚本（验证 H1/H2/H3/H5 综合）

从社区取 **1-3 个真实流行源的 lx 脚本**（如六音音源等公开流传的脚本）。

**选择标准**：
- 优先选明确使用 `crypto` / `buffer` / 复杂 Promise 链的
- 优先选仍在被使用的（不是几年前的）
- 至少一个带有 `form`/`formData` 或自定义 header 的请求

> **不要**把这些脚本提交进产品仓库（版权与合规原因），仅作本地测试，报告里记录"脚本名 + 通过/失败 + 错误类型"，不记录内容。

---

## 4. 桥接实现要点（spike 版，够用即可）

```dart
// 只实现 spike 需要的三个桥
void injectLxBridge(JavascriptRuntime rt, {required String scriptInfo}) {
  // 1) 注入 globalThis.lx
  rt.evaluate('''
    globalThis.lx = {
      version: '2.0.0',
      env: 'desktop',
      EVENT_NAMES: { inited: 'inited', request: 'request', updateAlert: 'updateAlert' },
      _handlers: {},
      _send: (name, data) => sendMessage('LxBridge', [name, data]),
      on: function(name, fn) { this._handlers[name] = fn },
      send: function(name, data) { this._send(name, data) },
      request: function(url, opts, cb) {
        sendMessage('LxHttp', [url, opts])
        globalThis._httpCb = cb
      },
      utils: { /* buffer / crypto / zlib 占位，逐步补 */ },
    };
  ''');

  // 2) HTTP 桥
  rt.onMessage('LxHttp', (args) async {
    final url = args[0] as String;
    final opts = (args[1] as Map?) ?? {};
    try {
      final resp = await dio.request(url,
        options: Options(method: opts['method'] ?? 'GET', headers: opts['headers']));
      // 回写到 JS 的 callback
      rt.evaluate('globalThis._httpCb(null, ${jsonEncode({'body': resp.data})})');
      return null;
    } catch (e) {
      rt.evaluate('globalThis._httpCb(${jsonEncode(e.toString())}, null)');
      return null;
    }
  });

  // 3) 接收 inited / updateAlert
  rt.onMessage('LxBridge', (args) {
    /* 记录事件，inited 表示初始化成功 */
    return null;
  });
}
```

> **注意**：上面是**教学示意，不是可直接编译的实现**。真实实现需处理：JSON 序列化边界、Promise 返回语义、回调只能被调用一次、dio 的 form/formData 映射、取消函数（`lx.request` 返回值）。
> **不要**在 spike 阶段追求代码优雅——目标是拿到结论，代码验收后就丢弃。

---

## 5. 执行步骤（3 天计划）

### Day 1：跑通最小闭环（H1/H2/H5）
1. 建工程、装依赖
2. 实现注入 + HTTP 桥 + inited 监听
3. 跑**脚本 A**，确认：
   - `inited` 收到，能读到 `sources` 定义
   - 触发 `on(request)` 后返回非空 URL
4. **在 macOS 与 Android 各跑一次**，记录差异

### Day 2：补 buffer/crypto（H3/H4）
1. 统计脚本 B/C 中 `utils.` 的全部 API 调用（用正则扫脚本源码即可）
2. 按调用频率从高到低实现（先 `buffer.from` / `bufToString` / `md5`）
3. 对每个实现做**对照测试**：与 Node 计算结果逐字节比对
4. 跑脚本 B，确认签名输出正确
5. 跑脚本 C，记录第一个失败点

### Day 3：健壮性 + 结论（H6/H7/H8）
1. 死循环脚本测试：15s 超时是否生效、宿主是否存活
2. 双实例并发交叉调用测试
3. 汇总所有失败脚本的**错误类型归类**（语法错误 / API 缺失 / 结果不符 / 超时）
4. 做决策判定（§6）

---

## 6. 判定标准（硬性阈值）

先定义"通过"：

> **脚本"通过" = 能收到 `inited` + 能对它声明的每个 action 返回**语义正确**的结果（不是"没报错"）**

对真实脚本集（≥3 个，建议 5 个）统计：

| 通过率 | 结论 | 后续行动 |
|---|---|---|
| ≥ 90% | **主路径成立** | 按 M2 原计划推进（纯 flutter_js） |
| 60% – 90% | **有条件成立** | 推进，但必须：① 实现能力位降级（失败的源标 `broken` 并提示）；② 记录已知不兼容清单；③ 优先补高频失败 API |
| 30% – 60% | **触发 D1（双轨）** | Android 保留原生 QuickJS（抄栖弦 MIT 代码），桌面用 flutter_js；两套都归到 `MusicSource` 接口后 |
| < 30% | **主路径不成立** | 重新评估：改为 Android+原生 QuickJS 为主、桌面用 any-listen 式"外部脚本进程"方案，或缩小桌面音源能力预期 |

**不可接受的"假通过"**：
- 只验证 `inited` 到达就算通过 ← 错误，必须验证 action 返回正确
- 签名算法"跑通不报错"但没和 Node 对拍 ← 错误，会线上 403
- 用简化过的自造脚本代替真实脚本 ← 错误，自造脚本不会暴露真实坑

---

## 7. 实验报告模板（`docs/spike-lx.md`）

```markdown
# M2 Spike 报告

## 环境
- Flutter / Dart 版本：
- flutter_js 版本：0.8.7
- 测试平台：macOS xx / Windows xx / Android xx

## 结果总表
| 脚本 | 平台 | inited | musicUrl | 备注 |
|---|---|---|---|---|
| A 最小 | macOS | ✅ | ✅ | — |
| B buffer+crypto | macOS | ✅ | ✅ | aes 输出与 Node 一致 |
| C 真实#1 | macOS | ❌ | — | SyntaxError: xxx（第 N 行） |
| ... | | | | |

## 通过率
X / Y = Z%

## 失败归类
| 类别 | 数量 | 典型错误 | 可解性判断 |
|---|---|---|---|
| 语法差异 | 2 | `\<` 转义 / 其他 | 可预处理 |
| API 缺失 | 1 | `buffer.writeUInt32BE` | 需补 polyfill |
| 结果不符 | 0 | — | — |
| 超时/挂死 | 0 | — | — |

## H1–H8 逐条结论
（逐条给出 通过/失败 + 证据）

## 决策
按 §6 判定：通过率 Z% → 结论 = 主路径 / 有条件 / D1 双轨 / 重估

## 遗留问题
- （列出尚未验证但已知存在的风险）
```

---

## 8. 常见陷阱（执行前必读）

| 陷阱 | 说明 |
|---|---|
| 忽略 `resp.body` 类型 | lx 的 `request` 回调里 `body` 可能是字符串或已解析对象，取决于平台实现。真实脚本常直接 `JSON.parse(resp.body)`，桥必须返回**字符串**，不能返回已解析 Map |
| 回调被多次调用 | `on(request)` 的 Promise 只能 resolve 一次；桥实现若重复回写会导致 `already resolved` |
| AES 模式字符串映射 | lx 用 `'aes-128-cbc'` 这类 Node 风格字符串，pointycastle 需映射到对应 `PaddedBlockCipher`，且 **padding 必须 PKCS7** |
| `randomBytes` 语义 | 返回的是 Buffer 不是字符串，长度按字节 |
| `bufToString` 的 format | 支持 `utf8` / `hex` / `base64`；`fast_gbk` 用于中文场景 |
| 时间戳/时区 | 签名常含 `Date.now()`，QuickJS 需正确支持 `Date` |
| 中文编码 | lx 脚本里可能出现 GBK 编码的响应体，需 `charset` 转换 |
| macOS 沙盒 | spike 工程若开沙盒，需 entitlements 放行网络 |

---

## 9. Spike 之后

报告完成后：
1. 把结论回填到施工文档 §13 的决策点 D1
2. 若结论是"主路径"，把 spike 中验证过的桥接代码**重写**进 `lib/sources/runtime/`（不要直接搬 spike 代码，它没有隔离/超时/串行设计）
3. 若结论是"D1 双轨"，先更新 ADR-006 的后果章节，再调整 M2 计划
4. spike 工程可删除，但**报告与失败脚本清单保留**（后续回归测试要用）