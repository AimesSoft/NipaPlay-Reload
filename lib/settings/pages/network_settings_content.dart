import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/services/app_http_proxy.dart';
import 'package:nipaplay/services/nipaplay_server_router.dart';
import 'package:nipaplay/services/server_connectivity_service.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/tvos_remote_text_input_scope.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/network_settings.dart';

bool supportsUnifiedHttpProxySetting({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (isWeb) return false;
  return platform == TargetPlatform.windows ||
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.linux;
}

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
  DandanplayServerMode _currentMode = DandanplayServerMode.auto;
  ServerRoutingSnapshot? _routing;
  bool _isLoading = true;
  bool _isSavingCustom = false;
  bool _isSavingBangumiCustom = false;

  /// 下拉菜单里代表「自动选择」的哨兵值（不是合法 URL）。
  static const String _autoOptionValue = '__nipaplay_auto_server__';

  @override
  void initState() {
    super.initState();
    _loadCurrentServer();
    _connectivity.dandanplayNotifier.addListener(_onConnectivityChanged);
    _connectivity.bangumiNotifier.addListener(_onConnectivityChanged);
    _connectivity.checkingNotifier.addListener(_onConnectivityChanged);
    NipaplayServerRouter.instance.snapshotNotifier.addListener(
      _onRoutingChanged,
    );
  }

  @override
  void dispose() {
    _connectivity.dandanplayNotifier.removeListener(_onConnectivityChanged);
    _connectivity.bangumiNotifier.removeListener(_onConnectivityChanged);
    _connectivity.checkingNotifier.removeListener(_onConnectivityChanged);
    NipaplayServerRouter.instance.snapshotNotifier.removeListener(
      _onRoutingChanged,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (_isLoading) {
      return const AdaptiveSettingsPage(
        children: [Center(child: CircularProgressIndicator())],
      );
    }

    return AdaptiveSettingsPage(
      children: [
        AdaptiveSettingsSection(
          children: [
            AdaptiveSettingsTile<void>.card(
              title: _text(context, '网络诊断', '網路診斷', 'Network Diagnostics'),
              subtitle: _diagnosticsSubtitle(context),
              icon: Ionicons.wifi_outline,
              phoneIcon: cupertino.CupertinoIcons.wifi,
              enabled: !_connectivity.isChecking,
              onTap: _runDiagnostics,
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
              subtitle: _serverSubtitle(context),
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
            if (_showHttpProxySetting)
              AdaptiveSettingsTile<void>.card(
                title: _text(
                  context,
                  '媒体服务器与播放器 HTTP 代理',
                  '媒體伺服器與播放器 HTTP 代理',
                  'Media Server & Player HTTP Proxy',
                ),
                subtitle: _httpProxySubtitle(context),
                icon: Ionicons.git_network_outline,
                phoneIcon: cupertino.CupertinoIcons.arrow_right_arrow_left,
                onTap: _editHttpProxy,
              ),
          ],
        ),
        const SizedBox(height: 16),
        AdaptiveSettingsSection(
          children: [
            AdaptiveSettingsTile<void>.card(
              title: l10n.serverDescriptionTitle,
              subtitle: l10n.networkServerDescriptionPrimary,
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

  void _onRoutingChanged() {
    if (!mounted) return;
    setState(() {
      _routing = NipaplayServerRouter.instance.snapshot;
    });
  }

  /// 网络诊断：自动模式下先重新判定主/备用线路，再检测连通性。
  Future<void> _runDiagnostics() async {
    if (_currentMode == DandanplayServerMode.auto) {
      await NipaplayServerRouter.instance.refresh();
    }
    await _connectivity.checkConnectivity();
    if (!mounted) return;
    final mode = await NetworkSettings.getDandanplayServerMode();
    final server = await NipaplayServerRouter.instance.effectiveServer();
    if (!mounted) return;
    setState(() {
      _currentMode = mode;
      _currentServer = server;
      _routing = NipaplayServerRouter.instance.snapshot;
    });
  }

  Future<void> _loadCurrentServer() async {
    final mode = await NetworkSettings.getDandanplayServerMode();
    // 自动模式下顺带刷新一次判定，让界面能显示真实选中的线路。
    final server = await NipaplayServerRouter.instance.effectiveServer();
    final bangumiServer = await NetworkSettings.getBangumiServer();
    if (!mounted) return;
    setState(() {
      _currentMode = mode;
      _currentServer = server;
      _currentBangumiServer = bangumiServer;
      _routing = NipaplayServerRouter.instance.snapshot;
      _isLoading = false;
    });
  }

  Future<void> _changeServer(String optionValue) async {
    if (optionValue == _autoOptionValue) {
      await NetworkSettings.setDandanplayServerMode(
        DandanplayServerMode.auto,
      );
    } else {
      await NetworkSettings.setDandanplayServer(optionValue);
    }
    if (!mounted) return;
    final mode = await NetworkSettings.getDandanplayServerMode();
    final server = await NipaplayServerRouter.instance.effectiveServer();
    if (!mounted) return;
    setState(() {
      _currentMode = mode;
      _currentServer = server;
    });
    AdaptiveSnackBar.show(
      context,
      message: context.l10n.networkServerSwitchedTo(
        _getServerDisplayName(context, optionValue),
      ),
      type: AdaptiveSnackBarType.success,
    );
  }

  Future<void> _editDandanplayServer() async {
    // 切到自动/固定模式后仍保留用户填过的自定义地址，这里回填便于再次修改。
    final initialValue = await NetworkSettings.getCustomServer();
    if (!mounted) return;
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
      // 留空表示清除自定义服务器并回到自动选择。
      await NetworkSettings.clearCustomServer();
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
      final mode = await NetworkSettings.getDandanplayServerMode();
      final server = await NipaplayServerRouter.instance.effectiveServer();
      if (!mounted) return;
      setState(() {
        _currentMode = mode;
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
      final mode = await NetworkSettings.getDandanplayServerMode();
      final server = await NipaplayServerRouter.instance.effectiveServer();
      if (!mounted) return;
      setState(() {
        _currentMode = mode;
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

  bool get _showHttpProxySetting {
    return supportsUnifiedHttpProxySetting(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    );
  }

  String _httpProxySubtitle(BuildContext context) {
    final proxy = PlayerFactory.getHttpProxy();
    final supportedKernels = _text(
      context,
      '播放器代理仅支持 MDK/MediaKit 内核。',
      '播放器代理僅支援 MDK/MediaKit 核心。',
      'Player proxy is supported by MDK/MediaKit only.',
    );
    if (proxy.isEmpty) {
      final disabled = _text(
        context,
        '未启用。仅支持 http:// 代理端点，可承载 HTTP/HTTPS 目标流量。',
        '未啟用。僅支援 http:// 代理端點，可承載 HTTP/HTTPS 目標流量。',
        'Disabled. Only http:// proxy endpoints are supported for HTTP/HTTPS targets.',
      );
      return '$disabled $supportedKernels';
    }
    return '$proxy\n$supportedKernels';
  }

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

  Future<void> _editHttpProxy() async {
    final input = await _showHttpProxyInputDialog();
    if (!mounted || input == null) return;
    try {
      AppHttpProxy.validate(input);
    } on FormatException {
      AdaptiveSnackBar.show(
        context,
        message: _text(
          context,
          '请输入有效的 http:// 代理地址；不支持 HTTPS 代理端点或 SOCKS。',
          '請輸入有效的 http:// 代理位址；不支援 HTTPS 代理端點或 SOCKS。',
          'Enter a valid http:// proxy endpoint. HTTPS proxy endpoints and SOCKS are unsupported.',
        ),
        type: AdaptiveSnackBarType.error,
      );
      return;
    }

    await PlayerFactory.saveHttpProxy(input);
    if (!mounted) return;
    setState(() {});
    AdaptiveSnackBar.show(
      context,
      message: input.isEmpty
          ? _text(context, 'HTTP 代理已关闭', 'HTTP 代理已關閉', 'HTTP proxy disabled.')
          : _text(context, 'HTTP 代理已保存并立即生效', 'HTTP 代理已儲存並立即生效',
              'HTTP proxy saved and applied.'),
      type: AdaptiveSnackBarType.success,
    );
  }

  Future<String?> _showHttpProxyInputDialog() async {
    final colorScheme = Theme.of(context).colorScheme;
    var inputValue = PlayerFactory.getHttpProxy();
    return BlurDialog.show<String>(
      context: context,
      title: _text(
        context,
        'HTTP 代理',
        'HTTP 代理',
        'HTTP Proxy',
      ),
      contentWidget: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _text(
              context,
              '供 Emby/Jellyfin 请求与播放器网络流共用。留空关闭。',
              '供 Emby/Jellyfin 請求與播放器網路串流共用。留空關閉。',
              'Shared by Emby/Jellyfin requests and player network streams. Leave empty to disable.',
            ),
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.72),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          TvOSRemoteTextInputControl(
            title: 'HTTP 代理',
            child: TextFormField(
              initialValue: inputValue,
              onChanged: (value) => inputValue = value,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                hintText: 'http://127.0.0.1:8000',
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
          onPressed: () => Navigator.of(context).pop(inputValue.trim()),
        ),
      ],
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
          TvOSRemoteTextInputControl(
            title: title,
            child: TextField(
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
    var inputValue = PlayerFactory.getCustomPlayerUA();
    final isPhone =
        AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone;
    final dialogNavigator = Navigator.of(
      context,
      rootNavigator: isPhone,
    );
    final inputField = TextFormField(
      initialValue: inputValue,
      onChanged: (value) => inputValue = value,
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
          TvOSRemoteTextInputControl(
            title: _text(
              context,
              '自定义 User-Agent',
              '自訂 User-Agent',
              'Custom User-Agent',
            ),
            child: isPhone
                ? Material(
                    type: MaterialType.transparency,
                    child: inputField,
                  )
                : inputField,
          ),
        ],
      ),
      actions: [
        HoverScaleTextButton(
          text: context.l10n.cancel,
          idleColor: colorScheme.onSurface.withValues(alpha: 0.7),
          onPressed: dialogNavigator.pop,
        ),
        HoverScaleTextButton(
          text: _text(context, '保存', '儲存', 'Save'),
          idleColor: colorScheme.onSurface,
          onPressed: () => dialogNavigator.pop(inputValue.trim()),
        ),
      ],
    );
    return result;
  }

  List<DropdownMenuItemData<String>> _serverDropdownItems(
    BuildContext context,
  ) {
    final items = <DropdownMenuItemData<String>>[
      DropdownMenuItemData(
        title: _text(
          context,
          '自动选择（推荐）',
          '自動選擇（推薦）',
          'Automatic (Recommended)',
        ),
        value: _autoOptionValue,
        isSelected: _currentMode == DandanplayServerMode.auto,
        description: _autoDescription(context),
      ),
      DropdownMenuItemData(
        title: _text(
          context,
          '香港服务器（域名）',
          '香港伺服器（網域）',
          'Hong Kong Server (Domain)',
        ),
        value: NetworkSettings.hongKongServer,
        isSelected: _currentMode == DandanplayServerMode.hongKong,
        description: NetworkSettings.hongKongServer,
      ),
      DropdownMenuItemData(
        title: _text(
          context,
          '国内服务器（IP 直连）',
          '國內伺服器（IP 直連）',
          'China Server (Direct IP)',
        ),
        value: NetworkSettings.chinaServer,
        isSelected: _currentMode == DandanplayServerMode.china,
        description: NetworkSettings.chinaServer,
      ),
    ];

    if (_currentMode == DandanplayServerMode.custom &&
        _currentServer.isNotEmpty) {
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

  /// 自动模式下的说明文本，展示依据（IP 归属地）与当前实际线路。
  String _autoDescription(BuildContext context) {
    final base = _text(
      context,
      '按 IP 归属地自动选择国内或香港服务器，并在线路异常时自动切换备用服务器',
      '依 IP 歸屬地自動選擇國內或香港伺服器，並在線路異常時自動切換備用伺服器',
      'Pick the China or Hong Kong server by IP region, with automatic failover.',
    );
    final routing = _routing;
    if (routing == null || routing.detectedRegion == null) {
      return base;
    }
    final regionText =
        routing.detectedRegion == NetworkSettings.autoRegionChina
            ? _text(context, '已判定为国内网络', '已判定為國內網路', 'Region: China')
            : _text(context, '已判定为海外网络', '已判定為海外網路', 'Region: Overseas');
    return '$base\n$regionText';
  }

  /// 服务器选择项下方的摘要，自动模式会带上当前生效线路。
  String _serverSubtitle(BuildContext context) {
    switch (_currentMode) {
      case DandanplayServerMode.auto:
        final parts = <String>[
          _text(context, '自动选择', '自動選擇', 'Automatic'),
          '${_text(context, '当前', '目前', 'Current')}: '
              '${_getServerDisplayName(context, _currentServer)}',
        ];
        if (_routing?.failoverActive == true) {
          parts.add(
            _text(
              context,
              '线路异常，已临时切换备用服务器',
              '線路異常，已臨時切換備用伺服器',
              'Failover active.',
            ),
          );
        }
        return parts.join('\n');
      case DandanplayServerMode.hongKong:
      case DandanplayServerMode.china:
      case DandanplayServerMode.custom:
        return context.l10n.currentServer(
          _getServerDisplayName(context, _currentServer),
        );
    }
  }

  String _diagnosticsSubtitle(BuildContext context) {
    final checkingText = _connectivity.isChecking
        ? _text(context, '检测中…', '檢測中…', 'Checking...')
        : _text(context, '点击重新检测', '點擊重新檢測', 'Tap to check again');
    return '${_getServerDisplayName(context, _currentServer)}\n'
        '弹弹play: ${_statusText(context, _connectivity.dandanplayAvailable)}\n'
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
    if (serverUrl == _autoOptionValue) {
      return _text(context, '自动选择', '自動選擇', 'Automatic');
    }
    if (serverUrl == NetworkSettings.hongKongServer) {
      return _text(
        context,
        '香港服务器',
        '香港伺服器',
        'Hong Kong Server',
      );
    }
    if (serverUrl == NetworkSettings.chinaServer) {
      return _text(
        context,
        '国内服务器',
        '國內伺服器',
        'China Server',
      );
    }
    return serverUrl;
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
