// nipaplay_core — 逻辑层公共出口。
// 红线：本包禁止 import 任何 UI 包（material/cupertino/widgets/rendering/painting）。
// 允许：flutter/foundation、flutter/services、dart:ui 几何值类型、非 UI 插件。
// 每搬一批在此追加对应 export（也供 scripts/check_core_purity.sh 校验）。

// ---- Batch 1: models / constants / pure utils ----
export 'models/anime_detail_display_mode.dart';
export 'models/background_image_render_mode.dart';
export 'models/bangumi_collection_submit_result.dart';
export 'models/bangumi_comment_model.dart';
export 'models/bangumi_model.dart';
export 'models/dandanplay_remote_model.dart';
export 'models/danmaku/blocked_item.dart';
export 'models/danmaku/danmaku_item.dart';
export 'models/danmaku/style.dart';
export 'models/danmaku_auto_load_strategy.dart';
export 'models/database/anime_episode_relation.dart';
export 'models/emby_media_selection.dart';
export 'models/jellyfin_transcode_settings.dart';
export 'models/media_identity.dart';
export 'models/media_server_playback.dart';
export 'models/search_model.dart';
export 'models/server_profile_model.dart';
export 'models/torrent_magnet_preview.dart';
export 'models/torrent_task.dart';
export 'models/trending_bangumi.dart';
export 'services/app_http_proxy.dart';
export 'services/backup_category.dart';
export 'services/emby_media_preference_store.dart';
export 'services/emby_media_selection_controller.dart';
export 'services/emby_media_selection_resolver.dart';
export 'services/emby_media_source_catalog.dart';
export 'services/emby_media_source_selection.dart';
export 'services/emby_release_name_parser.dart';
export 'services/incremental_sync_webdav_connections.dart';
export 'services/media_server_playback_client.dart';
export 'services/process_memory_cache.dart';
export 'constants/acknowledgements.dart';
export 'constants/danmaku/ass_kind.dart';
export 'constants/danmaku/mode.dart';
export 'constants/media_extensions.dart';
export 'constants/settings_keys.dart';
export 'utils/frame_rate_sampler.dart';
export 'utils/http_header_utils.dart';
export 'utils/http_user_agent.dart';

// ---- Batch 2: player abstraction base + unified interface ----
export 'player_abstraction/abstract_player.dart';
export 'utils/anime4k_shader_manager.dart';
export 'utils/crt_shader_manager.dart';
export 'player_abstraction/erika_gif_export.dart';
export 'player_abstraction/hwdec_type.dart';
export 'utils/mock_mdk.dart';
export 'utils/mpv_utils.dart';
export 'player/nipa_player.dart';
export 'player_abstraction/player_data_models.dart';
export 'player_abstraction/player_enums.dart';
export 'utils/video_aspect_geometry.dart';

// ---- Batch 3: danmaku parsing / cpp_native FFI bindings ----
export 'cpp_native/nipaplay_native.dart';
export 'danmaku_abstraction/danmaku_content_item.dart';
export 'danmaku_abstraction/positioned_danmaku_item.dart';
export 'constants/danmaku_color_presets.dart';
export 'utils/danmaku_parser.dart';
export 'utils/danmaku/style.dart';
export 'utils/danmaku_xml_utils.dart';
export 'utils/legacy_charset_decoder.dart';

// ---- Batch 4: network foundation / settings storage / host discovery ----
export 'models/shared_remote_library.dart';
export 'services/certificate_trust_service.dart';
export 'services/http_client_initializer.dart';
export 'services/media_server_device_id_service.dart';
export 'services/media_server_transport.dart';
export 'services/nipaplay_lan_discovery.dart';
export 'services/nipaplay_server_router.dart';
export 'services/playback_position_store.dart';
export 'services/remote_control_settings.dart';
export 'services/system_proxy_service.dart';
export 'services/web_remote_access_service.dart';
export 'utils/network_settings.dart';
export 'utils/settings_storage.dart';
