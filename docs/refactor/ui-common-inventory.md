# nipaplay_ui_common 抽取盘点（Phase 2）

> 生成时间：2026-10-12 ｜ 基于 HEAD 6469bea0（阶段一完成后）
> 硬规则（用户明令）：**含焦点（Focus/FocusNode/Keyboard）或手势（GestureDetector/Listener/onPointer）逻辑的组件一律留在各版本**；ui_common 禁止 import `package:nipaplay/...`、globals、providers、plugins。

## 1. 判定口径
- **A 可搬**：依赖 ⊆ flutter + nipaplay_core + 第三方，无焦点/手势
- **B 清理后可搬**：需参数化 globals 读取或抽接口（本阶段暂不动，留给 TV 阶段按需处理）
- **C 禁搬**：焦点/手势命中、app 态胶水（providers/services/pages）、平台/外观专属

## 2. 搬移批次（执行计划）

### 批次 0 — 显示面契约（钥匙批）
`lib/app/` 的 6 个 A 级文件，178 行，**50+ 文件引用**（全库渗透最广的抽象）：
`app_display_surface.dart`(5, 枚举)、`app_display_surface_scope.dart`(24, InheritedWidget)、`app_navigation_scope.dart`(32)、`app_page_component.dart`(19)、`app_page_ids.dart`(61)、`unified_app_actions.dart`(37)。
落位：`packages/nipaplay_ui_common/lib/app/`（保持同形）。

### 批次 A — l10n 整体（生成层，零 app 依赖，实测确认）
`lib/l10n/` 8 文件（3 个 arb：zh 模板 1001 行 / zh_Hant 601 / en 989；生成 app_localizations*.dart 共 9670 行；手写 l10n.dart + app_locale_utils.dart）+ `l10n.yaml`。
落位：`packages/nipaplay_ui_common/lib/l10n/`，l10n.yaml 随包。app pubspec 移除 `generate: true`，ui_common 加 `generate: true` 并在包内 gen。43 个消费方 import 改写。

### 批次 B — 纯模型/存储（7 文件 ~384 行）
`media_library/media_source_option.dart`(100, 零 import)、`media_library/media_library_section_order_store.dart`(101, core)、`media_library/unified_library_management_model.dart`(65, widgets)、`settings/unified_setting_content_type.dart`(19, 纯枚举)、`settings/adaptive_settings_scope.dart`(32, InheritedWidget)、`settings/about_settings_data.dart`(12, core)、`playback/unified_playback_entry_model.dart`(51, foundation)。

### 批次 C — widgets 干净件（7 文件 ~675 行）
`about_version_banner_text`(62)、`adaptive_markdown`(105, flutter_markdown)、`danmaku_density_chart`(304)、`in_view_dialog`(85)、`intro_skip_button`(40)、`desktop_picture_in_picture_scope`(25, InheritedWidget)、`user_activity/user_activity_view_model.dart`(29)。
（context_menu 整组为桌面专属，虽 widgets 文件自身干净，保持模块完整不拆——留 app。）

### 批次 D — themes A 级底料（启发式扫描 + 引擎闭包预检过滤）
已验证 A 级：`typing_text`(110)、`bounce_hover_scale`(71)、`transparent_page_route`(41)、`control_shadow`(102)、`custom_refresh_indicator`(201, glassmorphism)、`settings_no_ripple_theme`(61)、`large_screen_mode_scope`(23)。
另对 `themes/nipaplay/widgets/` 全量做启发式预筛（禁 globals/providers/services/plugins/pages/video_player_state/player_menu 焦点/手势符号），候选交给 move_batch.py 闭包预检最终裁决。

### B 级候选（本阶段不执行，TV 阶段按需）
`embedded_subtitle_overlay`(199, 需播放状态接口)、`danmaku_group_widget`(188, globals 参数化)、`single_danmaku`(216, 需 renderer 接口上移)、`media_server_network_image`(376, 图片加载器注入)、`tv_safe_blur`/`responsive_container`/`loading_placeholder`(参数化)、`switchable_view`(344, 断开 custom_scaffold)、`unified_torrent_page_model`(243, 需 torrent_task_scan_summary 先解 watch_history 环)、`unified_media_library_sections`+`media_collection_empty_content`(需 watch_history_model 解环)。

## 3. 明确不搬清单（C，留各版本）
- **焦点/手势命中**：adaptive_media_library_primitives(1123)、adaptive_media_library_controls(1162)、adaptive_playback_entry_view(619)、external_subtitle_overlay(1358)、adaptive_settings_widgets(1270)、adaptive_library_management_overview、macos_native_video_view、desktop_transient_overlay、context_menu_controller、airplay_route_picker、desktop_user_activity
- **app 态胶水**：settings 全部内容页(20 个约 13.3k 行) + unified_settings_entries(694) + unified_setting_content + unified_settings_page + media_library 的 page/controls/collection_view/add_media_flow + unified_home_components + adaptive_app_page_content + unified_app_pages + unified_app_view_presenter + unified_app_virtual_windows
- **播放态/内核耦合**：danmaku_overlay、danmaku_container(1147)、vertical_indicator、minimal_progress_bar、indicator_widget、player_menu/* 全部(576 行)
- **平台/外观专属**：cupertino/ 整目录(60 文件)、macos_platform_menu、desktop_player_page_slot、emby_media_source_selector、theme_registry、user_activity 的 cupertino/desktop 版
- **逻辑层（归 core）**：controllers/user_activity_controller、search/tag_search_controller

## 4. 反向依赖规模（改写工作量依据）
`package:nipaplay/app/` 66 文件、`package:nipaplay/l10n/` 43 文件、`package:nipaplay/media_library/` 35 文件、adaptive_settings_widgets 21 文件（留 app 不动其消费方）。

## 5. 验证门（与阶段一同口径）
1. `flutter analyze`：lib/test error 0
2. `flutter test`：失败集合 ⊆ 阶段一后的 6 项基线预存
3. `scripts/check_ui_common_purity.sh`：ui_common 无 `package:nipaplay/` import、无 globals/providers/plugins 依赖
4. 每批独立 commit
