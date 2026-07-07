import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/services/server_connectivity_service.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/network_settings.dart';

class NetworkSettingsContent extends StatefulWidget {
  const NetworkSettingsContent({super.key});

  @override
  State<NetworkSettingsContent> createState() => _NetworkSettingsContentState();
}

class _NetworkSettingsContentState extends State<NetworkSettingsContent> {
  final GlobalKey _serverDropdownKey = GlobalKey();
  final _connectivity = ServerConnectivityService.instance;

  String _currentServer = '';
  String _currentBangumiServer = '';
  bool _isLoading = true;
  bool _isSavingCustom = false;
  bool _isSavingBangumiCustom = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentServer();
    _connectivity.dandanplayNotifier.addListener(_onConnectivityChanged);
    _connectivity.bangumiNotifier.addListener(_onConnectivityChanged);
    _connectivity.checkingNotifier.addListener(_onConnectivityChanged);
  }

  @override
  void dispose() {
    _connectivity.dandanplayNotifier.removeListener(_onConnectivityChanged);
    _connectivity.bangumiNotifier.removeListener(_onConnectivityChanged);
    _connectivity.checkingNotifier.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (_isLoading) {
      return AdaptiveSettingsPage(
        title: l10n.networkSettings,
        children: const [Center(child: CircularProgressIndicator())],
      );
    }

    return AdaptiveSettingsPage(
      title: l10n.networkSettings,
      children: [
        AdaptiveSettingsSection(
          children: [
            AdaptiveSettingsTile<void>.card(
              title: _text(context, '网络诊断', '網路診斷', 'Network Diagnostics'),
              subtitle: _diagnosticsSubtitle(context),
              icon: Ionicons.wifi_outline,
              phoneIcon: cupertino.CupertinoIcons.wifi,
              enabled: !_connectivity.isChecking,
              onTap: _connectivity.checkConnectivity,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AdaptiveSettingsSection(
          children: [
            AdaptiveSettingsTile<void>.card(
              title: _text(
                context,
                '自定义 Bangumi API 服务器',
                '自訂 Bangumi API 伺服器',
                'Custom Bangumi API Server',
              ),
              subtitle: _bangumiSubtitle(context),
              icon: Ionicons.book_outline,
              phoneIcon: cupertino.CupertinoIcons.book,
              enabled: !_isSavingBangumiCustom,
              onTap: _editBangumiServer,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AdaptiveSettingsSection(
          children: [
            AdaptiveSettingsTile<String>.dropdown(
              title: l10n.dandanplayServer,
              subtitle: l10n.currentServer(
                _getServerDisplayName(context, _currentServer),
              ),
              icon: Ionicons.server_outline,
              phoneIcon: cupertino.CupertinoIcons.cloud,
              items: _serverDropdownItems(context),
              onChanged: _changeServer,
              dropdownKey: _serverDropdownKey,
            ),
            AdaptiveSettingsTile<void>.card(
              title: _text(
                context,
                '自定义弹弹play API 服务器',
                '自訂彈彈play API 伺服器',
                'Custom DanDanPlay API Server',
              ),
              subtitle: _dandanplayCustomSubtitle(context),
              icon: Ionicons.create_outline,
              phoneIcon: cupertino.CupertinoIcons.pencil,
              enabled: !_isSavingCustom,
              onTap: _editDandanplayServer,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AdaptiveSettingsSection(
          children: [
            AdaptiveSettingsTile<void>.card(
              title: _text(
                context,
                '自定义 User-Agent',
                '自訂 User-Agent',
                'Custom User-Agent',
              ),
              subtitle: _persistentUASubtitle(context),
              icon: Ionicons.person_outline,
              phoneIcon: cupertino.CupertinoIcons.person,
              onTap: _editPersistentUA,
            ),
            AdaptiveSettingsTile<void>.card(
              title: _text(
                context,
                '恢复默认 User-Agent',
                '恢復預設 User-Agent',
                'Restore Default User-Agent',
              ),
              subtitle: _text(
                context,
                '清除自定义 UA 并使用内核默认值',
                '清除自訂 UA 並使用核心預設值',
                'Clear the custom UA and use the player kernel default.',
              ),
              icon: Ionicons.refresh_outline,
              phoneIcon: cupertino.CupertinoIcons.refresh,
              enabled: _persistentUAHasValue(),
              onTap: _resetPersistentUA,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AdaptiveSettingsSection(
          children: [
            AdaptiveSettingsTile<void>.card(
              title: l10n.serverDescriptionTitle,
              subtitle:
                  '${l10n.serverBullet(l10n.primaryServer, l10n.networkServerDescriptionPrimary)}\n'
                  '${l10n.serverBullet(l10n.backupServer, l10n.networkServerDescriptionBackup)}',
              icon: Ionicons.help_circle_outline,
              phoneIcon: cupertino.CupertinoIcons.question_circle,
              onTap: () {},
            ),
          ],
        ),
      ],
    );
  }

  void _onConnectivityChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCurrentServer() async {
    final server = await NetworkSettings.getDandanplayServer();
    final bangumiServer = await NetworkSettings.getBangumiServer();
    if (!mounted) return;
    setState(() {
      _currentServer = server;
      _currentBangumiServer = bangumiServer;
      _isLoading = false;
    });
  }

  Future<void> _changeServer(String serverUrl) async {
    final message = context.l10n.networkServerSwitchedTo(
      _getServerDisplayName(context, serverUrl),
    );
    await NetworkSettings.setDandanplayServer(serverUrl);
    if (!mounted) return;
    setState(() {
      _currentServer = serverUrl;
    });
    AdaptiveSnackBar.show(
      context,
      message: message,
      type: AdaptiveSnackBarType.success,
    );
  }

  Future<void> _editDandanplayServer() async {
    final initialValue =
        NetworkSettings.isCustomServer(_currentServer) ? _currentServer : '';
    final title = _text(
      context,
      '自定义弹弹play API 服务器',
      '自訂彈彈play API 伺服器',
      'Custom DanDanPlay API Server',
    );
    final inputHint = context.l10n.customServerInputHint;
    final invalidMessage = context.l10n.invalidServerAddress;
    final switchedMessage = context.l10n.switchedToCustomServer;
    final input = await _showServerInputDialog(
      title: title,
      message: inputHint,
      initialValue: initialValue,
    );
    if (!mounted) return;
    if (input == null) return;

    if (input.isEmpty) {
      await _resetDandanplayServer();
      return;
    }

    if (!NetworkSettings.isValidServerUrl(input)) {
      AdaptiveSnackBar.show(
        context,
        message: invalidMessage,
        type: AdaptiveSnackBarType.error,
      );
      return;
    }

    setState(() {
      _isSavingCustom = true;
    });
    try {
      await NetworkSettings.setDandanplayServer(input);
      final server = await NetworkSettings.getDandanplayServer();
      if (!mounted) return;
      setState(() {
        _currentServer = server;
      });
      AdaptiveSnackBar.show(
        context,
        message: switchedMessage,
        type: AdaptiveSnackBarType.success,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingCustom = false;
        });
      }
    }
  }

  Future<void> _editBangumiServer() async {
    final initialValue =
        NetworkSettings.isCustomBangumiServer(_currentBangumiServer)
            ? _currentBangumiServer
            : '';
    final title = _text(
      context,
      '自定义 Bangumi API 服务器',
      '自訂 Bangumi API 伺服器',
      'Custom Bangumi API Server',
    );
    final inputHint = _text(
      context,
      '输入自定义 Bangumi API 服务器地址，留空使用默认服务器 (${NetworkSettings.bangumiDefaultServer})',
      '輸入自訂 Bangumi API 伺服器地址，留空使用預設伺服器 (${NetworkSettings.bangumiDefaultServer})',
      'Enter a custom Bangumi API server. Leave empty to use the default (${NetworkSettings.bangumiDefaultServer}).',
    );
    final invalidMessage = context.l10n.invalidServerAddress;
    final switchedMessage = _text(
      context,
      'Bangumi 服务器已切换到自定义服务器',
      'Bangumi 伺服器已切換到自訂伺服器',
      'Bangumi server switched to custom server.',
    );
    final input = await _showServerInputDialog(
      title: title,
      message: inputHint,
      initialValue: initialValue,
    );
    if (!mounted) return;
    if (input == null) return;

    if (input.isEmpty) {
      await _resetBangumiServer();
      return;
    }

    if (!NetworkSettings.isValidServerUrl(input)) {
      AdaptiveSnackBar.show(
        context,
        message: invalidMessage,
        type: AdaptiveSnackBarType.error,
      );
      return;
    }

    setState(() {
      _isSavingBangumiCustom = true;
    });
    try {
      await NetworkSettings.setBangumiServer(input);
      final server = await NetworkSettings.getBangumiServer();
      if (!mounted) return;
      setState(() {
        _currentBangumiServer = server;
      });
      AdaptiveSnackBar.show(
        context,
        message: switchedMessage,
        type: AdaptiveSnackBarType.success,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingBangumiCustom = false;
        });
      }
    }
  }

  Future<void> _resetDandanplayServer() async {
    final message = _text(
      context,
      '已切换到默认服务器',
      '已切換到預設伺服器',
      'Switched to default server.',
    );
    setState(() {
      _isSavingCustom = true;
    });
    try {
      await NetworkSettings.resetToDefaultServer();
      final server = await NetworkSettings.getDandanplayServer();
      if (!mounted) return;
      setState(() {
        _currentServer = server;
      });
      AdaptiveSnackBar.show(
        context,
        message: message,
        type: AdaptiveSnackBarType.success,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingCustom = false;
        });
      }
    }
  }

  Future<void> _resetBangumiServer() async {
    final message = _text(
      context,
      '已切换到默认服务器',
      '已切換到預設伺服器',
      'Switched to default server.',
    );
    setState(() {
      _isSavingBangumiCustom = true;
    });
    try {
      await NetworkSettings.resetBangumiServer();
      final server = await NetworkSettings.getBangumiServer();
      if (!mounted) return;
      setState(() {
        _currentBangumiServer = server;
      });
      AdaptiveSnackBar.show(
        context,
        message: message,
        type: AdaptiveSnackBarType.success,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingBangumiCustom = false;
        });
      }
    }
  }

  String _persistentUASubtitle(BuildContext context) {
    final ua = PlayerFactory.getCustomPlayerUA();
    if (ua.isEmpty) {
      return _text(
        context,
        '未设置（使用内核默认 UA）',
        '未設定（使用核心預設 UA）',
        'Not set (using the player kernel default UA).',
      );
    }
    return ua.length > 60 ? '${ua.substring(0, 60)}...' : ua;
  }

  bool _persistentUAHasValue() => PlayerFactory.getCustomPlayerUA().isNotEmpty;

  Future<void> _editPersistentUA() async {
    final input = await _showUserAgentInputDialog();
    if (!mounted || input == null) return;
    await PlayerFactory.saveCustomPlayerUA(input);
    if (!mounted) return;
    setState(() {});
    AdaptiveSnackBar.show(
      context,
      message: _text(context, '已保存自定义 UA', '已儲存自訂 UA', 'Custom UA saved.'),
      type: AdaptiveSnackBarType.success,
    );
  }

  Future<void> _resetPersistentUA() async {
    await PlayerFactory.saveCustomPlayerUA('');
    if (!mounted) return;
    setState(() {});
    AdaptiveSnackBar.show(
      context,
      message: _text(context, '已恢复默认 UA', '已恢復預設 UA', 'Default UA restored.'),
      type: AdaptiveSnackBarType.success,
    );
  }

  Future<String?> _showServerInputDialog({
    required String title,
    required String message,
    required String initialValue,
  }) async {
    final colorScheme = Theme.of(context).colorScheme;
    final controller = TextEditingController(text: initialValue);
    final result = await BlurDialog.show<String>(
      context: context,
      title: title,
      contentWidget: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.72),
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            cursorColor: AppAccentColors.current,
            decoration: InputDecoration(
              hintText: 'https://example.com',
              hintStyle: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.38),
              ),
            ),
            style: TextStyle(color: colorScheme.onSurface),
          ),
        ],
      ),
      actions: [
        HoverScaleTextButton(
          text: context.l10n.cancel,
          idleColor: colorScheme.onSurface.withValues(alpha: 0.7),
          onPressed: () => Navigator.of(context).pop(),
        ),
        HoverScaleTextButton(
          text: context.l10n.useThisServer,
          idleColor: colorScheme.onSurface,
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
        ),
      ],
    );
    controller.dispose();
    return result;
  }

  Future<String?> _showUserAgentInputDialog() async {
    final colorScheme = Theme.of(context).colorScheme;
    final controller = TextEditingController(
      text: PlayerFactory.getCustomPlayerUA(),
    );
    final result = await BlurDialog.show<String>(
      context: context,
      title: _text(
        context,
        '自定义 User-Agent',
        '自訂 User-Agent',
        'Custom User-Agent',
      ),
      contentWidget: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _text(
              context,
              '播放器请求视频时使用，长期有效。重新输入可覆盖原值。',
              '播放器請求影片時使用，長期有效。重新輸入可覆蓋原值。',
              'Used by player video requests until changed. Enter a new value to replace the current one.',
            ),
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.72),
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            keyboardType: TextInputType.multiline,
            minLines: 2,
            maxLines: 4,
            autocorrect: false,
            enableSuggestions: false,
            cursorColor: AppAccentColors.current,
            decoration: InputDecoration(
              hintText: 'Mozilla/5.0 ...',
              hintStyle: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.38),
              ),
            ),
            style: TextStyle(color: colorScheme.onSurface),
          ),
        ],
      ),
      actions: [
        HoverScaleTextButton(
          text: context.l10n.cancel,
          idleColor: colorScheme.onSurface.withValues(alpha: 0.7),
          onPressed: () => Navigator.of(context).pop(),
        ),
        HoverScaleTextButton(
          text: _text(context, '保存', '儲存', 'Save'),
          idleColor: colorScheme.onSurface,
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
        ),
      ],
    );
    controller.dispose();
    return result;
  }

  List<DropdownMenuItemData<String>> _serverDropdownItems(
    BuildContext context,
  ) {
    final items = [
      DropdownMenuItemData(
        title: context.l10n.networkPrimaryServerRecommended,
        value: NetworkSettings.primaryServer,
        isSelected: _currentServer == NetworkSettings.primaryServer,
        description: context.l10n.networkServerDescriptionPrimary,
      ),
      DropdownMenuItemData(
        title: context.l10n.networkBackupServer,
        value: NetworkSettings.backupServer,
        isSelected: _currentServer == NetworkSettings.backupServer,
        description: context.l10n.networkServerDescriptionBackup,
      ),
    ];

    if (NetworkSettings.isCustomServer(_currentServer)) {
      items.add(
        DropdownMenuItemData(
          title: context.l10n.customServerWithValue(_currentServer),
          value: _currentServer,
          isSelected: true,
        ),
      );
    }

    return items;
  }

  String _diagnosticsSubtitle(BuildContext context) {
    final checkingText = _connectivity.isChecking
        ? _text(context, '检测中…', '檢測中…', 'Checking...')
        : _text(context, '点击重新检测', '點擊重新檢測', 'Tap to check again');
    return '弹弹play: ${_statusText(context, _connectivity.dandanplayAvailable)}\n'
        'Bangumi: ${_statusText(context, _connectivity.bangumiAvailable)}\n'
        '$checkingText';
  }

  String _bangumiSubtitle(BuildContext context) {
    if (NetworkSettings.isCustomBangumiServer(_currentBangumiServer)) {
      return _currentBangumiServer;
    }
    return _text(
      context,
      '当前使用默认服务器：${NetworkSettings.bangumiDefaultServer}',
      '目前使用預設伺服器：${NetworkSettings.bangumiDefaultServer}',
      'Using default server: ${NetworkSettings.bangumiDefaultServer}',
    );
  }

  String _dandanplayCustomSubtitle(BuildContext context) {
    if (NetworkSettings.isCustomServer(_currentServer)) {
      return _currentServer;
    }
    return context.l10n.customServerInputHint;
  }

  String _statusText(BuildContext context, bool? available) {
    if (available == null) {
      return _text(context, '检测中', '檢測中', 'Checking');
    }
    return available
        ? _text(context, '可用', '可用', 'Available')
        : _text(context, '不可用', '不可用', 'Unavailable');
  }

  String _getServerDisplayName(BuildContext context, String serverUrl) {
    switch (serverUrl) {
      case NetworkSettings.primaryServer:
        return context.l10n.primaryServer;
      case NetworkSettings.backupServer:
        return context.l10n.backupServer;
      default:
        return serverUrl;
    }
  }

  String _text(
    BuildContext context,
    String simplified,
    String traditional,
    String english,
  ) {
    final locale = context.l10n.localeName;
    if (locale == 'en') {
      return english;
    }
    if (locale == 'zh_Hant') {
      return traditional;
    }
    return simplified;
  }
}
