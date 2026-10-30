# Aiwli Music 架构决策记录（ADR）

**版本** v1.2 · 2026-10-29
**读者**：接手本项目的 AI 或人类工程师。
**用途**：记录**已经做出**、**不希望在实施过程中被反复挑战**的架构决策。每条 ADR 包含背景、选项、决策、理由、后果。若某条决策的前提假设发生变化（如 pub 包状态变化），应在本文档追加"ADR-xxx-superseded"记录，**而不是直接改写历史**。

> 施工细节见 [`aiwli-music-design.md`](./aiwli-music-design.md)。本文档只回答"为什么这样定"。

---

## ADR-001 · 从零新建工程，不做改造

**状态**：已采纳 · 2026-10-27

**背景**
存在一个高度相关的参考实现 CyShineMusic（栖弦），Android-only，用 Flutter 实现，MIT 许可，已实现 lx 音源脚本加载（原生 QuickJS）、BASS 播放、逐字歌词、Material 3 主题。

**选项**
- A. 以栖弦为基座改造，补桌面平台实现
- B. 从零新建，按需复制栖弦的 MIT 代码片段

**决策**：**B**

**理由**
1. 栖弦的跨平台障碍集中在三处：`bass_player`（Android 原生 BASS 方法通道）、`music_source_runtime`（Android 原生 QuickJS 桥）、`music_home_widget`（Android 桌面小组件）。三者都只注册 android 平台（pubspec 中 `platforms: { android: ... }`）。
2. 要跨平台就必须拆掉这三个插件——**拆除本身约 1-2 周**，拆完剩下的与"从零新建 + 复制业务层"所得完全一致。
3. 栖弦把音频焦点、播放控制、媒体广播三职责混在 `PlayerAudioHandler` 一个类里，这个结构在任何平台都需要重排，不存在"保留原样"的选项。
4. MIT 许可允许复制，因此最有价值的部分（播放状态机、逐字歌词、业务 UI）可以直接搬，成本不高于改造。

**后果**
- 正面：架构干净，无历史技术债；可自由选择技术栈。
- 负面：需要重新搭骨架；需要人工甄别哪些栖弦代码可复用（不是整包拷贝）。
- 缓解：主文档 §12 明确列出栖弦哪几个文件可以直接抄。

---

## ADR-002 · 全平台统一播放引擎（media_kit），不做多引擎

**状态**：已采纳 · 2026-10-27

**背景**
需要覆盖 Android/iOS/macOS/Windows/Linux 五端播放。候选：media_kit（libmpv 统一引擎）、just_audio（移动端原生 + 桌面靠第三方桥）、自研 BASS 桥。

**选项**
- A. media_kit 五端统一
- B. just_audio（移动端原生）+ just_audio_media_kit（桌面桥）
- C. 移动端 BASS/原生、桌面 media_kit 的多引擎方案

**决策**：**A**

**理由**
1. **just_audio 的桌面路线不成立**：它本身无 Windows/Linux 实现，必须依赖 `just_audio_media_kit`（Pato05）。该桥实测：GitHub **14★**、pub 最后发版 **2025-04（18 个月前）**、pub 标注 **unverified uploader**；且 README 自承 `shuffleOrder` 被忽略、gapless 需开实验性 `--prefetch-playlist`（"Use at your own risk"）、HTTP header "(untested)"。音乐播放器的三大刚需在桌面端全部踩在桥的短板上。
2. **桥的底层仍是 media_kit**——多垫一层却削减能力，不划算。
3. media_kit 实测 1.8k★、media-kit 组织维护、2026-08 仍有 push、pub 平台矩阵六端全绿；namida（6.7k★）、harmonoid（4.8k★）两个最成熟的 Flutter 音乐播放器生产使用。
4. 多引擎方案（选项 C）会让"播放行为"变成两份实现两套 bug，与"引擎统一"的工程目标冲突。

**后果**
- 正面：一份播放逻辑，五端行为一致；gapless/shuffle/header 全部原生支持；无 BASS 商用授权问题（libmpv 为 LGPL）。
- 负面：BASS 特有功能（WASAPI 独占输出、BASS_FX 高级均衡器）不可用；media_kit 的 issue 数量较多（364 open）。
- 缓解：`AudioEngine` 抽象保留接口位，若日后确需 WASAPI 独占，可加 `BassEngine` 实现（参考 ZeroBit-Player，GPL 只读），不影响主路径。

---

## ADR-003 · 三种职责分离：引擎 / 焦点策略 / 媒体广播

**状态**：已采纳 · 2026-10-27

**背景**
参考实现（栖弦）在 `PlayerAudioHandler` 中同时承担：播放引擎控制、音频焦点与中断响应（约 300 行）、媒体会话广播（通知栏/锁屏）。该结构在 Android 上工作良好，但无法在桌面复用。

**选项**
- A. 保持单类（照抄参考实现）
- B. 拆为三个接口：`AudioEngine`、`AudioFocusPolicy`、`MediaSessionCast`

**决策**：**B**

**理由**
1. 三者的**平台差异性完全不同**：引擎无差异（media_kit 统一）；音频焦点差异极大（手机有、桌面无此概念）；媒体广播协议不同（通知栏 / SMTC / MPRIS）。
2. 平台差异必须能被"编译路径隔离"——桌面上不应执行任何 `audio_session` 代码。单类结构做不到这一点，只能靠运行时 `if` 判断，容易漏判导致桌面崩溃。
3. 拆分后 `PlayerCore` 成为纯逻辑（队列/状态机/世代守卫），可被单元测试用 `FakeAudioEngine` 完整覆盖——这是单类结构无法实现的。

**后果**
- 正面：桌面路径天然干净；核心逻辑可测；新增平台只需实现 Cast，不动核心。
- 负面：多两层间接，代码量略增（约 +300 行胶水）。
- 必须遵守：`PlayerCore` 不得 import 任何平台插件；`AudioFocusPolicy` 的桌面实现必须是空实现（`Stream.empty()`），不得为"统一接口"而在桌面调用 audio_session。

---

## ADR-004 · 以 MusicFree 插件为主音源生态，lx 脚本为兼容层

**状态**：已采纳 · 2026-10-27

**背景**
两种可选音源协议，能力面差异极大（详见施工文档 §4.3/§4.5）。

**事实（已核实 lx 官方规范）**
- **lx 源脚本**：非 local 源**只有 `musicUrl`** 一个能力。搜索、榜单、歌单导入由 App 内置 API 提供，**与脚本无关**。
- **MusicFree 插件**：模块导出式，一个插件自带某平台的搜索、详情、歌词、封面、歌单导入全套能力，且支持用户配置变量。

**决策**：**MusicFree 插件为主生态，lx 脚本为兼容层，lx 内置官方 API 移植列为可选里程碑 M6**

**理由**
1. 若以 lx 为主，用户"装个源脚本"后仍然搜不到歌——必须由 App 内置 5 个平台的搜索/榜单 API 才能形成闭环，那是额外的一大块移植工作。
2. MusicFree 插件装完即全功能，产品体验闭环更短。
3. lx 官方自身已从窄脚本转向宽扩展形态（any-listen 的 extension 机制），说明窄协议是历史形态。

**后果**
- 正面：首期即可用插件覆盖全功能；lx 兼容层的实现量很小（只桥 musicUrl）。
- 负面：lx 脚本用户体验不完整（能播不能搜），需在 UI 明确提示；若要补齐需做 M6。
- 必须遵守：`SourceManifest.capabilities` 必须驱动 UI 降级，不得假设所有源都能搜索（详见 ADR-008）。

---

## ADR-005 · 不为 any-listen 单独实现适配器

**状态**：已采纳 · 2026-10-27

**背景**
any-listen 是 lx 官方的新项目（4.6k★），采用"扩展"机制，看起来像第三种音源形态。需要判断是否要为其开发第三套适配器。

**决策**：**不单独实现，架构预留位置即可**

**证据**
`any-listen/any-listen-extension-lx-api-source-loader` 的 `config.ts`：

```ts
contributes: {
  resource: [
    { id: 'kw', resource: ['musicUrl'] },
    { id: 'tx', resource: ['musicUrl'] },
    { id: 'wy', resource: ['musicUrl'] },
    { id: 'kg', resource: ['musicUrl'] },
    { id: 'mg', resource: ['musicUrl'] },
  ],
},
buildConfig: { isIsolateMode: true },
grant: ['internet', 'isolate_context'],
```

资源声明与 lx 规范"非 local 源 actions 固定为 `['musicUrl']`"完全一致；`isIsolateMode` + `isolate_context` 表明它是 **lx 脚本的隔离进程容器**，不是新协议。

**后果**
- 正面：省掉一套适配器开发。
- 负面：若 any-listen 未来扩展出宽能力协议，需要新增第三个 adapter。
- 缓解：`MusicSource` 接口本身与协议无关，新增 adapter 不影响业务层。**触发条件**：当 any-listen 官方扩展出现 `search` 类 resource 声明时，重新评估本 ADR。

---

## ADR-006 · 音源脚本运行时用 flutter_js，接受其维护风险

**状态**：已采纳 · 2026-10-27 · **风险已登记**

> ✅ **2026-10-29 spike 验证完成**：主路径**有条件成立（60–90% 档）**——H1–H8 中 7 项全过、H6（超时中断）以 isolate 池方案解决；md5/aes 与 openssl 逐字节一致；333KB 混淆真实脚本可解析执行。证据与行动清单见 `spike_lx/docs/spike-lx.md`。

**背景**
需要在 Flutter 中执行不受信任的 JavaScript（lx 脚本与 MusicFree 插件）。候选：flutter_js、flutter_qjs、WebView、自建 QuickJS FFI 绑定。

**选项对比（实测）**
| 选项 | 平台 | 维护 | 判决 |
|---|---|---|---|
| flutter_js 0.8.7 | 五端（无 web） | 542★，单人（abner），最近提交 2026-01，81 open issues，2025-09→2026-01 有四个月空窗 | **采纳** |
| flutter_qjs 0.3.7 | 五端（名义） | 2022-05 停更，SDK 约束 `<3.0.0` | 否决 |
| WebView | 桌面生态分裂 | — | 否决（内存大、数据交换难） |
| 自建 QuickJS FFI | 五端 | 自研 | 备选（成本高） |

**决策**：**flutter_js**

**理由**
1. 唯一同时满足"五端 + 仍在维护 + 可直接用"的选项。
2. Android/Win/Linux 走 QuickJS，iOS/macOS 走 JSC——都是成熟引擎。
3. 已有工程（MusicWEP）验证过"Flutter + flutter_js 跑 MusicFree 插件"可行，其踩坑解法可直接照抄思路。

**后果**
- 正面：立刻可用；无需自研绑定。
- 负面：**单人维护**，遇 bug 可能需自修或 fork；QuickJS ≠ V8，部分脚本可能不兼容。
- **缓解（必须执行）**：
  1. 只在 `lib/sources/runtime/` 内 import flutter_js，其他层不感知——替换成本可控。
  2. M2 前置 spike 验证真实脚本兼容性（施工文档 §13）。
  3. 失败率 >30% 时启用双轨：Android 保留原生 QuickJS（栖弦 MIT 代码可抄），桌面用 flutter_js。

---

## ADR-007 · 不引入第二套音源运行时（不做多运行时并存）

**状态**：已采纳 · 2026-10-27

**背景**
考虑过"lx 用 flutter_js、MusicFree 用另一套运行时"或"不同平台用不同 JS 引擎"。

**决策**：**只保留一个 RuntimeHost，其内部按平台选择 QuickJS 或 JSC；两种协议共享同一套宿主设施**

**理由**
1. 两种协议的底层需求高度重合：都需要 HTTP 桥、crypto 桥、超时、串行、实例隔离、诊断日志。分两套会导致这些基础设施写两遍、bug 修两遍。
2. 差异只在**协议适配层**（lx 是事件收发、MusicFree 是方法导出），各约 200 行。
3. 平台差异（QuickJS vs JSC）已被 flutter_js 封装，RuntimeHost 只需一个 `createRuntime()` 分支。

**后果**
- 正面：基础设施单份维护；新增第三种协议只需加 adapter。
- 负面：适配器之间可能互相影响（如同一 runtime 池耗尽）。缓解：实例池上限 + 空闲回收。

---

## ADR-008 · 能力位驱动 UI 降级，不做"能力猜测"

**状态**：已采纳 · 2026-10-27

**背景**
不同源能力差异极大（lx 脚本只有 musicUrl；MusicFree 插件可能缺专辑搜索）。曾在方案中考虑"调用失败再降级"或"按源类型硬编码假设"。

**决策**：**以 `SourceManifest.capabilities` 为唯一事实来源，UI 与聚合器据此决定是否展示入口；实现方对未声明能力抛 `UnsupportedSourceCapability`**

**理由**
1. "调用失败再降级"会让用户看到一闪而过的错误，体验差且难以区分"能力缺失"与"网络故障"。
2. "按源类型假设"会在插件能力差异出现时立刻失效（例如某插件只支持搜歌不支持搜专辑）。
3. 能力位在源加载时（inited / inspect）即可确定，是零成本的静态信息。

**后果**
- 正面：UI 稳定、可预测；聚合器可以精确扇出。
- 负面：**适配器实现者必须准确填写能力位**——填错会导致 UI 隐藏了实际可用的功能。必须为每个适配器写能力位推导的单元测试。
- 必须遵守：不得因为"某源通常支持搜索"而在 manifest 中默认声明 `searchMusic`。

---

## ADR-009 · 桌面无音频焦点：空实现而非"模拟"

**状态**：已采纳 · 2026-10-27

**背景**
Windows/macOS/Linux 没有"音频焦点"概念（多应用同时出声是正常行为）。但为保持 `AudioFocusPolicy` 接口统一，存在"在桌面模拟一套焦点逻辑"的诱惑。

**决策**：**桌面实现为空操作（activate 直接返回 true，events 返回 `Stream.empty()`），不模拟任何焦点行为**

**理由**
1. 模拟焦点会在桌面制造"播放器互相抢占"的假问题，而这个能力在桌面根本不需要。
2. 空实现让桌面编译路径完全不触碰 `audio_session`，避免 `MissingPluginException`（该包确实不支持 Windows/Linux）。
3. 桌面需要的只是"单向广播"（把状态告诉系统），那是 `MediaSessionCast` 的职责，不是焦点。

**后果**
- 正面：桌面行为符合系统惯例；无插件异常。
- 负面：桌面端用户拔耳机不会自动暂停（多数桌面播放器也不这么做，属可接受）。
- 注意：`InterruptionCoordinator` 只应在移动端被注册；桌面注册它属于实现错误。

---

## ADR-010 · 数据层用 drift，不用手写 SQL 也不引入服务端

**状态**：已采纳 · 2026-10-27

**背景**
需要持久化歌单、播放历史、下载任务、源配置。候选：drift、sqflite、hive、json 文件、后端服务。

**决策**：**drift（SQLite）**

**理由**
1. 五端全覆盖（sqflite 的桌面支持需额外配置，hive 在复杂查询上弱）。
2. 类型安全 + 编译期校验 + 迁移框架完善，适合"表结构会演进"的项目。
3. 歌单/历史/下载需要关系查询（如"某歌单的所有曲目按 position 排序"），SQL 比 KV 更合适。

**后果**
- 正面：迁移可控；查询表达力强。
- 负面：需维护 schema 版本与迁移代码。**必须为每次结构变更写迁移测试**。
- 拒绝的替代：引入服务端存储（违背"本地优先、隐私"的产品定位）。

---

## ADR-011 · 首期不做 Web 端

**状态**：已采纳 · 2026-10-27

**背景**
Flutter 可编译到 Web。但音源脚本依赖 `flutter_js`，该包**平台声明不含 web**。

**决策**：**首期不做 Web 端**

**理由**
1. 没有 JS 运行时就无法执行 lx 脚本/MusicFree 插件，Web 端会退化成"只能播本地"的残缺应用。
2. 浏览器内执行第三方脚本还涉及 CORS、沙箱、安全策略等额外复杂度。
3. 若将来需要，可用"服务端跑脚本 + Web 拉结果"的方案（any-listen 的 Web 版就是这条路），但那是另一个架构，不在本期范围。

**后果**
- 正面：范围收敛，五端工作量可控。
- 负面：无 Web。
- 触发条件：若产品确需 Web，应新建 ADR 讨论"服务端音源代理"架构，而非强行塞入现有设计。

---

## ADR-012 · 原生依赖下沉边界：只在 pub 生态确实空白处写原生，Windows SMTC 用纯 Dart

**状态**：已采纳 · 2026-10-28（**修改 ADR-002 表格外的媒体广播实现，并撤销主文档 §1.3 的"smtc_windows 需 Rust"弱点**）

> ⚠️ **2026-10-29 修订**：本条决策 C 中「Windows SMTC 用 win32 自实现」部分已被 **ADR-013 取代**——当时漏查了 `audio_service_platform_interface` 的联邦生态，现成实现 `audio_service_win` 已存在（证据见 `dependency-evidence.md` §2.3）。本条的**下沉边界原则**与「Windows 构建链无需 rustup」成果**继续有效**。以下原文保留，未改动。

**背景**
同类项目 `zeplee/aiwli_git`（Flutter + Rust libgit2 单调度器）走的是"重 Rust、轻 Dart 依赖"路线：pubspec 仅 7 个依赖，Git 引擎全部下沉 Rust。该项目的构建代价在 README 中明确写出：

> Windows/Linux：`flutter build windows/linux --release`（**cargokit 现编 vendored libgit2/openssl，需 Rust + CMake**）

调研该选择是否出于必要，结论是**部分必要**：`git2dart`（Dart FFI 绑定 libgit2，2026-09 仍更新）确实存在且五端二进制齐备，但它只覆盖底层仓库操作，**块级暂存、cherry-pick 精细控制、冲突三方合并这些 UI 级语义**没有现成 Dart 实现——这部分是空白，所以下沉有理。换言之：**它不是"为架构而架构"，而是"填补生态空白"**。

但这个结论**不能外推到播放链路**。逐项核查（证据见 [`dependency-evidence.md`](./dependency-evidence.md)）后确认：playback 侧每一环都有成熟 pub 包，**没有一个需要 Rust**。

**选项**

- A. 跟随 aiwli_git，把播放与媒体集成也下沉 Rust 统一底座
- B. 全部走 pub 包，Windows SMTC 接受 `smtc_windows`（需 Rust 工具链）
- C. 全部走 pub 包，Windows SMTC 用 `win32`（纯 Dart FFI）自行实现

**决策**：**C**

**理由**

1. **A 是过度设计**：播放侧生态完整，`media_kit_libs_windows_audio` 的 `CMakeLists.txt` 实测为**从 GitHub Releases 下载预编译 libmpv 7z**（`mpv-dev-x86_64-20230924-git-652a1dd.7z`），只需 CMake，**不需要 Rust**。为一个已有预编译产物的能力重写 Rust 层，收益为负。aiwli_git 的两层技术栈代价（构建、调试、CI、发版各一套）不该被复制。
2. **B 引入了不必要的构建门槛**：实测 `smtc_windows@1.1.0` 的 pubspec 依赖 `flutter_rust_bridge ^2.11.1`；解包其 tar 确认**包内无任何预编译 `.dll`、含 `Cargo.toml` 与 `rust/` 目录**——即每个 Windows 构建机与 CI 都必须装 rustup 并现场编译。为一个"把歌名告诉系统任务栏"的能力付这个代价，不划算。
3. **C 技术上成立，且已验证底层齐备**：`win32@6.4.0` 是**纯 Dart**（依赖仅 `ffi`/`ffi_leak_tracker`/`meta`），解包确认它同时具备
   - COM 基础：`IUnknown`、`IClassFactory`、`CoCreateInstance`、`ole32` 测试用例
   - WinRT 激活：`lib/src/win32/api_ms_win_core_winrt_l1_1_0.g.dart` 提供 `RoGetActivationFactory<T extends IUnknown>(HSTRING, ...)`
   - 且已生成大量 COM 接口绑定（`iaudioclient`、`ishellitem`、`immdevice` 等），说明该生成链路可用

   缺的只是 SMTC 自身的接口声明，需要自己写 `ISystemMediaTransportControlsInterop` 等声明并通过 `RoGetActivationFactory` 激活。这是一次性投入，之后零构建负担。
4. **边界原则可复用**：不是"能不能写原生"，而是"**生态是否已经提供**"。提供了就用，空白才写。这条原则同时解释了为什么 aiwli_git 下沉有理、而播放链路不该下沉。

**后果**

- 正面：
  - Windows 构建链**不再需要 rustup**，CI 与本地环境只需 VS2022 + CMake（后者 media_kit 本来就要）
  - `pubspec.yaml` 保持纯 Dart/Flutter 依赖，无 `cargokit`、无 `rust_builder`
  - 五端构建环境差异缩小到"仅 VS2022 / Xcode / NDK"这些 Flutter 自带要求
- 负面：
  - 需自行编写 Windows SMTC 的 COM/WinRT 声明与调用（预估 300–500 行 Dart），并处理 `HSTRING`/`PROPVARIANT` 生命周期
  - 该实现无第三方维护，Windows SDK 版本变化时需自行跟进
- 缓解：
  - `MediaSessionCast` 接口保持不变（见 ADR-003），SMTC 只是其中一个实现；若纯 Dart 方案受阻，**可随时退回 `smtc_windows`**，代价仅是该平台构建机加 rustup，不影响其他四端
  - 建议把 SMTC 实现排在里程碑末段（M5 打磨期），它不阻塞播放主链路
- 明确不做：不把播放引擎、音源宿主、标签读写下沉原生——它们的 pub 包均成熟（证据见 `dependency-evidence.md`）

---

## ADR-013 · Windows SMTC 改用现成联邦实现 audio_service_win，不自己写

**状态**：已采纳 · 2026-10-29 · **取代 ADR-012 决策 C 中「win32 自实现 SMTC」部分**；ADR-012 的下沉边界原则与「Windows 构建链无需 rustup」成果继续有效

> ⚠️ **2026-10-29 追加修订**：本条的**实现选型（三件套 + fork audio_service_win）已被 [ADR-014](#adr-014--媒体控制层终选flutter_media_session--直驱-audio_service_mpris零-fork-零自研) 取代**——发起人确认两条硬要求（功能完善 + 尽量不自研 SDK）后，维护 fork 不再可接受。本条确立的原则（不自研 SMTC、seek 为必要功能、回退链思想）继续有效。以下原文保留，未改动。

**背景**
ADR-012 定下「win32 纯 Dart 自实现 SMTC」时，漏查了 `audio_service_platform_interface` 的联邦生态。按用户诉求「有全平台 pub 就用 pub、节省开发量」复核后确认现成方案已存在（证据见 `dependency-evidence.md` §2.3–2.5）：

- `audio_service_win@0.0.3`：pub 官方联邦标签 `implements-federated-plugin:audio_service_platform_interface`，C++/WinRT 调 SMTC，无 Cargo.toml（无 Rust），月下载 3.7k
- `flutter_media_session@3.0.9`：五端**缺 Linux**，Windows 端含 `TimelineProperties`（支持进度条）；若采用需为 Linux 另配 MPRIS，维护两套 API
- `audio_manager@1.0.0`：单包六端（150 赞），但**它是完整播放器**（Android MediaPlayer / Windows `Windows.Media.Playback` / Linux GStreamer），采用即替换 media_kit

**选项**

- A. `audio_service` + `audio_service_win` + `audio_service_mpris`（联邦三件套：一套 API 五端，播放引擎仍是 media_kit）
- B. 维持 ADR-012 的 win32 自实现
- C. `audio_manager` 全家桶（播放+媒体控制一包搞定，代价是换引擎）

**决策**：**A**

**理由**

1. **开发量等同"单包"**：联邦机制下业务层只写一个 `AudioHandler`，`audioHandler.play()` 五端同一行代码；三个包是平台实现而非三套业务，与硬约束 2（业务层零平台 import）一致。
2. **C 不可取**：audio_manager 的引擎按平台分裂（MediaPlayer / Windows.Media.Playback / GStreamer），gapless、HTTP header、shuffle 等行为无法保证跨端一致——这正是 ADR-002 否决多引擎的理由；且 namida/harmonoid 的成熟先例都在 media_kit 侧，audio_manager 无同等规模验证。
3. **相比 B 省实打实的开发量**：300–500 行自维护 COM/WinRT 代码不必写，SMTC 交互细节（DisplayUpdater、按钮回调生命周期）已被包作者踩过坑。
4. **接口不变即可替换**：`audio_service_win` 若缺能力，回退顺序：向上游提 PR → `smtc_windows`（仅该平台加 rustup）→ 恢复 ADR-012 自实现。业务代码一行不动。

**后果**

- 正面：Windows 构建链维持无 Rust（VS2022 + CMake）；五端一套 API；自维护原生代码为零。
- 负面：`audio_service_win` 仅 0.0.3 / 3 likes / 实现接口 6 方法（configure、setMediaItem、setState、setQueue、stopService 等），**任务栏进度条（TimelineProperties）未实现**；单人维护、迭代慢。
- 缓解：SMTC 排期在 M5，不阻塞播放主链路；缺口出现时按上述回退链处理。

**2026-10-29 追记（发起人确认「拖动进度为必要功能」后）**

规格已把 seek 定为媒体会话契约的一部分（主文档 `MediaSessionCast.commands` 含 seek），因此「系统界面拖进度」不是可选项。四端核实（见 `dependency-evidence.md` §2.6）：

- Android/iOS/macOS：audio_service 本体完整支持（通知栏/锁屏/控制中心进度条 + 拖动回调）
- Linux：audio_service_mpris 实现了标准 MPRIS `SetPosition` 方法并发出 `Seeked` 信号，双向完整
- Windows：audio_service_win 0.0.3 **缺 TimelineProperties**——唯一缺口

**补齐计划（按序）**：
1. **首选：fork/PR `audio_service_win` 补 TimelineProperties + SMTC PositionRequest 事件**。该插件仅 339 行 C++ + 117 行 Dart，预估补 ~100 行；保持零 Rust、保持联邦 API，补齐后回馈上游
2. 回退：Windows 平台叠加 `smtc_windows`（其 Rust 绑定已导出 `timeline.dart`，功能完整），仅该平台构建机加 rustup
3. 不可选项：砍掉系统层 seek（违背发起人确认的功能要求）

注意区分：**应用内进度条拖动（ui-spec §2.2）由 media_kit 引擎直接负责，五端本就完整**，本条只涉及系统媒体层。
- 明确不做：不为"一个包搞定"而更换播放引擎。

---

## ADR-014 · 媒体控制层终选：flutter_media_session + 直驱 audio_service_mpris，零 fork 零自研

**状态**：已采纳 · 2026-10-29 · **取代 ADR-013 的实现选型（三件套 + fork）**；ADR-013 确立的原则（不自研 SMTC、seek 为必要功能）与回退链思想继续有效

**背景**
发起人明确两条硬要求：① **功能完善**——要的功能都要实现（含系统层 seek，ADR-013 追记已确认）；② **尽量不要自己做 SDK**——维护 fork 也算自研。

`dependency-evidence.md` §2.7 已穷尽核查：不存在"零改动 + 单包 + 五端 seek"的现成方案，天花板两条（零 fork 路线 B / 生态成熟路线 A）。按要求②，A 的 fork 部分出局。

**决策**

- **`flutter_media_session ^3.0.9`**：覆盖 Android（Media3 前台服务 + 通知）/ iOS（锁屏、灵动岛）/ macOS（控制中心）/ **Windows（SMTC：TimelineProperties 进度条 + SeekTo 回传，其 C++ L221/L405 已源码核实）** / Web
- **`audio_service_mpris ^0.2.1`（Linux）**：**脱离 audio_service 直接驱动**——它只依赖 audio_service_platform_interface，注册实例并推送 SetState/SetMediaItem 即可；`SetPosition`（L58）与 `Seeked`（L317）双向完整（源码已核实）
- 业务侧：`MediaSessionCast` 接口（ADR-003）不变，写两个适配实现（fms 适配器 + mpris 直驱器，约 150 行胶水，属业务代码而非 SDK）

**理由**

1. 两条硬要求同时满足：功能全（seek 五端第一天全通，无缺口、无补丁）+ 零 fork、零 Rust、零自研原生模块（三个包全是现成 pub 包）。
2. fms 与本项目架构对口：官方定位即 "bring your own player (just_audio, media_kit…)"，Windows 端能力经源码核实**比 audio_service_win 更完整**。
3. mpris 直驱器落在自家 `MediaSessionCast` 适配层；若 fms 官方日后发布 MPRIS 支持（README 已列 Planned），可无缝收敛为单包。
4. 生产界对照（§2.7）：Namida/Harmonoid 都得 fork 或自写原生——fms 是在"总要改一点"的现实里**改动最小**的路。

**后果**

- 正面：零 fork、零 Rust、零自研 SDK；seek 全端完整；fms 活跃（2026-10-26 仍 push，v3.1.0-pre 持续迭代）。
- 负面：fms 年轻（2026-04 创建、4 likes、单人维护）；需自维护 mpris 直驱器约 150 行；fms 稳定版为 3.0.9（3.1 处于 pre）。
- 缓解：包风险被 `MediaSessionCast` 适配层隔离——若 fms 停滞，回退链：换 audio_service 三件套并接受 fork（ADR-013）→ win32 自实现（ADR-012）。排期仍在 M5，不阻塞播放主链路。
- 明确不做：不 fork audio_service_win；不为"单包"更换播放引擎（audio_manager 否决不变）。

---

## 附录：ADR 索引

| ID | 主题 | 状态 |
|---|---|---|
| ADR-001 | 从零新建 vs 改造栖弦 | 已采纳 |
| ADR-002 | 统一 media_kit 引擎 | 已采纳 |
| ADR-003 | 引擎/焦点/广播三职责分离 | 已采纳 |
| ADR-004 | MusicFree 主生态、lx 兼容层 | 已采纳 |
| ADR-005 | 不为 any-listen 单独适配 | 已采纳 |
| ADR-006 | flutter_js + 风险缓解 | 已采纳（风险登记） |
| ADR-007 | 单一 RuntimeHost | 已采纳 |
| ADR-008 | 能力位驱动降级 | 已采纳 |
| ADR-009 | 桌面焦点空实现 | 已采纳 |
| ADR-010 | drift 数据层 | 已采纳 |
| ADR-011 | 首期不做 Web | 已采纳 |
| ADR-012 | 原生下沉边界；Win SMTC 曾定自实现 | 已采纳（SMTC 部分被 ADR-013 取代） |
| ADR-013 | Win SMTC 用联邦实现 audio_service_win | 已采纳（实现选型被 ADR-014 取代） |
| ADR-014 | 媒体控制层终选：fms + 直驱 mpris，零 fork 零自研 | 已采纳 |