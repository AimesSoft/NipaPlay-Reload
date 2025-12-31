class SettingsKeys {
  SettingsKeys._();

  static const String clearDanmakuCacheOnLaunch =
      'clear_danmaku_cache_on_launch';

  static const String autoMatchDanmakuFirstSearchResultOnHashFail =
      'danmaku_auto_match_first_search_result_on_hash_fail';

  /// 开发调试：Web 远程访问使用外部 Web UI（反向代理到本机端口）
  static const String devRemoteAccessWebUiPort = 'dev_remote_access_webui_port';
}
