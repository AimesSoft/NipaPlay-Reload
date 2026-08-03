import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/services/media_server_service_base.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/tvos_remote_text_input_scope.dart';

bool supportsMediaServerConnectionUserAgentSetting({bool isWeb = kIsWeb}) {
  return !isWeb;
}

class MediaServerConnectionUserAgentSetting extends StatefulWidget {
  const MediaServerConnectionUserAgentSetting({super.key});

  @override
  State<MediaServerConnectionUserAgentSetting> createState() =>
      _MediaServerConnectionUserAgentSettingState();
}

class _MediaServerConnectionUserAgentSettingState
    extends State<MediaServerConnectionUserAgentSetting> {
  String _storedUserAgent = '';
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadUserAgent();
  }

  @override
  Widget build(BuildContext context) {
    if (!supportsMediaServerConnectionUserAgentSetting()) {
      return const SizedBox.shrink();
    }

    final displayedUserAgent = _storedUserAgent.isEmpty
        ? MediaServerServiceBase.defaultConnectionUserAgent
        : _storedUserAgent;

    return AdaptiveSettingsSection(
      children: [
        AdaptiveSettingsTile<void>.card(
          title: _title(context),
          subtitle: _isLoading
              ? _text(context, '正在读取...', '正在讀取...', 'Loading...')
              : displayedUserAgent,
          icon: Ionicons.person_outline,
          phoneIcon: cupertino.CupertinoIcons.person,
          enabled: !_isLoading && !_isSaving,
          onTap: _editUserAgent,
        ),
      ],
    );
  }

  Future<void> _loadUserAgent() async {
    final stored = await MediaServerServiceBase.getStoredConnectionUserAgent();
    if (!mounted) return;
    setState(() {
      _storedUserAgent = stored;
      _isLoading = false;
    });
  }

  Future<void> _editUserAgent() async {
    final input = await _showInputDialog();
    if (!mounted || input == null) return;

    setState(() => _isSaving = true);
    final saved = await MediaServerServiceBase.saveConnectionUserAgent(input);
    if (!mounted) return;
    setState(() {
      _storedUserAgent = saved;
      _isSaving = false;
    });
    AdaptiveSnackBar.show(
      context,
      message: saved.isEmpty
          ? _text(
              context,
              '已恢复默认连接 UA',
              '已恢復預設連線 UA',
              'Default connection UA restored.',
            )
          : _text(
              context,
              '连接 UA 已保存',
              '連線 UA 已儲存',
              'Connection UA saved.',
            ),
      type: AdaptiveSnackBarType.success,
    );
  }

  Future<String?> _showInputDialog() async {
    var inputValue = _storedUserAgent;
    if (AdaptiveSettingsScope.isPhoneLayout(context)) {
      return cupertino.showCupertinoDialog<String>(
        context: context,
        builder: (dialogContext) => cupertino.CupertinoAlertDialog(
          title: Text(_title(context)),
          content: Column(
            children: [
              const SizedBox(height: 12),
              Text(_description(context)),
              const SizedBox(height: 12),
              cupertino.CupertinoTextFormFieldRow(
                initialValue: inputValue,
                onChanged: (value) => inputValue = value,
                placeholder: MediaServerServiceBase.defaultConnectionUserAgent,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 256,
              ),
            ],
          ),
          actions: [
            cupertino.CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.l10n.cancel),
            ),
            cupertino.CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(inputValue),
              child: Text(context.l10n.save),
            ),
          ],
        ),
      );
    }

    return BlurDialog.show<String>(
      context: context,
      title: _title(context),
      contentWidget: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_description(context)),
          const SizedBox(height: 12),
          TvOSRemoteTextInputControl(
            title: _title(context),
            maxLength: 256,
            child: TextFormField(
              initialValue: inputValue,
              onChanged: (value) => inputValue = value,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 256,
              decoration: const InputDecoration(
                hintText: MediaServerServiceBase.defaultConnectionUserAgent,
              ),
            ),
          ),
        ],
      ),
      actions: [
        HoverScaleTextButton(
          text: context.l10n.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        HoverScaleTextButton(
          text: context.l10n.save,
          onPressed: () => Navigator.of(context).pop(inputValue),
        ),
      ],
    );
  }

  String _title(BuildContext context) => _text(
        context,
        '连接 User-Agent（Jellyfin/Emby）',
        '連線 User-Agent（Jellyfin/Emby）',
        'Connection User-Agent (Jellyfin/Emby)',
      );

  String _description(BuildContext context) => _text(
        context,
        '用于 Jellyfin/Emby API、图片、播放会话和同步请求；视频流使用播放器 UA。留空使用程序默认值。',
        '用於 Jellyfin/Emby API、圖片、播放會話與同步請求；影片串流使用播放器 UA。留空使用程式預設值。',
        'Used for Jellyfin/Emby API, image, playback-session, and sync requests; video streams use the player UA. Leave empty to use the app default.',
      );

  String _text(
    BuildContext context,
    String simplified,
    String traditional,
    String english,
  ) {
    final locale = context.l10n.localeName;
    if (locale == 'en') return english;
    if (locale == 'zh_Hant') return traditional;
    return simplified;
  }
}
