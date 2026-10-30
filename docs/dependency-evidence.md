# 依赖实证核查（Dependency Evidence）

**版本** v1.0 · 2026-10-28
**性质**：**证据附录，无施工效力**。主文档引用本文结论，但冲突时以主文档 + ADR 为准。
**用途**：记录"每个关键依赖到底能不能用、要不要原生工具链"的**实测证据**，避免后人凭印象推翻或重复踩坑。

> 所有核查均通过 pub.dev API 与**解包 tar 包实际查看内容**完成，不是看 README 猜想。核查日期见各条。

---

## 0. 核查方法

```bash
# 元数据
curl -s https://pub.dev/api/packages/<pkg> | jq '.latest.pubspec'

# 关键：解包看真实内容（有无预编译产物、有无 Cargo.toml）
curl -sL https://pub.dev/packages/<pkg>/versions/<ver>.tar.gz | tar tz
```

**判定"是否需要 Rust"只看两点**：
1. pubspec 依赖里是否出现 `flutter_rust_bridge` / `rust_lib_*`
2. 包内是否含 `Cargo.toml` / `rust/` 目录，且**不含**预编译 `.dll`/`.so`

---

## 1. 播放链路：全部无需 Rust

| 包 | 版本 | 原生要求 | 结论 |
|---|---|---|---|
| `media_kit` | 1.2.6 | 无（纯 Dart 壳） | ✅ 无需 Rust |
| `media_kit_video` | 2.0.1 | 无 | ✅ 无需 Rust |
| `media_kit_libs_audio` | 1.0.7 | 聚合包（见下） | ✅ 无需 Rust |
| `media_kit_libs_windows_audio` | 1.0.9 | **CMake**（下载预编译 libmpv） | ✅ 无需 Rust |
| `media_kit_libs_android_audio` | — | 预编译 `.so` | ✅ 无需 Rust |
| `media_kit_libs_linux` | — | 系统/随附 libmpv | ✅ 无需 Rust |

### 1.1 `media_kit_libs_windows_audio` 的决定性证据

解包后**不含任何 `.dll`**，实际内容只有 C++ 插件壳与 CMake 脚本：

```
windows/media_kit_libs_windows_audio_plugin_c_api.cpp
windows/include/.../media_kit_libs_windows_audio_plugin_c_api.h
windows/CMakeLists.txt
```

`CMakeLists.txt` 里的实际下载地址：

```cmake
set(LIBMPV "mpv-dev-x86_64-20230924-git-652a1dd.7z")
set(LIBMPV_URL "https://github.com/media-kit/libmpv-win32-audio-build/releases/download/2023-09-24/${LIBMPV}")
download_and_verify(...)
```

**含义**：Windows 上要 **CMake**（下载 + 校验 MD5 + 解压预编译 7z），**但不需要 Rust、不需要编译 mpv/ffmpeg 源码**。这与 aiwli_git 的 `cargokit 现编 vendored libgit2/openssl` 有本质区别。

---

## 2. 系统媒体集成：唯一的历史痛点是 Windows

| 包 | 版本 | 平台 | 原生要求 |
|---|---|---|---|
| `audio_service` | 0.18.19 | android / ios / macos / web | ✅ 无 Rust |
| `audio_session` | 0.2.4 | android / ios / macos / web | ✅ 无 Rust |
| `audio_service_mpris` | 0.2.1 | linux | ✅ 无 Rust（dbus） |
| `smtc_windows` | 1.1.0 | windows | ❌ **需要 Rust** |
| `win32` | 6.4.0 | windows | ✅ 纯 Dart |
| **`audio_service_win`** | 0.0.3 | windows | ✅ C++/WinRT，无 Cargo.toml |
| `flutter_media_session` | 3.0.9 | **A/iOS/mac/Win/web（缺 Linux）** | ✅ 无 Rust |
| `audio_manager` | 1.0.0 | **六端全**（但是完整播放器） | ✅ 无 Rust |

### 2.1 `smtc_windows` 为什么被否决

pubspec 依赖：

```yaml
dependencies:
  flutter_rust_bridge: ^2.11.1
```

解包确认：

```
./Cargo.toml
./rust/Cargo.toml
（无任何 .dll —— find . -name "*.dll" 返回空）
```

**含义**：每个 Windows 构建机与 CI 都必须装 rustup 并现场编译。为一个"把曲目信息告诉任务栏"的能力付这个代价不划算 → **ADR-012 决定改用纯 Dart**。

### 2.2 `win32` 为什么可行（已验证底层齐备）

> **2026-10-29 注**：本节结论技术上成立，但已被 ADR-013 取代——发现了更省开发量的现成联邦实现（见 §2.3）。win32 自实现降级为回退链最后一环。

依赖仅 `ffi` / `ffi_leak_tracker` / `meta`，**纯 Dart**。解包确认它同时具备：

| 能力 | 证据文件 |
|---|---|
| COM 基础 | `lib/src/com/iunknown.g.dart`、`iclassfactory.g.dart` |
| COM 创建实例 | `ole32` 相关（测试用例 `test/com/propvariant_test.dart`） |
| **WinRT 激活** | `lib/src/win32/api_ms_win_core_winrt_l1_1_0.g.dart` 内 `RoGetActivationFactory<T extends IUnknown>(HSTRING, ...)` |
| 已生成的 COM 接口 | `iaudioclient`、`immdevice`、`ishellitem`、`iuiautomation` 等数百个 |

**缺什么**：SMTC 自身的接口声明（`ISystemMediaTransportControlsInterop`、`ISystemMediaTransportControls`、`ISystemMediaTransportControls2`）。需要自己写声明 + 用 `RoGetActivationFactory` 激活。这是**一次性工作**，之后零构建负担。

### 2.3 `audio_service_win`（ADR-013 采纳）

解包核实（2026-10-29）：

```
./lib/audio_service_win.dart          → class AudioServiceWin extends AudioServicePlatform
./windows/audio_service_win_plugin.cpp → SystemMediaTransportControls / winrt::
（无 Cargo.toml —— C++ 原生插件，不需要 Rust）
```

- pub 官方联邦标签：`implements-federated-plugin:audio_service_platform_interface`
- MIT、140/160 分、月下载 3.7k
- **限制**：仅实现 6 个方法（configure / setMediaItem / setState / setQueue / stopService + registerWith），C++ 侧无 `TimelineProperties` → 任务栏进度条不可用
- 规模：339 行 C++ + 117 行 Dart → 补 TimelineProperties + PositionRequest 事件预估 ~100 行（ADR-013 追记的首选补齐方案）
- 回退链：上游 PR → `smtc_windows`（加 rustup）→ win32 自实现（ADR-012）

### 2.4 `flutter_media_session`（评估未采纳）

- 平台 A/iOS/macOS/Windows/web，**缺 Linux**；纯媒体控制（非播放器）
- Windows 端实测含 `SystemMediaTransportControlsInterop` 与 `TimelineProperties` → **支持进度条**，比 audio_service_win 完整
- 4 likes / 月下载 1.7k；若采用需为 Linux 另配 MPRIS 服务（如 `anni_mpris_service`），两套 API 两处胶水代码
- 结论：Windows 能力更强但整体开发量更高；留作 audio_service_win 长期缺能力时的备选

### 2.5 `audio_manager`（评估否决）

- **单包六端、150 likes、2026-08 仍活跃**——表面最符合"全平台单包"
- 但解包 + README 核实：它是**完整播放器**（Android MediaPlayer / Windows `Windows.Media.Playback` / Linux GStreamer+MPRIS 自带），不是纯媒体控制层
- 采用即替换 media_kit，与 ADR-002 冲突：引擎按平台分裂，gapless/header 行为无法保证一致；无 namida/harmonoid 量级的生产验证
- 结论：对"已有统一引擎"的项目是倒退；仅适合从零且不在意跨端一致性的小项目

### 2.6 系统层 seek 五端能力核实（2026-10-29，发起人确认「拖动进度必要」后）

| 平台 | 系统界面拖进度 | 证据 |
|---|---|---|
| Android/iOS/macOS | ✅ 完整 | audio_service 本体：MediaStyle 通知 / 锁屏 / Now Playing 进度条 + 回调 |
| Linux | ✅ 完整 | `audio_service_mpris` 源码 `mpris.dart` L58 实现 `SetPosition` 方法、L317 `emitSeeked` 发 `Seeked` 信号，双向完整 |
| Windows | ❌ 缺 | `audio_service_win` C++ 侧无 TimelineProperties（见 §2.3） |

备选包能力：
- `smtc_windows`：Rust 绑定导出 `src/rust/internal/timeline.dart` → TimelineProperties 完整（回退方案 2）
- `flutter_media_session`：Windows 端含 `TimelineProperties`（见 §2.4），但缺 Linux，未采纳

**结论**：唯一缺口在 Windows，按 ADR-013 追记的补齐计划执行（首选 fork/PR，回退 smtc_windows）。

### 2.7 生态终局核查（2026-10-29，回答「还有没有更好的方案」）

穷尽性搜索证据（此后无需再找）：

| 核查项 | 结果 |
|---|---|
| pub 多关键词全扫（media controls desktop / system media transport / windows media session / MPNowPlaying 等） | **无新包**——候选池封闭：fms、audio_service 系、smtc_windows、win32、audio_manager、avplayer 系 |
| `audio_service_win` 上游 | 最后提交 **2026-03-29**（停滞 7 个月），共 5 个 issue → fork 路线需自担长期维护 |
| `flutter_media_session` Linux 计划 | README 标 "Planned (MPRIS)"，**分支里尚无 mpris 工作**（3.1.0-pre 只做了 Android 按钮布局与修复） |
| `avplayer_audio_service_win`（audio_service_win 的 fork） | grep **TimelineProperties = 0 次**——连 fork 也没补 seek，无捷径可捡 |
| media_kit 官方 | issue 区无 SMTC 集成计划（引擎不管系统媒体层） |
| **生产级交叉验证** | **Namida（6.7k★）pubspec 实际用 fork 版 audio_service**（MSOB7YY fork，2026-10 仍活跃，含 iOS 修复/skipIntervals 等）+ smtc_windows；Harmonoid（4.8k★）自写原生 C++。**最成熟的两个 Flutter 播放器都逃不开 fork 或自写** |

**结论**：不存在"零改动 + 单包 + 五端 seek"的现成方案。可选天花板就是两条。
**→ 2026-10-29 已定案：ADR-014 选 B 路线**（发起人准则：功能完善 + 尽量不自研 SDK，维护 fork 即自研）。原记录保留：
- **零 fork 路线（B）**：flutter_media_session + 直驱 audio_service_mpris —— 零 fork 零 Rust、seek 五端全通，代价是包年轻 + ~150 行胶水
- **生态成熟路线（A）**：audio_service 三件套 —— 单套 API，代价是维护一个小 fork（生产界常态，见上）

### 2.7 曲库扫描生态实测（2026-10-30，M4 真机验证）

需求：本机曲库扫描（MediaStore）+ 下载落库，**工程零手写平台代码**。

| 方案 | 结果 |
|---|---|
| `on_audio_query` 2.9.0（182★） | ✗ 无 namespace，AGP 9 构建即失败（2023-05 停更） |
| `media_browser` 1.3.1（六端，2026-09-28） | ✗ 真机实测（Android 12 小米）`no such column: genre`——其 SQL 引用设备 MediaStore 不存在的列；发布两天即翻车 |
| `on_audio_query_forked` 2.9.1（2024-10） | ✓ 已声明 namespace（备选，未采用——fork 死包） |
| **`on_audio_query_pluse` 3.0.7**（2026-06，活跃） | ✅ **采用**：federated，android 子包声明 namespace（AGP 9 兼容），`checkAndRequest` + `querySongs` 真机扫出 33 首与 Kotlin 方案等价 |
| 自写 90 行 Kotlin（旧方案） | ✓ 曾验证，已按「零手写平台代码」目标移除 |

**下载落库**：`flutter_media_store` 1.3.1（2025-01，saveFile/append，自动处理权限与 API 29+ IS_PENDING）替代手写 saveAudio。

**坑清单**：
1. `on_audio_query_pluse` 的 pub 主入口文件名是坏的（`lib/on_audio_query_pluse.dart` 不存在），须直接 `import 'package:on_audio_query_pluse/on_audio_query.dart'`
2. 其 API<33 权限检查要求 READ+WRITE **同时 granted**：manifest 须声明 `WRITE_EXTERNAL_STORAGE maxSdkVersion=32`，否则 checkAndRequest 永远 false
3. 主动判定平台分支的 SongModel 字段名与 on_audio_query 一致（title/artist/data/duration），data 即文件路径

**iOS/桌面**：M5 阶段评估 `media_browser`（六端，桌面=文件系统扫描）或纯 Dart `Directory.list + audio_metadata_reader`。

---

## 3. 对照案例：`zeplee/aiwli_git` 的 Rust 选择是否必要

这是用户提出"重 Rust 是不是被迫的"的直接核查对象。

| 问题 | 证据 | 结论 |
|---|---|---|
| Dart 有没有 Git 库？ | `git2dart` 0.5.6（2026-09-04 发版，持续维护） | **有** |
| 它的原生二进制齐备吗？ | `git2dart_binaries` 1.14.0，flutter plugin 声明 **android/ios/linux/macos/windows 五端齐全**，`ffiPlugin: true` | **齐备** |
| 那 aiwli_git 为什么还写 Rust？ | `git2dart` 只覆盖底层仓库操作；**块级暂存、cherry-pick 精细控制、冲突三方合并**等 UI 级语义无现成 Dart 实现 | **部分必要：填补语义空白，不是纯重复劳动** |
| 它的代价是什么？ | README 自述：`Windows/Linux：cargokit 现编 vendored libgit2/openssl，需 Rust + CMake` | **每次构建现编 openssl** |

**可复用的判断原则**：

> 不是"能不能写原生"，而是"**pub 生态是否已经提供了这个能力**"。提供了就用；只有确实空白时才下沉，且要清楚记下构建代价。

这条原则同时解释了两件事：
- aiwli_git 下沉**有理**（Git UI 级语义是空白）
- 播放链路下沉**无理**（media_kit 已把 mpv 预编译好，只差 CMake 解压）

---

## 4. 被否决的依赖（复核记录）

| 包 | 否决理由 | 核查日期 |
|---|---|---|
| `just_audio`（作为统一引擎） | 无 Windows/Linux 实现；桌面靠 `just_audio_media_kit`（14★、18 个月未发版、unverified uploader），且桥自承 gapless 实验性、shuffleOrder 被忽略 | 2026-10-27（见 ADR-002） |
| `smtc_windows` | 需 Rust（见 §2.1） | 2026-10-28 |
| `flutter_qjs` | 最后发版 2022-05，SDK 约束 `>=2.12 <3.0.0` | 2026-10-27 |

---

## 5. 复核提醒

pub 包状态会变。若距本文档超过 **6 个月**，或遇到构建失败，**按 §0 的方法重新解包核查**，不要直接引用本文结论。

重点复核项：
- `audio_service_win` 是否补齐 TimelineProperties / 更多方法（补齐则回退链第一环自动解决）
- `smtc_windows` 是否已改为预编译分发（若是，回退链第二环成本下降）
- `media_kit_libs_windows_audio` 的 libmpv 下载地址是否仍然有效（2023-09-24 的构建产物）
- `flutter_js` 维护状态（见主文档 §1.3）
