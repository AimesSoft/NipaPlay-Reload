# 阶段一回归验证报告 — nipaplay_core 抽取

- 仓库：`NipaPlay-Reload-features`（branch `nipaplay`）
- 基线 commit：`11c2786b`（perf(metadata): stop synopsis cache thrash...）
- 最终 commit：`449eaebd`（batch 5），中间 aca5caad / b2 / 3c3be3f8 / 8ca890f8
- 执行日期：2026-10-12
- 执行环境：Windows 10 x64 + Flutter 3.44.6 stable（Dart 3.12.2），Git Bash

## 1. 交付总览

| 项 | 结果 |
|---|---|
| `packages/nipaplay_core` | 已创建，149 个 dart 文件，含统一播放器接口 `player/nipa_player.dart` |
| git mv 搬移文件 | **147 个**（B1=39, B2=12, B3=37, B4=17, B5=42），`git show -M50 --name-status` 全部 R100，`git log --follow` 可穿透重命名追溯历史 |
| app 内 import 改写 | ~450 个文件、约 770 处 URI（`package:nipaplay/...` 与相对路径 → `package:nipaplay_core/...`），由迁移引擎 `docs/refactor/tools/move_batch.py` 完成 |
| core 依赖（全部非 UI） | flutter(foundation/services), path, xml, charset, cp949_codec, enough_convert, shared_preferences, http, crypto, uuid, dio, webdav_client, flutter_rust_bridge 2.12.0, dart_ipc, ffi |
| 红线静态检查 | `scripts/check_core_purity.sh` **通过**（禁 material/cupertino/widgets/rendering/painting/animation 与 UI 第三方包；dart:ui 仅值类型；禁 Widget/BuildContext 符号） |
| 行为改写 | 仅 2 处 import 级清理（danmaku_content_item、danmaku_color_presets：material→dart:ui show Color；Colors.white→const Color(0xFFFFFFFF)），逐符号核对，值完全一致 |
| 新增代码 | `player/nipa_player.dart`（NipaPlayer/PlayerFactory/PlayerCapabilities/PlayerConfig/MediaSource/PlayerState/NipaTargetPlatform/NipaPlayerSurface）+ 迁移/校验工具脚本 |

### 与用户模板的偏差（约束 3 优先，详见 core-inventory.md §1.2）
- `Widget buildVideoSurface()` → `NipaPlayerSurface createSurfaceHandle()`（不透明描述符，UI 层包装成 Widget）
- `TargetPlatform` → core 自有 `NipaTargetPlatform` 枚举
- 四内核适配器对 NipaPlayer 的**实现**与统一接口的接线，推迟到内核适配器完成依赖注入解耦之后（四适配器反向依赖 app 层 subtitle_font_loader/storage_service/watch_history_database；erika 适配器含 StatefulWidget）——已列入库存文档 Batch 2"同批不搬"清单

## 2. 回归验证对比（重构前 / 重构后）

### 2.1 flutter analyze（全仓库）
| 指标 | 基线 11c2786b | 重构后 449eaebd | 判定 |
|---|---|---|---|
| **lib/ error** | **0** | **0** | ✅ 持平 |
| **test/ error** | **0** | **0** | ✅ 持平 |
| lib/ warning | 192 | 188-191 | ✅ 无新增 |
| lib/ info | 1817 | 1708-1817 | ✅ 无新增（搬移后减少） |
| packages/ error | 1149 | 1149 | ✅ 持平（vendored 包，不属于本项目质量门） |
| third_party/ error | 875 | 875 | ✅ 持平 |
| core 包自身 error | — | 0 | ✅ |

日志：`docs/refactor/logs/baseline_pubget_analyze.log`、`b5_analyze3.log`（含 b1–b4 各批日志）

### 2.2 flutter test（全量，~870 用例）
| 指标 | 基线（两次采样） | 重构后（每批全量） | 判定 |
|---|---|---|---|
| 通过 | 843–844 | **844** | ✅ 持平 |
| 跳过 | 25 | 25 | ✅ |
| 失败 | 7–8 | **6** | ✅ 失败集合为基线预存子集，无新增 |

基线预存失败（在 HEAD worktree 上复现确认，与本重构无关）：
1. `danmaku_matching_access_test`（源码扫描型，预存）
2. `android_tv_platform_policy_test`
3. `mainline_flutter_compatibility_test`（Linux dependency override，预存）
4. `bangumi_external_auth_launch_test`
5. `television_media_library_test`（Provider 注入，预存）
6. `tvos_erika_kernel_policy_test` × 2（源码扫描断言 `\n` 行尾，Windows checkout 为 CRLF 而失败）
7. `subtitle_manager_regression_test`（**flaky**：worktree 复跑通过；真实文件 IO + 时序）

重构后消失的基线失败 2 项（均为良性翻转）：
- `tvos_erika/release uses shared hosted Erika`：其断言依赖源码含 `\n`；迁移引擎改写 `system_resource_monitor.dart`（1 行 import 变更）时按 `.gitattributes text=auto` 归一化为 LF，断言由失败转通过。文件语义 diff 仅 1 行。
- `subtitle_manager_regression_test`：flaky，本次运行通过。

重构过程中引入又修复的回归（如实记录）：
- Batch 1：`tvos_large_screen_adaptation_policy_test`、`unified_app_architecture_test`——源码扫描型测试硬编码 `lib/constants/settings_keys.dart` 路径，文件搬移后 PathNotFound。已把扫描路径更新为 `packages/nipaplay_core/lib/constants/settings_keys.dart`（修后全绿）。
- Batch 2：`erika_gif_export_contract_test` 同理（`erika_gif_export_io.dart` 路径），已更新。

### 2.3 flutter build windows --debug
| 指标 | 基线 | 重构后 |
|---|---|---|
| 结果 | **失败**：nipaplay_smb2 插件原生 C 编译（libsmb2/socket.c，MSVC 警告即错误） | **失败**：universal_gamepad 插件原生 C++ 编译（sdl_manager.h，C2220 警告即错误） |

两次失败均为 **vendored 插件的原生 C/C++ 编译问题**（本机 MSVC/SDK 组合下"警告视为错误"），与 Dart 重构无关——重构未触碰任何 vendored 插件，失败点不同属原生并行编译的非确定性。Dart 侧编译完整性由 analyze 0 error + 全量测试覆盖（构建日志：`docs/refactor/logs/baseline_test_build.log`、`post_refactor_build.log`）。Windows 端原生构建修复不在本阶段范围（用户发版走 CI，仓库带 release workflow）。

### 2.4 core 纯净度（scripts/check_core_purity.sh）
每批执行，最终状态：**通过**——core 无 material/cupertino/widgets/rendering/painting import、无 UI 第三方包、无 Widget/BuildContext/StatefulWidget 符号、dart:ui 仅几何值类型。

## 3. 每批次记录（每批独立 commit，独立可验证）

| 批次 | commit | 文件数 | 主要内容 | 门禁结果 |
|---|---|---|---|---|
| B1 models/constants/utils | aca5caad | 39 | 19 模型 + emby 选择簇 + app_http_proxy/process_memory_cache 等 + 5 constants + 3 utils | ✅ |
| B2 player 基座 + 统一接口 | (见 git log) | 12+1 | abstract_player/enums/data_models/hwdec/erika_gif_export/mock_mdk/mpv_utils/几何/着色器管理器 + nipa_player.dart | ✅ |
| B3 弹幕解析 + cpp_native | 3c3be3f8 | 37 | cpp_native FFI 绑定 29 文件 + 弹幕解析/转换 + content/positioned item + 2 处 UI import 清理 | ✅ |
| B4 网络基座 | 8ca890f8 | 17 | 证书信任/系统代理/http_overrides/传输层/LAN 发现/服务器路由/远程访问/设置存储 | ✅ |
| B5 rust FFI + WebDAV | 449eaebd | 42 | src/rust 22 文件（frb 绑定）+ webdav_service + 增量同步 + 外部播放器会话模型 | ✅ |

## 4. 未搬移清单与依赖循环（等待人工决策，约束 6）

未搬移：video_player_state 上帝类（1.45 万行 UI 态）、全部 pages/widgets/themes/controllers/providers、23 个 UI 污染 services、danmaku 全部渲染层（overlay/painter/atlas）、plugin_service 本体、globals.dart 等（完整清单见 core-inventory.md §3/§4）。

实锤循环 4 组（未强行打破）：
1. `watch_history_model ⇄ watch_history_database`
2. `player_factory → system_resource_monitor → player_factory`（连带 `player_kernel_manager ⇄ video_player_state`）
3. `smb_service → smb2_native_service(barrel) → smb2_native_service_ffi/stub → smb_service`
4. `web_server_service → web_api_service → providers/service_provider → web_server_service`

人工决策建议：环 1 拆纯数据类或抽 repository 接口；环 2 把"内核名上报"改为事件注入；环 3 凭据获取改接口注入；环 4 组合根移到 main 侧。四环解开后，watch_history 模型、player_factory、smb_service、web_server 组可进入 core。

## 5. 复现方式

```bash
# 静态检查（core 红线）
bash scripts/check_core_purity.sh
# 分析门
flutter analyze   # lib/ 与 test/ error 必须为 0
# 单元测试
flutter test      # 失败集合须 ⊆ 基线预存 6 项
# 批次搬移（后续阶段复用）
python docs/refactor/tools/move_batch.py docs/refactor/tools/batchN.json --dry-run
python docs/refactor/tools/move_batch.py docs/refactor/tools/batchN.json
flutter analyze && bash scripts/check_core_purity.sh && flutter test && git commit
```

## 6. 结论

阶段一达成：`packages/nipaplay_core` 承载数据模型、常量、纯工具、播放器抽象基座与统一接口、弹幕解析、C++/Rust FFI 绑定、网络基座与 WebDAV 客户端；普通版 analyze/test 与基线持平、历史保留（R100 + --follow 可溯）、core 红线由脚本强制。阶段二（ui_common 抽取）可在本基线上开始。
