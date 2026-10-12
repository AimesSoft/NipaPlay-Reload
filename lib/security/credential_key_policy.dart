abstract final class CredentialKeyPolicy {
  static const scalarKeys = {
    'dandanplay_token',
    'dandanplay_app_secret',
    'bangumi_access_token',
    'dandanplay_remote_api_token',
    'incremental_sync_webdav_password',
    'emby_access_token',
    'jellyfin_access_token',
    'spoiler_ai_api_key',
  };
  static const compositeKeys = {
    'webdav_connections': 'password',
    'smb_connections': 'password',
    'server_profiles': 'accessToken',
  };
  static bool isSecretKey(String key) =>
      key != 'plugin_enabled_ids' &&
      key != 'plugin_downloader_override' &&
      key != 'last_token_renew_time' &&
      key != 'dandanplay_remote_token_required' &&
      !key.startsWith('plugin_switch_setting_') &&
      (scalarKeys.contains(key) ||
          key.startsWith('credential_vault_') ||
          RegExp(r'password|passwd|token|secret|api[\s_-]?key|cookie|authorization|密码|密碼|密钥|密鑰|令牌|憑證|凭证',
                  caseSensitive: false)
              .hasMatch(key));
}
