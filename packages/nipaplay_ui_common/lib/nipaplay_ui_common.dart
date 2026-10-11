// nipaplay_ui_common — 手机版与 TV 版共用的 UI 层公共出口。
// 红线：本包禁止 import `package:nipaplay/...`（app 本体）、globals、providers、plugins。
// 允许：flutter SDK、package:nipaplay_core、第三方包。
// 每搬一批在此追加对应 export（也供 scripts/check_ui_common_purity.sh 校验）。

// ---- 批次 0: 显示面契约 ----
export 'app/app_display_surface.dart';
export 'app/app_display_surface_scope.dart';
export 'app/app_navigation_scope.dart';
export 'app/app_page_component.dart';
export 'app/app_page_ids.dart';
export 'app/unified_app_actions.dart';
