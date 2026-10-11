# nipaplay_core 抽取盘点（Phase 1）

> 生成时间：2026-10-12 ｜ 仓库：`NipaPlay-Reload-features`（branch `nipaplay`，基线 commit 见 git log）
> 结论先行：**本阶段只搬"无 UI 依赖且不在依赖环上"的文件**；含 Widget 的文件原地不动；4 处循环依赖只记录链路，等待人工决策。

## 1. 范围与决策记录

### 1.1 core 依赖红线（check_core_purity.sh 强制执行）
- `packages/nipaplay_core` 的 pubspec 禁止：`flutter/material`、`flutter/cupertino`、`fluent_ui` 等一切 UI 包。
- core 源码禁止 import：`package:flutter/material.dart`、`widgets.dart`、`cupertino.dart`、`rendering.dart`、`painting.dart`、`animation.dart`。
- core 源码**允许** import（"非 UI 运行时"白名单）：
  - `package:flutter/foundation.dart`（ChangeNotifier / ValueListenable / debugPrint / compute / kIsWeb / @immutable）
  - `package:flutter/services.dart`（MethodChannel / rootBundle，平台通道非 UI）
  - `dart:ui` 仅限几何/颜色值类型（Rect / Size / Offset / Color），禁止 Canvas / TextPainter / Window
  - 非 UI 插件：shared_preferences、path_provider、http、dio、xml、uuid、crypto、sqflite(+ffi)、shelf*、webdav_client、smb_connect、ffi、flutter_rust_bridge、rust_lib_nipaplay、dart_ipc、charset* 等
- 理由：四个播放器内核依赖平台通道/FFI，纯 Dart core 不可行；红线的精神是"core 不含任何 Widget/渲染代码"。

### 1.2 对播放器统一接口模板的两处调整（偏差声明）
用户模板中 `Widget buildVideoSurface()` 与全局约束 3（core 禁 UI）冲突，按约束 3 优先处理：
1. `NipaPlayer.buildVideoSurface()` → `NipaPlayerSurface createSurfaceHandle()`，`NipaPlayerSurface` 是不透明描述符（textureId / 平台视图 id / kind）。UI 侧（现 app、未来 ui_common）负责把描述符包成 Widget。
2. 模板的 `TargetPlatform` 用 core 自有枚举 `NipaTargetPlatform`（android/ios/windows/macos/linux/web/ohos/tvos），避免 core API 出现 Flutter 类型；app 侧做映射。
接口与其余方法（initialize/load/play/pause/seek/stateStream/positionStream/dispose/capabilities、PlayerFactory.create/supportsPlatform/priority）与模板一致。

### 1.3 判定方法
三个并行扫描（播放器内核 / 服务与模型 / 弹幕与平台能力）逐文件判定：UI 依赖（material/widgets/cupertino/rendering/painting/dart:ui、Widget/BuildContext）、第三方包、项目内依赖、反向依赖。watch_history 模型环、smb 环等以 grep 双向 import 实锤。

## 2. 目标结构

```
packages/nipaplay_core/
  pubspec.yaml            # name: nipaplay_core，依赖=白名单内
  lib/
    nipaplay_core.dart    # barrel：公开 API（模型、播放器接口、解析器）
    src/
      models/             # ← lib/models/**（可搬子集）
      constants/          # ← lib/constants/**
      utils/              # ← lib/utils/**（可搬子集）
      services/           # ← lib/services/**（可搬子集）
      player/             # ← lib/player_abstraction/**（可搬子集）+ 新接口 nipa_player.dart
      danmaku/            # ← 弹幕解析/桥接
      platform/           # ← lib/cpp_native/**（FFI 绑定）
      rust/               # ← lib/src/rust/**（frb 生成绑定，Batch 5）
```
搬移方式：`git mv`，目录结构在 core 内保持同形（`lib/models/x.dart` → `packages/nipaplay_core/lib/src/models/x.dart`），文件间相对 import 不需改写。app 内所有引用改写为 `package:nipaplay_core/...`。

## 3. 分批搬移清单

> 每批 = 一次独立验证（flutter analyze lib test 0 error + flutter test 全绿）+ 一次 git commit。
> 每批执行前由 `docs/refactor/tools/check_batch.py` 重新校验待搬文件的 import 闭包，若发现新的 UI 依赖或环，该文件降级留观并记录。

### Batch 1 — 数据模型 + 常量 + 纯工具（~34 文件，全部零 flutter import 或仅 foundation）
| 当前路径 (lib/) | 目标 (core src/) | 依赖 | 被谁依赖（量级） |
|---|---|---|---|
| models/anime_detail_display_mode.dart | models/ | 无 | UI 少量 |
| models/background_image_render_mode.dart | models/ | 无 | UI 少量 |
| models/bangumi_collection_submit_result.dart | models/ | 无 | services 1 |
| models/bangumi_comment_model.dart | models/ | 无 | services/UI 少量 |
| models/bangumi_model.dart | models/ | 无 | 大量（services/UI） |
| models/dandanplay_remote_model.dart | models/ | dart:convert | services 3 |
| models/danmaku/blocked_item.dart | models/danmaku/ | 无 | settings/UI |
| models/danmaku/danmaku_item.dart | models/danmaku/ | constants | 大量 |
| models/danmaku/style.dart | models/danmaku/ | 无 | 大量 |
| models/danmaku_auto_load_strategy.dart | models/ | 无 | settings/UI |
| models/database/anime_episode_relation.dart | models/database/ | 无 | database 服务 |
| models/media_identity.dart | models/ | dart:convert | webdav/media 服务 |
| models/media_server_playback.dart | models/ | 无 | emby/jellyfin 服务 |
| models/search_model.dart | models/ | 无 | services 2 |
| models/server_profile_model.dart | models/ | 无 | multi_address/backup |
| models/jellyfin_transcode_settings.dart | models/ | 无 | transcode 服务 |
| models/torrent_magnet_preview.dart | models/ | path | torrent 服务 |
| models/torrent_task.dart | models/ | path | torrent 服务 |
| models/trending_bangumi.dart | models/ | bangumi_model | services 1 |
| services/emby_media_selection.dart | services/（模型性质，随批 1） | 无 | emby 组 5 文件 |
| services/emby_media_source_catalog.dart | services/ | emby_media_selection | emby 组 |
| services/emby_media_selection_resolver.dart | services/ | emby_media_selection+release_parser | emby 组 |
| services/emby_release_name_parser.dart | services/ | emby_media_selection | emby 组 |
| services/media_server_playback_client.dart | services/ | transcode_settings+playback | sync 服务 |
| services/backup_category.dart | services/ | 无 | sync/backup 组 |
| services/incremental_sync_webdav_connections.dart | services/ | 无 | sync 组 |
| services/app_http_proxy.dart | services/ | 无（纯内存静态） | player_factory/proxy |
| services/process_memory_cache.dart | services/ | 无 | webdav/smb |
| constants/acknowledgements.dart | constants/ | 无 | about 页 |
| constants/danmaku/ass_kind.dart | constants/danmaku/ | 无 | ass 转换 |
| constants/danmaku/mode.dart | constants/danmaku/ | 无 | 弹幕引擎全家 |
| constants/media_extensions.dart | constants/ | 无 | file_picker/scan |
| constants/settings_keys.dart | constants/ | 无 | 大量（prefs 键） |
| utils/http_header_utils.dart | utils/ | 无 | dandanplay 客户端 |
| utils/http_user_agent.dart | utils/ | 无 | transport |
| utils/legacy_charset_decoder.dart | utils/ | charset/cp949/enough_convert | 弹幕解析 |
| utils/frame_rate_sampler.dart | utils/ | 无 | 播放信息 |
| utils/build_info_types.dart | utils/ | 无 | build_info |

**同批不搬**：emby_model/jellyfin_model/playable_item/playback_detail_context/torrent_task_scan_summary（传递依赖 watch_history_model，见 §5 环 1）；watch_history_model/watch_history_database（环 1）；shared_remote_library（→ Batch 4，依赖 web_remote_access_service）；external_player_session/*（→ Batch 5，依赖 src/rust）。

### Batch 2 — 播放器抽象基座 + 统一接口（~12 文件 + 2 新文件）
| 当前路径 (lib/) | 目标 (core src/) | 依赖 | 备注 |
|---|---|---|---|
| player_abstraction/player_enums.dart | player/ | 无 | 纯 |
| player_abstraction/player_data_models.dart | player/ | dart:typed_data | 纯 |
| player_abstraction/hwdec_type.dart | player/ | 无 | 硬解枚举 |
| player_abstraction/abstract_player.dart | player/ | foundation | ValueListenable |
| player_abstraction/erika_gif_export.dart | player/ | 条件导出 | |
| player_abstraction/erika_gif_export_io.dart | player/ | ffi | 纯 FFI |
| player_abstraction/erika_gif_export_stub.dart | player/ | 无 | |
| utils/mock_mdk.dart | player/ | 无 | Web mock |
| utils/mpv_utils.dart | utils/ | foundation | mpv 日志路径 |
| utils/video_aspect_geometry.dart | player/ | dart:ui(Rect) | 几何计算 |
| utils/anime4k_shader_manager.dart | player/ | services+path_provider | 读 asset |
| utils/crt_shader_manager.dart | player/ | services+path_provider | 读 asset |
| **新文件** nipa_player.dart | player/ | — | 统一接口（§1.2） |
| **新文件** player_capabilities.dart | player/ | — | PlayerCapabilities/PlayerConfig/MediaSource/PlayerState |

**同批不搬**（原地，依赖注入化后再评估）：
- `player_factory.dart`（环 2 + 依赖 utils/globals）
- 四内核适配器 media_kit/mdk/video_player（依赖 utils/subtitle_font_loader、storage_service、watch_history_database 等 app 层；media_kit 适配器 4050 行且 widgets import 疑似冗余，待清理）
- `erika_player_adapter.dart`（含 StatefulWidget 窗口覆盖层）
- `player_abstraction.dart` facade（`buildPlatformVideoSurface` 返回 Widget → surface 拆分后评估）
- `lazy_player_delegate.dart`（import player_factory，随工厂留观）
- `decoder_manager.dart`、`audio_track_manager.dart`、`subtitle_manager.dart`、`subtitle_parser.dart`、`player_kernel_manager.dart`（依赖 player_abstraction facade/环）

### Batch 3 — 弹幕引擎(解析/布局桥) + C++ FFI 绑定（~45 文件）
| 当前路径 (lib/) | 目标 (core src/) | 备注 |
|---|---|---|
| cpp_native/**（35 文件，除下列 3 个外纯 ffi/io） | platform/cpp_native/** | danmaku_layout / danmaku_parser / similarity_engine / subtitle_parser / native_library / native_arena |
| cpp_native/bindings/danmaku_parser_io.dart | 同上 | 仅 foundation debugPrint，允许 |
| cpp_native/bindings/similarity_engine_io.dart | 同上 | 同上 |
| cpp_native/bindings/subtitle_parser_io.dart | 同上 | 同上（另依赖 danmaku_next_log，纯） |
| utils/danmaku_parser.dart | danmaku/ | 纯 isolate 解析 |
| utils/danmaku_xml_utils.dart | danmaku/ | xml 包 + cpp_native |
| utils/danmaku/style.dart | danmaku/ | 纯 |
| danmaku_abstraction/danmaku_content_item.dart | danmaku/ | material→dart:ui 清理后搬（仅 Color 级符号，逐行核对） |
| danmaku_abstraction/positioned_danmaku_item.dart | danmaku/ | 依赖 content_item |
| constants/danmaku_color_presets.dart | constants/ | material Color→dart:ui 清理后搬 |

**同批不搬**：danmaku_abstraction 的 text_renderer/globals 污染文件、kernel_factory（prefs+plugins）；danmaku_next/danmaku_gpu/danmaku_dfm 全部渲染与 overlay；danmaku_canvas 包（另有 models+timeline 纯文件，留原包）；`services/danmaku/danmaku_service.dart`（video_player_state 污染）；danmaku_density_analyzer（UI 图表泄漏）。

### Batch 4 — 网络基座 / 设置存储 / 主机发现（~20 文件，foundation+http+prefs）
| 当前路径 (lib/) | 目标 (core src/) | 依赖 |
|---|---|---|
| services/certificate_trust_service.dart | services/ | crypto+prefs |
| services/system_proxy_service.dart | services/ | dart:io |
| services/http_overrides_io.dart / _web.dart | services/ | dart:io |
| services/http_client_initializer.dart | services/ | 上述三件 |
| services/media_server_transport.dart (+client_io/stub) | services/ | http+prefs+constants |
| services/nipaplay_lan_discovery.dart | services/ | dart:io（主机发现） |
| services/nipaplay_server_router.dart | services/ | http+prefs+network_settings |
| services/web_remote_access_service.dart | services/ | http+prefs |
| services/playback_position_store.dart | services/ | prefs |
| services/remote_control_settings.dart | services/ | prefs |
| services/media_server_device_id_service.dart | services/ | prefs+uuid |
| utils/network_settings.dart | utils/ | prefs（执行前核对） |
| utils/settings_storage.dart | utils/ | prefs（执行前核对） |
| models/shared_remote_library.dart | models/ | web_remote_access_service（本批到位） |
| utils/file_hash.dart | utils/ | crypto+http+src/rust → 若 src/rust 未到位则留观 |

**同批不搬**：debug_log_service（WidgetsBinding 耦合，清理后下阶段）；multi_address_server_service、file_log_service_io、danmaku_cache_manager、backup_service、subtitle_service 等（依赖 debug_log/storage_service，视 storage_service 核对结果决定是否本批跟随）。

### Batch 5 — Rust FFI 绑定 + WebDAV 客户端（~45 文件）
| 当前路径 (lib/) | 目标 (core src/) | 备注 |
|---|---|---|
| src/rust/**（~9139 行 frb 生成） | rust/ | core 增加依赖 flutter_rust_bridge + rust_lib_nipaplay（path ../rust_builder） |
| services/webdav_service.dart | services/ | WebDAV 客户端：webdav_client+dio+http+xml+uuid+prefs+src/rust(webdav_multistatus) |
| utils/danmaku_ass_converter.dart | danmaku/ | src/rust(ass_converter) |
| utils/external_player_danmaku_ass.dart | danmaku/ | src/rust(dfm_plus) |
| services/rust_file_scan_service.dart | services/ | src/rust |
| services/incremental_sync_native_codec.dart | services/ | crypto+src/rust |
| models/external_player_session/**（7 文件） | models/external_player_session/ | dart_ipc+ffi+ass 转换器 |

**同批不搬**：dandanplay_service_io（依赖 app 层 web_remote/network_settings/remote_media_fetcher 等大量服务网）。

## 4. 明确不搬（含 Widget / UI 语义，留在各版本）
- `lib/utils/video_player_state.dart` + 14 个 part（约 1.45 万行播放器状态上帝类：material/cupertino/rendering + blur_* 组件 + BuildContext）
- `lib/pages/`、`lib/widgets/`、`lib/themes/`、`lib/player_menu/`、`lib/controllers/` 全部
- services 中 23 个 UI 污染文件：emby/jellyfin_dandanplay_matcher、desktop_exit_handler、desktop_player_window_service、external_player_*、playback_service、playback_source_service、player_remote_control_bridge、remote_access_qr_service、manual_danmaku_matcher、auto_next_episode_service 等（详见扫描报告）
- providers/ 全部 20 个（ChangeNotifier 应用态属于宿主 app；13 个干净 provider 若 TV 版需要，届时评估）
- utils/globals.dart（material + GlobalKey<NavigatorState> + plugin_service，反向依赖重灾区）
- danmaku 渲染层：danmaku_gpu 全部、danmaku_next 的 painter/overlay/atlas、danmaku_dfm/dfm_plus_overlay、danmaku_canvas 的 screen/painter
- 插件系统 plugin_service.dart 本体（blur_snackbar UI 泄漏）；`plugins/js_runtime_*` 的 PluginJsRuntime 抽象（js_runtime_types.dart）可随下阶段进 core，OHOS/JSC 冲突处理实现留平台层

## 5. 依赖循环链路（约束 6：只记录，等待人工决策）
1. **models 环**：`watch_history_model.dart` ⇄ `watch_history_database.dart`（1118 行 ⇄ 1288 行互相 import）。解锁方案（供决策）：拆出纯数据类 vs 抽 repository 接口。
2. **工厂环**：`player_abstraction/player_factory.dart` → `utils/system_resource_monitor.dart` → `player_abstraction/player_factory.dart`。连带 `utils/player_kernel_manager.dart` ⇄ `utils/video_player_state.dart`。
3. **services 内环**：`smb_service.dart` → barrel `smb2_native_service.dart` → `smb2_native_service_ffi/stub.dart` → 反向 import `smb_service.dart`（取凭据）。
4. **跨层环**：`services/web_server_service.dart` → `web_api_service.dart` → `providers/service_provider.dart`（静态组合根）→ 回 web_server_service；以及 models→services 反向（watch_history_database→smb/webdav_service、watch_history_model→auto_sync_service）。

## 6. 每批验证门（gate）
1. `flutter analyze lib test`：**error 数必须保持 0**（基线 0；warning/info 不作为门，记录差值即可）。
2. `flutter test`：与基线相同的通过/失败集合（基线结果见 logs/baseline_test_build.log）。
3. `check_core_purity.sh`：core 无 UI import（Batch 2 起每批执行）。
4. 批次末尾 `git commit`，提交信息注明批次号与搬移文件数。
5. 全部批次完成后：`flutter build windows --debug` 与基线构建结果一致（成功）。

## 7. 风险与回滚
- 每批独立 commit，任何一批失败可 `git revert` 单批。
- import 改写由脚本完成并以 analyze 验证，不手工逐文件改。
- 搬移不改任何逻辑代码（除 §Batch3 两处 material→dart:ui 的 import 级清理，逐行核对符号）。
