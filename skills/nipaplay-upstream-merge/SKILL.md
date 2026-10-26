---
name: nipaplay-upstream-merge
description: Use when merging upstream AimesSoft/NipaPlay-Reload into this fork, resolving conflicts, or when upstream code fails to compile after a merge. Documents the package-path re-pointing iron rule, the adjudication principles for overlapping feature work, and the mechanical merge workflow proven on the 1.11.9→1.11.11 merge (43 UU + 4 AA conflicts, zero analyze errors).
---

# NipaPlay 上游合并方法论

本仓库是长期特性分支（origin = TsangAsuna/features，分支 nipaplay），上游 =
`AimesSoft/NipaPlay-Reload`（默认分支 **main**，不是 nipaplay——`git branch -r`
里 codex/* 一堆，main 才是发布线）。合并节奏：拉 upstream → 合 main → 解冲突 →
analyze 0 error → 冒烟测试 → amend 合并提交 → push origin（**不建 PR**）→
手动派发 sideload IPA 构建。

## 铁律 1：包路径重指向（每次合并必踩）

本树把大量代码迁入了 `nipaplay_core` / `nipaplay_ui_common` 包，上游仍用
`lib/` 相对路径。**上游每个新文件/新测试都要检查 import**，本树不存在的
路径清单（2026-10 实测）：

| 上游写的路径 | 本树真实位置 |
|---|---|
| `package:nipaplay/models/bangumi_model.dart` | `package:nipaplay_core/models/bangumi_model.dart` |
| `package:nipaplay/models/torrent_task.dart` / `torrent_magnet_preview.dart` / `shared_remote_library.dart` / `search_model.dart` / `media_server_playback.dart` | `package:nipaplay_core/models/…` |
| `package:nipaplay/models/torrent_add_result.dart` | `package:nipaplay/models/`（上游自有，勿动） |
| `package:nipaplay/utils/network_settings.dart` / `platform_utils.dart` / `mpv_utils.dart` | `package:nipaplay_core/utils/…` |
| `package:nipaplay/services/webdav_service.dart` / `web_remote_access_service.dart` / `dandanplay_remote_service.dart` | `package:nipaplay_core/services/…` |
| `package:nipaplay/utils/danmaku/style.dart` | `package:nipaplay_core/utils/danmaku/style.dart` |
| `package:nipaplay/danmaku_abstraction/*` | `package:nipaplay_core/danmaku_abstraction/*` |
| `package:nipaplay/player_abstraction/player_enums.dart` | `package:nipaplay_core/player_abstraction/player_enums.dart` |
| `package:nipaplay/app/*`（app_display_surface / scope / app_page_ids / app_navigation_scope） | `package:nipaplay_ui_common/app/*` |
| `package:nipaplay/l10n/*` | `package:nipaplay_ui_common/l10n/*` |
| `package:nipaplay/themes/nipaplay/widgets/ui_scale_wrapper.dart` | `package:nipaplay_ui_common/themes/nipaplay/widgets/…` |
| `package:nipaplay/widgets/intro_skip_button.dart` | `package:nipaplay_ui_common/widgets/…` |
| `package:nipaplay/settings/adaptive_settings_scope.dart` | `package:nipaplay_ui_common/settings/…` |

判别法：import 的 URI 去掉 `package:<pkg>/` 前缀映射到
`lib/`（nipaplay）、`packages/nipaplay_core/lib/`、`packages/nipaplay_ui_common/lib/`
做存在性检查，按"文件正文实际引用的符号在哪个包"重指向。**批量重映射脚本
里不要按目录前缀整串替换后丢文件名**（1.11.11 合并踩过：`app/` 前缀替换把
文件名吞了，要从 git 恢复原始文件名重做）。

同目录双副本（如 `lib/utils/network_address_utils.dart` 与 core 副本）要么
re-export 壳要么同步维护；`video_aspect_geometry.dart` 选择了 core 为实现、
lib/ 路径放 re-export 壳——**单一类型来源**，避免同名类两种类型。

## 铁律 2：裁定原则（双方都改过同一段时）

按顺序判：
1. **上游吸收了我们先前移植/提交的 PR，且带测试** → 整体取上游
   （例：WebDAV id 重绑 #989 → 上游 wanUrl 双地址版；bangumi SWR 42a57e77 →
   上游 #1004）。本地实现标记为"已被上游取代"。
2. **上游修的是我们没见过的真实事故、带守卫/竞态代数** → 子系统整体取上游，
   把本地独有修复按清单 graft 回去（例：字幕自动加载取上游 detectionToken/
   register 模型，回填缓存预算/哈希名归正/单候选宽限三项）。
3. **本地是纯性能/焦点优化、上游无对应物** → 保留本地（ValueNotifier 焦点
   索引、RepaintBoundary、约束解码、常驻 Opacity 消除）。
4. **两边是不同功能恰好相邻**（AppDelegate 两个 MethodChannel、main.dart
   imageCache 预算 vs 鸿蒙授权恢复）→ 双保留拼接。
5. 语义拿不准时：先做符号依赖分析（HEAD 侧正文还引用哪些上游符号、反之），
   再按子系统粒度裁决，**最后靠 `flutter analyze` 收口**——拼接错误（缺括号、
   重复声明、undefined method）都会被它抓出来。

## 铁律 3：机械流程（ proven on 1.11.9→1.11.11）

```bash
git stash push -m "pre-merge leftovers"        # 工作区杂项先收起，别混进合并提交
git remote add upstream https://github.com/AimesSoft/NipaPlay-Reload.git
git fetch upstream                              # 上游 tag 会"would clobber"，无视
git merge upstream/main --no-edit               # 冲突全列出来
# 逐文件解：单 hunk 用 python 按序号取 head/up（写清 choice 表防手滑），
# 大子系统先符号分析再整段裁决；每解一个文件 grep -c '^<<<<<<<' 归零
git diff --name-only --diff-filter=U | xargs git add --   # 只暂存冲突文件
git stash pop                                   # 杂项回到工作区（不入合并提交）
git add <合并期间新建的文件>                     # re-export 壳、迁入 core 的工具类
flutter analyze lib test                        # 目标 0 error（vendored 包 error 忽略，见下）
flutter test <合并敏感区测试>                    # 每子系统挑 1-2 个契约测试
git commit（合并信息写裁定清单）→ 需要追加修复时 git commit --amend
git push origin nipaplay
```

- **vendored 包的 analyze error 是合并前就有的**
  （`packages/adaptive_platform_ui/example`、`packages/file_selector_ohos/example|test`、
  `packages/desktop_multi_window_linux_347`），验证法：
  `git diff HEAD...upstream/main --stat -- <path>` 为空即与合并无关，忽略。
- 冲突 hunk 多的文件（30+）不要逐 hunk 硬读：先 `git diff HEAD...upstream/main
  --stat -- <file>` 看上游改动量，再决定按 hunk 还是按子系统裁决。
- 合并期间新增的文件必须显式 `git add`（stash pop 后它们是 untracked）。
- 本机 Flutter 不在 PATH：`"F:/Hermes Agent CN Desktop
  Portable/data/hermes-home/workspace/flutter/bin/flutter.bat"` 全路径调用。

## 已知上游演进（后续合并会再遇到）

- `ExternalSubtitleOverlay` 改为 const 自绑定 `playbackTimeMs`（VideoState
  继承注入），不能再传 `currentPositionMs`。
- dfm overlay 被上游包了 `Visibility`（结构多一层括号，合并时数好配对）。
- MDK/字幕子系统见 [[nipaplay-player-kernel]]；bangumi 缓存见
  [[nipaplay-bangumi-cache]]。
- 上游测试文件大量引用旧包路径，`test/` 也要跑一遍重映射。
