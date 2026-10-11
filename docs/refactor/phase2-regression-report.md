# 阶段二回归验证报告 — nipaplay_ui_common 抽取

- 仓库：`NipaPlay-Reload-features`（branch `nipaplay`）
- 阶段一起点：`6469bea0`；阶段二批次 commit：454a8f60 (批次0) / fee15142 (l10n) / (B+C+D)
- 执行日期：2026-10-12

## 1. 交付总览

| 项 | 结果 |
|---|---|
| `packages/nipaplay_ui_common` | 已创建，**36 个 dart 文件 + 3 个 arb + l10n.yaml** |
| git mv 搬移 | 批次0: 6 / 批次A: 8+3arb / 批次B: 7 / 批次C: 7 / 批次D: 10 = **41 dart 文件** |
| import 改写 | ~250 个文件、~360 处 URI |
| 显示面契约 | `AppDisplaySurface` 等全库渗透最广的抽象（50+ 文件）迁入，TV 版可直接消费 |
| l10n | zh/zh_Hant/en 三语言整层迁入（含 1 万行生成代码），app 43 个消费方改写 |
| 依赖 | ui_common: flutter, flutter_localizations, intl, nipaplay_core, flutter_markdown, markdown, glassmorphism |
| 纯度 | `scripts/check_ui_common_purity.sh` 通过：**零 `package:nipaplay/` 依赖**、无 providers/window_manager 等插件 |

## 2. "什么不搬"（用户明令：焦点/手势组件留各版本）
- 焦点/手势命中 11 个：adaptive_media_library_primitives/controls、adaptive_playback_entry_view、external_subtitle_overlay、adaptive_settings_widgets、macos_native_video_view、desktop_transient_overlay、context_menu_controller、airplay_route_picker、desktop_user_activity、adaptive_library_management_overview
- app 态胶水：settings 内容页 20 个 + unified_settings_entries(694) + unified_setting_content + media_library 页面/控件 + dashboard/presenter 等
- 播放态耦合：danmaku_overlay/container、player_menu 全部、indicator 系列
- 平台专属：cupertino/ 整目录(60 文件)、macos_platform_menu、desktop 窗口件
- B 级候选（参数化后可搬，TV 阶段按需）：embedded_subtitle_overlay、danmaku_group_widget、single_danmaku、media_server_network_image、tv_safe_blur、responsive_container、loading_placeholder、switchable_view、unified_torrent_page_model、unified_media_library_sections

完整清单：`docs/refactor/ui-common-inventory.md`

## 3. 回归验证对比

### 3.1 flutter analyze
| 指标 | 阶段一末（6469bea0） | 阶段二末 | 判定 |
|---|---|---|---|
| lib/ error | 0 | **0** | ✅ |
| test/ error | 0 | **0** | ✅ |
| lib/ warning | 188 | 188 | ✅ |
| lib/ info | 1708 | 1696–1708 | ✅ 无新增 |

### 3.2 flutter test（每批全量）
| 批次 | 通过 | 失败 | 失败集合 |
|---|---|---|---|
| 阶段一末基线 | 844 | 6 | 基线预存 |
| 批次 0 | 845 | 5 | 基线预存子集 |
| 批次 A (l10n) | 846 | 4 | 基线预存子集 |
| 批次 B+C+D | 845 | 5 | 4 项基线预存 + 1 项路径回归（已修复） |

基线预存失败集合（与阶段一报告一致）：danmaku_matching_access / android_tv_platform_policy / mainline_flutter_compatibility / bangumi_external_auth_launch / television_media_library / tvos_erika_kernel_policy（CRLF 行尾敏感 ×2，其中 1 项已因 LF 归一化通过）。注：bangumi_external_auth_launch 在多次运行中时过时不过（flaky 倾向），任何一次运行失败集合 ⊆ 基线集合即达标。

### 3.3 ui_common 纯度
`check_ui_common_purity.sh` 每批通过：无 `package:nipaplay/` import、无 provider/window_manager/tray_manager/desktop_multi_window 依赖、pubspec 无 app 本体 path。

## 4. 执行偏差记录
1. 引擎 `--target` 首次启用时的两个缺陷及修复（批次 0 内完成）：(a) 补丁未生效导致 6 文件先落 core 再迁 ui_common；(b) `os.path.join` 反斜杠路径喂 `posixpath.relpath` 产生畸形 URI，153 处已修复。两处修复均有验证（畸形 URI 清零、analyze 0 error）。
2. `l10n.yaml` 在仓库根，不在引擎 lib/ 约束内，手工 `git mv`；其余 8 文件走引擎。
3. 批次 D 采用"语义筛选（禁播放器/大屏焦点设施/dashboard/dialog）+ 引擎闭包预检"双裁决：59 个启发式候选仅 10 个入选；history_like_list_card（依赖大屏焦点组件）、settings_slider（依赖 app_accent_color）、tooltip 系（依赖 player_menu_theme）被排除。
4. B/C/D 三批以 analyze 逐批门禁 + 合并全量测试验收，合并为一个 commit（文件集不相交，app 侧改写无法按批拆分）。
5. B/C/D 全量测试出现 1 个新失败：`unified_app_architecture_test`（源码扫描 `lib/media_library/media_source_option.dart` 路径，批次 B 搬移后失效）——已把扫描路径更新为 ui_common 新位置，该文件 63/63 全绿。全仓库已扫确认无其他残留字符串路径引用。

## 5. 结论
阶段二达成：显示面契约 + l10n + 纯模型 + 自包含 widgets/themes 底料进入 `nipaplay_ui_common`，零 app 反向依赖；焦点/手势与 app 态组件按规则留各版本。阶段三（TV 应用新建）现在可以：依赖 nipaplay_core（逻辑）+ nipaplay_ui_common（契约/本地化/基础组件），自建 TV 专属的焦点导航、设置瓦片、媒体库 primitives、播放器 overlay。
