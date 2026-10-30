# Aiwli Music 文档索引

**项目**：跨平台（Android / iOS / macOS / Windows / Linux）Flutter 音乐播放器，功能对齐 lx-music，支持 MusicFree 插件与 lx 源脚本。
**状态**：**文档阶段完成，尚未开始编码**（2026-10-29 修订：ADR-014 终选媒体控制层——零 fork 零自研）

---

## 代码

Flutter 工程在本仓库 `app/` 目录下（v0.1.0 本地+音源闭环版）：

```bash
cd app && flutter pub get
flutter run -d <device>   # 或 flutter build apk --debug
```

依赖全部来自 pub.dev，零手写平台代码（MainActivity 仅 3 行模板）。
详细依赖选型证据见 [`docs/dependency-evidence.md`](docs/dependency-evidence.md)。

---

## 读文档的顺序

**新接手者按此顺序读**：

| 顺序 | 文档 | 读它是为了 | 篇幅 |
|---|---|---|---|
| 1 | 本文档 | 知道有哪些文档、边界在哪 | 短 |
| 2 | [`adr-aiwli-music.md`](docs/adr-aiwli-music.md) | **先理解为什么这样定**，避免重复挑战已决策项 | 中 |
| 3 | [`aiwli-music-design.md`](docs/aiwli-music-design.md) | 施工主依据：架构、接口、目录、里程碑 | 长（主文档） |
| 4 | [`ui-spec-aiwli-music.md`](docs/ui-spec-aiwli-music.md) | 界面结构、交互规则、验收清单 | 长 |
| 5 | [`spike-lx-execution-plan.md`](./spike-lx-execution-plan.md) | **第一件要做的事**：验证 QuickJS 能否跑真实 lx 脚本 | 中 |
| — | [`selection-evidence.md`](docs/selection-evidence.md) | 仅需追溯选型证据时查阅（**非施工文档**） | 中 |
| — | [`dependency-evidence.md`](docs/dependency-evidence.md) | 想知道「某个包到底要不要 Rust/原生工具链」时查（**实测证据附录**） | 中 |

---

## 各文档职责边界（避免矛盾）

```
adr-aiwli-music.md          → 只回答"为什么"（决策）
aiwli-music-design.md → 只回答"做什么、怎么做"（施工规格）
ui-spec-aiwli-music.md      → 只回答"长什么样、怎么交互"
spike-lx-execution-plan.md     → 只回答"第一步怎么验证"
selection-evidence.md → 只记录"调研证据"（无施工效力）
dependency-evidence.md         → 只记录"依赖实测证据"（无施工效力）
```

**冲突裁决顺序**：主设计文档 > ADR > UI 规格 > 证据附录。
任何一处需要改动决策，**先改 ADR 并说明理由**，再同步主文档，不要只改一处。

---

## 项目一句话定位

> 用 Flutter 做五端音乐播放器：**播放引擎统一 media_kit**（不做移动/桌面双引擎），**音源以 MusicFree 插件为主生态、lx 源脚本为兼容层**，**音源脚本用 flutter_js 在 QuickJS/JSC 中隔离执行**。

## 四条不可违反的硬约束

1. **从零新建工程**，栖弦（CyShineMusic，MIT）只作参考实现与可复制素材，不作代码基座
2. **业务层零平台 import**——平台分支只允许出现在 `lib/platform/` 与 `main.dart`
3. **许可红线**：AGPL 生态（MusicFree / MusicWEP / any-listen）**只能读思路、不得复制代码**；any-listen 额外禁止商用
4. **不自研 SDK**：播放引擎、音源宿主、媒体控制、标签读写**一律用现成 pub 包，不 fork、不写原生、不维护第三方代码的私有副本**（ADR-012/013/014 确立的边界；媒体控制层终选 fms + mpris 直驱，见 ADR-014）

---

## 当前待你拍的 5 个决策（主文档 §16）

这些会实质影响设计，建议开工前定：

| ID | 问题 | 影响 | 建议默认 |
|---|---|---|---|
| Q1 | 是否商用 | 决定 AGPL 生态能否参考、是否需完全自研 | 非商用 |
| Q2 | 是否做 M6（移植 lx 内置官方 API） | 决定"装 lx 脚本能否搜索" | 先做 MusicFree，M6 延后 |
| Q3 | 是否要 iOS | 后台音频 + 上架审核工作量 | 做 |
| Q4 | 是否预置内置源 | 合规 | 不预置，用户自行导入 |
| Q5 | 数据同步方案 | M6 范围 | 首期不做 |

---

## 项目关键路径（一句话）

**先做 `spike-lx-execution-plan.md` 的实验。** 它用 3 天回答"flutter_js 能不能跑真实 lx 脚本"，这个答案决定整个音源架构（主路径 or 双轨）。在它给出结论前，不要开始写 M2 的两周代码。

---

## 文档清单与产出状态

| 文件 | 状态 | 说明 |
|---|---|---|
| `README-docs-index.md` | ✅ 完成 | 本索引 |
| `adr-aiwli-music.md` | ✅ 完成 | 11 条 ADR |
| `aiwli-music-design.md` | ✅ 完成 | v2.0，16 章 + 2 附录 |
| `ui-spec-aiwli-music.md` | ✅ 完成 | 13 章 + 验收清单 |
| `spike-lx-execution-plan.md` | ✅ 完成 | 3 天实验方案 + 判定阈值 |
| `selection-evidence.md` | ✅ 完成（降级） | 选型证据附录 |
| `dependency-evidence.md` | ✅ 完成 | 依赖实测证据（含"要不要 Rust"判定） |

**未写（等决策或等开工）**：
- 具体 UI 视觉稿（配色、图标、间距 token）——建议用 `frontend-design` 流程单独产出
- 数据同步协议规格（等 Q5）
- lx 内置官方 API 移植清单（等 Q2）
- CI 流水线配置文件（等 M0 建仓后写）

---

## 交接自检

接手者可回答以下问题，即说明文档足够：

- [ ] 为什么不用 just_audio？（→ ADR-002）
- [ ] 为什么不为 any-listen 单独做适配器？（→ ADR-005）
- [ ] 桌面端为什么没有音频焦点代码？（→ ADR-009）
- [ ] 用户装了 lx 脚本为什么可能搜不到歌？该怎么办？（→ ADR-004 + 主文档 §4.3）
- [ ] 音源脚本在哪个平台用什么引擎？（→ 主文档 §4.1）
- [ ] 第一件事该做什么？（→ spike 手册）
- [ ] 哪些仓库的代码能抄、哪些只能看？（→ 主文档 §12）
- [ ] 为什么 Windows SMTC 不用 `smtc_windows`？构建机要装 Rust 吗？（→ ADR-013/014 + `dependency-evidence.md` §2.1）
- [ ] 为什么不用 `audio_manager` 一个包把播放和媒体控制都搞定？（→ ADR-013 理由 2 + ADR-002）
- [ ] Windows 系统浮层能拖进度吗？应用内进度条呢？（→ ADR-014：五端第一天全通；证据 `dependency-evidence.md` §2.6）
- [ ] 媒体控制层为什么是两个包而不是一个？fms 停滞了怎么办？（→ ADR-014 + `dependency-evidence.md` §2.7：单包五端 seek 不存在；回退链在适配层后面）
- [ ] 为什么 aiwli_git 用 Rust 有理，而播放链路不该学它？（→ ADR-012 理由 1/4）
---

## 开源协议

Copyright © 2026 Aiwli. 本项目以 **AGPL-3.0-or-later**（GNU Affero 通用公共许可证 v3 或更新版本）
发布 —— 与 [aiwli_git](https://github.com/zeplee/aiwli_git) 一致，见 [LICENSE](LICENSE)。
依赖均为 MIT/BSD/Apache 等宽松协议，兼容聚合。

## 合规声明（重要）

- **本项目不内置任何音源**：壳工程零内置搜索/取链/榜单能力，全部由用户自行导入的
  lx 音源脚本提供（与 lx-music 官方发布版同构）。脚本的能力声明（`musicUrl` /
  `lyric` / `pic` / `musicSearch` / `boardList` / `boardSongs`）决定功能是否可用，
  未声明的能力对应 UI 自动隐藏。
- 搜索与排行榜功能仅在所导入脚本声明相应能力时可用；本项目不分发、不预置任何
  音源脚本。
- 请仅将本项目用于个人学习与合法用途，音乐内容版权归属各自权利人。
