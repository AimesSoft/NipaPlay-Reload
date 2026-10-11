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

// ---- 批次 A: l10n 本地化层 ----
export 'l10n/l10n.dart';
export 'l10n/app_locale_utils.dart';
export 'l10n/app_localizations.dart';

// ---- 批次 B: 纯模型/存储 ----
export 'media_library/media_source_option.dart';
export 'media_library/media_library_section_order_store.dart';
export 'media_library/unified_library_management_model.dart';
export 'settings/unified_setting_content_type.dart';
export 'settings/adaptive_settings_scope.dart';
export 'settings/about_settings_data.dart';
export 'playback/unified_playback_entry_model.dart';

// ---- 批次 C: widgets 干净件 ----
export 'widgets/about_version_banner_text.dart';
export 'widgets/adaptive_markdown.dart';
export 'widgets/danmaku_density_chart.dart';
export 'widgets/in_view_dialog.dart';
export 'widgets/intro_skip_button.dart';
export 'widgets/desktop_picture_in_picture_scope.dart';
export 'widgets/user_activity/user_activity_view_model.dart';

// ---- 批次 D: themes 通用底料 ----
export 'themes/theme_ids.dart';
export 'themes/nipaplay/widgets/typing_text.dart';
export 'themes/nipaplay/widgets/bounce_hover_scale.dart';
export 'themes/nipaplay/widgets/transparent_page_route.dart';
export 'themes/nipaplay/widgets/control_shadow.dart';
export 'themes/nipaplay/widgets/custom_refresh_indicator.dart';
export 'themes/nipaplay/widgets/settings_no_ripple_theme.dart';
export 'themes/nipaplay/widgets/large_screen_mode_scope.dart';
export 'themes/nipaplay/widgets/settings_hint_text.dart';
export 'themes/nipaplay/widgets/ui_scale_wrapper.dart';
