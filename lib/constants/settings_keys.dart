class SettingsKeys {
  SettingsKeys._();

  static const String appLanguageMode = 'app_language_mode';

  static const String clearDanmakuCacheOnLaunch =
      'clear_danmaku_cache_on_launch';

  static const String autoMatchDanmakuFirstSearchResultOnHashFail =
      'danmaku_auto_match_first_search_result_on_hash_fail';

  static const String autoMatchDanmakuOnPlay = 'danmaku_auto_match_on_play';

  static const String danmakuAutoLoadStrategy = 'danmaku_auto_load_strategy';


  // =========================== 外部播放器相关设置 ============================

  static const String useExternalPlayer                        = 'external_player_enabled';                        // 是否启用外部播放器
  static const String externalPlayerPath                       = 'external_player_path';                           // 外部播放器路径
  static const String externalPlayerDanmakuOverlay             = 'external_player_danmaku_overlay';                // 外部播放器弹幕外挂开关 (ASS 字幕注入)
  static const String externalPlayerAutoSwitchToDanmakuConsole = 'external_player_auto_switch_to_danmaku_console'; // 启动外部播放器后自动切换到弹幕控制台


  /// 自定义播放器请求视频的 User-Agent（空字符串 = 用内核默认 UA）。
  static const String customPlayerUA = 'custom_player_ua';

  static const String autoCheckUpdatesInBackground =
      'auto_check_updates_in_background';

  static const String legacyAutoCheckUpdatesOnAboutPage =
      'auto_check_updates_on_about_page';

  static const String showRemoteAccessQrCode = 'show_remote_access_qr_code';

  static const String labsEnableLargeScreenMode =
      'labs_enable_large_screen_mode';

  static const String labsShowRemoteAccessQrCode =
      'labs_show_remote_access_qr_code';

  static const String labsEnableErikaPlayerKernel =
      'labs_enable_erika_player_kernel';

  static const String danmakuEnableNextPlusPlusEngine =
      'labs_enable_next_plus_plus_engine';

  static const String torrentDownloadDirectory = 'torrent_download_directory';

  static const String torrentRecentDownloadDirectories =
      'torrent_recent_download_directories';

  static const String torrentRecentDownloadDirectoriesMigrated =
      'torrent_recent_download_directories_migrated';

  static const String mediaLibrarySelectedSection =
      'media_library_selected_section';

  static const String downloaderEnabled = 'downloader_enabled';

  static const String downloaderCreateFolderForTask =
      'downloader_create_folder_for_task';

  static const String downloaderAutoScanCompletedTasks =
      'downloader_auto_scan_completed_tasks';

  static const String downloaderAutoScannedCompletedTaskKeys =
      'downloader_auto_scanned_completed_task_keys';

  static const String githubProxyUrl = 'github_proxy_url';

  static const String danmakuSupersample = 'danmaku_supersample';


  // ===========================================================================
  // ============================ 弹幕相关设置 =================================
  // ===========================================================================

  // 弹幕基本设置
  static const String danmakuOpacity                    = 'danmaku_opacity';                        // 透明度设置
  static const String danmakuOutlineStyle               = 'danmaku_outline_style';                  // 描边样式设置
  static const String danmakuVisible                    = 'danmaku_visible';                        // 可见性设置
  static const String mergeDanmaku                      = 'merge_danmaku';                          // 合并设置
  static const String danmakuStacking                   = 'danmaku_stacking';                       // 堆叠设置
  static const String danmakuRandomColorEnabled         = 'danmaku_random_color_enabled';           // 随机颜色设置
  static const String blockTopDanmaku                   = 'block_top_danmaku';                      // 屏蔽设置
  static const String blockBottomDanmaku                = 'block_bottom_danmaku';                   // 屏蔽设置
  static const String blockScrollDanmaku                = 'block_scroll_danmaku';                   // 屏蔽设置
  static const String timelineDanmakuEnabled            = 'timeline_danmaku_enabled';               // 时间轴弹幕设置
  static const String danmakuBlockWords                 = 'danmaku_block_words';                    // 弹幕屏蔽词设置
  static const String danmakuFontSize                   = 'danmaku_font_size';                      // 字体大小设置
  static const String danmakuFontFilePath               = 'danmaku_font_file_path';                 // 字体文件路径设置
  static const String danmakuFontFamily                 = 'danmaku_font_family';                    // 字体族设置
  static const String danmakuShadowStyle                = 'danmaku_shadow_style';                   // 阴影样式设置
  static const String next2DanmakuOutlineWidth          = 'next2_danmaku_outline_width';            // 描边宽度设置
  static const String danmakuDisplayArea                = 'danmaku_display_area';                   // 显示区域设置
  static const String danmakuSpeedMultiplier            = 'danmaku_speed_multiplier';               // 速度倍数设置
  static const String danmakuDfmPlusTrackGap            = 'danmaku_dfm_plus_track_gap';             // 轨道间距设置
  static const String rememberDanmakuOffset             = 'remember_danmaku_offset';                // 记住偏移设置
  static const String danmakuConvertToSimplified        = 'danmaku_convert_to_simplified';          // 简繁转换设置
  static const String danmakuRenderEngine               = 'danmaku_render_engine';                  // 渲染引擎设置
  static const String legacyDanmakuKernel               = 'danmaku_kernel';                         // 内核设置（已废弃，保留用于迁移旧设置）
  static const String showDanmakuDensityChart           = 'show_danmaku_density_chart';             // 密度图设置
  static const String playerTopSendDanmakuButtonVisible = 'player_top_send_danmaku_button_visible'; // 播放器顶部发送按钮可见性设置

  // 弹幕防剧透设置
  static const String spoilerPreventionEnabled          = 'spoiler_prevention_enabled';
  static const String spoilerAiUseCustomKey             = 'spoiler_ai_use_custom_key';
  static const String spoilerAiApiFormat                = 'spoiler_ai_api_format';
  static const String spoilerAiApiUrl                   = 'spoiler_ai_api_url';
  static const String spoilerAiApiKey                   = 'spoiler_ai_api_key';
  static const String spoilerAiModel                    = 'spoiler_ai_model';
  static const String spoilerAiTemperature              = 'spoiler_ai_temperature';
  static const String spoilerAiDebugPrintResponse       = 'spoiler_ai_debug_print_response';

  // 弹幕开发调试设置
  static const String showCanvasDanmakuCollisionBoxes   = 'show_canvas_danmaku_collision_boxes';
  static const String showCanvasDanmakuTrackNumbers     = 'show_canvas_danmaku_track_numbers';
  static const String showGpuDanmakuCollisionBoxes      = 'show_gpu_danmaku_collision_boxes';
  static const String showGpuDanmakuTrackNumbers        = 'show_gpu_danmaku_track_numbers';

}
