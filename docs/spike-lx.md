# M2 Spike 报告：flutter_js 能否执行真实 lx 音源脚本

**日期**：2026-10-29
**工程**：`workspace/spike_lx`（可丢弃的最小验证工程，不进产品仓库）
**结论**：**主路径有条件成立（60–90% 档）**——按 ADR-006 的纯 flutter_js 路线推进，附三项必做缓解（见 §6）

---

## 1. 环境

| 项 | 值 |
|---|---|
| Flutter / Dart | 3.47.8 stable / 3.13.7（puro env） |
| flutter_js | 0.8.7 |
| 引擎 | **JSC**（macOS 系统 JavaScriptCore，产品默认）+ **QuickJS**（QuickJsRuntime2 + 自编译 quickjs-c-bridge dylib，即 Win/Linux/Android 的产品引擎） |
| 宿主方式 | `flutter test`（Dart VM + FFI，`FLUTTER_TEST` 模式下 ffi.dart 走 `DynamicLibrary.process()`，预加载 dylib） |
| HTTP 桥 | dio 5.11.1；本地 127.0.0.1 确定性服务 + httpbin.org 外网真实请求 |
| 对照基准 | openssl（md5 / aes-128-cbc / base64） |

> 关键环境事实：macOS 无完整 Xcode（仅 CLT），`flutter run/build macos` 不可用。spike 改用 Dart VM 测试执行，**结论不受影响**（JS 引擎行为与宿主 GUI 无关）。QuickJS dylib 由 `abner/quickjs-c-bridge` 源码 + CLT clang 编译（3 处小补丁：CONFIG_VERSION 宏、frame_address/int 转换、NULL→0 返回值）。

---

## 2. 假设结论（H1–H8）

| # | 假设 | 结论 | 证据 |
|---|---|---|---|
| H1 | QuickJS 解析执行真实脚本 | **✓** | 脚本 A/B 全过；**333KB 重度混淆真实脚本（sixyin）解析执行成功** |
| H2 | request 桥 err/resp.body 语义 | **✓** | 本地确定性服务 + httpbin.org 外网请求均返回正确 URL |
| H3 | buffer polyfill 覆盖 | **✓**（补 2 处后） | from/bufToString/concat 全部经桥往返正确 |
| H4 | crypto 桥逐字节一致 | **✓** | md5 与 **aes-128-cbc/PKCS7 输出与 openssl 逐字节一致**（双引擎） |
| H5 | Promise 链正确 resolve | **✓** | async/await、嵌套 then、Promise.resolve 链探针 9/9 |
| H6 | 15s 超时可中断 | **⚠️ 不成立——同步 evaluate 无法中断** | `while(true)` 永久阻塞引擎；**必须 isolate 隔离**（宿主存活已验证） |
| H7 | 多实例并发 | **✓** | 双实例交叉读写无串台 |
| H8 | V8→QuickJS 语法差异 | **✓** | 9/9 探针含 `\<` 正则转义、可选链、空值合并 |

---

## 3. 真实脚本验证（3 个，pdone/lx-music-source 10.4k★）

| 脚本 | 大小 | 解析执行 | inited | musicUrl 动作 | 归类 |
|---|---|---|---|---|---|
| huibq | 2.7KB | ✓ | ✓（5 源） | **上游 503**（onrender 免费部署宕机） | 宿主链路 ✓ / 上游不可用 |
| helloworld | 21KB | ✓ | ✓（6 源） | **脚本级多 API 聚合**：`resolve-url:不支持128k`（语义响应）+ `mobi.s:超时` | 宿主链路 ✓ / 上游部分可用 |
| sixyin（六音） | 333KB 重度混淆 | **✓** | ✗ 8s 未达 | 强制 dispatch → no handler | **API 面缺失**（初始化依赖更多 lx API，待定位） |

**载荷结构实测**（M2 直接采用）：lx 事件载荷为 `{ source, action, info: { type: '128k', musicInfo: { songmid, hash, id, name, singer, ... } } }`——`info.type` 是音质字段，`info.musicInfo` 是完整歌曲对象，与早期假设的扁平 `{musicId, quality}` 结构不同。

---

## 4. 通过率与判定

- 合成脚本（A/B）：**2/2 全过**（双引擎，含加密对拍）
- 真实脚本（3 个）：**0/3 动作级语义全过**——但**全部到达或证明可到达上游**，失败归类：上游 503/超时/不支持（2 个，非宿主问题）+ API 面缺失（1 个）
- 机制层（H1–H8）：8 项中 7 项全过、1 项（H6）以隔离方案解决

**判定：有条件成立（60–90% 档）**。脚本执行、桥接、HTTP、加密、Promise、多实例全部可用；瓶颈是 ① 真实脚本需要的**完整 lx API 面**（六音初始化卡死即为证据）② 上游源可用性（与宿主无关，由健康度机制处理）。

---

## 5. M2 直接受益的坑与解法（照抄清单）

1. **通道回调传的是已解码 Dart 对象**（Map/List），不是 JSON 字符串——handler 按 `dynamic` 收
2. **同步桥返回值**：注册具名 `Object? Function(dynamic)` 赋给 `void Function(dynamic)` 参数，JS 侧 `sendMessage()` 同步拿到 Dart 返回值
3. **QuickJS 微任务必须显式驱动**：每次 Dart→JS 往返后调 `rt.executePendingJob()`；JSC 无此要求
4. **aesEncrypt 必须返回 buffer（字节数组）**而非 hex 字符串——对齐 Node Buffer 语义，脚本会自己 `bufToString`
5. **console 群组方法必须 polyfill**：真实脚本用 `console.group`（flutter_js 只内置 log/info/error/warn）
6. **死循环不可中断** → RuntimeHost 采用 isolate 池执行脚本调用（设计文档 §11 的"超时丢弃但保留实例"在同步阻塞下不成立，需修正）
7. **事件载荷**：`info.type` + `info.musicInfo` 结构

---

## 6. 后续行动（按 60–90% 档规定）

1. **能力位降级**：失败的源标 `broken` 并提示（ADR-008 既有设计，落地）
2. **不兼容清单**：六音类混淆脚本初始化依赖定位（优先补齐其用到的 API；用 `lx` 对象打点确认触达面）
3. **优先补高频 API**：console 群组（已补）；下一批按真实脚本扫描频率补 `utils.crypto` 其余模式（rsa/ des）、`utils.zlib`、`buffer` 全编码
4. **RuntimeHost 修订**：isolate 池 + 每调用超时（H6 结论），设计文档 §11 第 4 行同步修正
5. **补充验证**：Windows/Linux/Android 平台上的 QuickJS 行为（本 dylib 为 macOS 构建；引擎 C 源相同，预期一致）；上游 503 环境恢复后的 huibq 复测

---

## 7. 复现方法

```bash
# 编译 QuickJS dylib（CLT 即可，无需 Xcode）
git clone --depth 1 https://github.com/abner/quickjs-c-bridge /tmp/qcb
cd /tmp/qcb/cxx
clang -include inttypes.h -DCONFIG_VERSION='"spike"' -c -O2 -I quickjs -o /tmp/qjs.o quickjs/quickjs.c
clang -c -O2 -I quickjs -o /tmp/lre.o quickjs/libregexp.c     # 同法编译 libregexp/libunicode/cutils/libbf
clang++ -c -O2 -std=c++17 -I quickjs -o /tmp/bridge.o libfastdev_quickjs_runtime.cpp
clang++ -dynamiclib -o libquickjs_c_bridge.dylib /tmp/qjs.o /tmp/lre.o ... # 链接
cp libquickjs_c_bridge.dylib <工程>/test/native/

# 运行 spike
cd spike_lx && flutter test        # FLUTTER_TEST 模式自动预加载
```

真实脚本仅存 `/tmp/lx_scripts/`（huibq/helloworld/sixyin），不提交仓库。
