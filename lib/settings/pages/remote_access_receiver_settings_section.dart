import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/providers/remote_access_settings_provider.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/services/remote_access_qr_service.dart';
import 'package:nipaplay/services/remote_control_access_guard_service.dart';
import 'package:nipaplay/services/remote_control_settings.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/utils/remote_access_address_utils.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

class RemoteAccessReceiverSettingsSection extends StatefulWidget {
  const RemoteAccessReceiverSettingsSection({super.key});

  @override
  State<RemoteAccessReceiverSettingsSection> createState() =>
      _RemoteAccessReceiverSettingsSectionState();
}

class _RemoteAccessReceiverSettingsSectionState
    extends State<RemoteAccessReceiverSettingsSection> {
  bool _webServerEnabled = false;
  bool _receiverEnabled = true;
  bool _autoStartEnabled = false;
  bool _ipv6Enabled = false;
  List<String> _accessUrls = [];
  String? _publicIpUrl;
  bool _isLoadingPublicIp = false;
  int _currentPort = 1180;

  List<Map<String, dynamic>> _trustedDevices = [];
  bool _isLoadingTrustedDevices = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final server = ServiceProvider.webServer;
    await server.loadSettings();
    final receiverEnabled = await RemoteControlSettings.isReceiverEnabled();
    await _loadTrustedDevices();
    if (!mounted) return;
    final shouldUpdateUrls = server.isRunning;
    setState(() {
      _webServerEnabled = server.isRunning;
      _receiverEnabled = receiverEnabled;
      _autoStartEnabled = server.autoStart;
      _ipv6Enabled = server.ipv6Enabled;
      _currentPort = server.port;
    });
    if (shouldUpdateUrls) {
      await _updateAccessUrls();
    }
  }

  Future<void> _loadTrustedDevices() async {
    if (mounted) {
      setState(() {
        _isLoadingTrustedDevices = true;
      });
    }
    try {
      final guardService = RemoteControlAccessGuardService.instance;
      await guardService.loadTrustedDevices();
      final devices = await guardService.getTrustedDevices();
      if (!mounted) return;
      setState(() {
        _trustedDevices = devices;
      });
    } catch (e) {
      debugPrint('加载受信任设备失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTrustedDevices = false;
        });
      }
    }
  }

  Future<void> _removeTrustedDevice(String clientKey) async {
    final confirmed = AdaptiveSettingsScope.isPhoneLayout(context)
        ? await cupertino.showCupertinoDialog<bool>(
            context: context,
            builder: (dialogContext) => cupertino.CupertinoAlertDialog(
              title: const Text('移除受信任设备'),
              content: const Text('移除后，该设备下次连接时需要重新确认。'),
              actions: [
                cupertino.CupertinoDialogAction(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                cupertino.CupertinoDialogAction(
                  isDestructiveAction: true,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('移除'),
                ),
              ],
            ),
          )
        : await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('移除受信任设备'),
              content: const Text('移除后，该设备下次连接时需要重新确认。'),
              actions: [
                AdaptiveSettingsActionButton(
                  label: '取消',
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
                AdaptiveSettingsActionButton(
                  label: '移除',
                  destructive: true,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                ),
              ],
            ),
          );
    if (confirmed != true) return;

    try {
      final guardService = RemoteControlAccessGuardService.instance;
      await guardService.removeTrustedDevice(clientKey);
      if (!mounted) return;
      setState(() {
        _trustedDevices.removeWhere(
          (device) => device['clientKey'] == clientKey,
        );
      });
      AdaptiveSnackBar.show(context, message: '已移除受信任设备');
    } catch (e) {
      debugPrint('移除受信任设备失败: $e');
      if (!mounted) return;
      AdaptiveSnackBar.show(context, message: '移除受信任设备失败');
    }
  }

  Future<void> _updateAccessUrls() async {
    final urls = await ServiceProvider.webServer.getAccessUrls();
    if (!mounted) return;
    setState(() {
      _accessUrls = urls;
    });
    await _fetchPublicIp();
  }

  Future<void> _fetchPublicIp() async {
    if (!_webServerEnabled || !mounted) return;
    setState(() {
      _isLoadingPublicIp = true;
    });
    try {
      final response =
          await http.get(Uri.parse('https://api.ipify.org')).timeout(
                const Duration(seconds: 5),
                onTimeout: () => throw Exception('获取公网IP超时'),
              );
      final ip = response.statusCode == 200 ? response.body.trim() : null;
      if (!mounted || !_webServerEnabled) return;
      setState(() {
        _publicIpUrl =
            ip == null || ip.isEmpty ? null : 'http://$ip:$_currentPort';
        _isLoadingPublicIp = false;
      });
    } catch (e) {
      debugPrint('获取公网IP出错: $e');
      if (!mounted || !_webServerEnabled) return;
      setState(() {
        _publicIpUrl = null;
        _isLoadingPublicIp = false;
      });
    }
  }

  Future<void> _toggleWebServer(bool enabled) async {
    setState(() {
      _webServerEnabled = enabled;
    });

    final server = ServiceProvider.webServer;
    if (enabled) {
      final success = await server.startServer(port: _currentPort);
      if (!mounted) return;
      if (success) {
        AdaptiveSnackBar.show(context, message: '远程访问服务已启动');
        await _updateAccessUrls();
        return;
      }
      setState(() {
        _webServerEnabled = false;
        _accessUrls = [];
        _publicIpUrl = null;
      });
      _showStartServerErrorDialog(server.lastStartErrorMessage ?? '未知原因');
      return;
    }

    await server.stopServer();
    if (!mounted) return;
    AdaptiveSnackBar.show(context, message: '远程访问服务已停止');
    setState(() {
      _accessUrls = [];
      _publicIpUrl = null;
    });
  }

  Future<void> _toggleAutoStart(bool enabled) async {
    setState(() {
      _autoStartEnabled = enabled;
    });
    await ServiceProvider.webServer.setAutoStart(enabled);
    if (!mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: enabled
          ? '已开启自动开启：下次启动将自动启用远程访问'
          : (_webServerEnabled ? '已关闭自动开启（当前服务仍在运行）' : '已关闭自动开启'),
    );
  }

  Future<void> _toggleIpv6(bool enabled) async {
    final previousValue = _ipv6Enabled;
    setState(() {
      _ipv6Enabled = enabled;
    });

    final server = ServiceProvider.webServer;
    final success = await server.setIpv6Enabled(enabled);
    if (!mounted) return;
    if (success) {
      setState(() {
        _webServerEnabled = server.isRunning;
      });
      if (server.isRunning) {
        await _updateAccessUrls();
      }
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: enabled ? '已开启 IPv6 访问地址' : '已关闭 IPv6 访问地址',
      );
      return;
    }

    setState(() {
      _ipv6Enabled = previousValue;
      _webServerEnabled = server.isRunning;
      _accessUrls = [];
      _publicIpUrl = null;
    });
    _showStartServerErrorDialog(server.lastStartErrorMessage ?? '未知原因');
  }

  Future<void> _toggleReceiver(bool enabled) async {
    setState(() {
      _receiverEnabled = enabled;
    });
    await RemoteControlSettings.setReceiverEnabled(enabled);
    if (enabled && !_webServerEnabled) {
      final server = ServiceProvider.webServer;
      final success = await server.startServer(port: _currentPort);
      if (!mounted) return;
      if (success) {
        setState(() {
          _webServerEnabled = true;
        });
        await _updateAccessUrls();
      } else {
        _showStartServerErrorDialog(server.lastStartErrorMessage ?? '未知原因');
      }
    }
    if (!mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: enabled ? '被遥控端已开启' : '被遥控端已关闭',
    );
  }

  void _copyUrl(String url) {
    Clipboard.setData(ClipboardData(text: url));
    AdaptiveSnackBar.show(context, message: '访问地址已复制到剪贴板');
  }

  void _showStartServerErrorDialog(String message) {
    if (AdaptiveSettingsScope.isPhoneLayout(context)) {
      AdaptiveAlertDialog.show(
        context: context,
        title: '远程访问服务启动失败',
        message: message,
        actions: [
          AlertAction(
            title: '确定',
            style: AlertActionStyle.primary,
            onPressed: () {},
          ),
        ],
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('远程访问服务启动失败'),
        content: Text(message),
        actions: [
          AdaptiveSettingsActionButton(
            label: '确定',
            primary: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Future<void> _showPortDialog() async {
    if (AdaptiveSettingsScope.isPhoneLayout(context)) {
      final input = await AdaptiveAlertDialog.inputShow(
        context: context,
        title: '设置远程访问端口',
        input: const AdaptiveAlertDialogInput(
          placeholder: '端口 (1-65535)',
          keyboardType: TextInputType.number,
        ),
        actions: [
          AlertAction(
            title: '取消',
            style: AlertActionStyle.cancel,
            onPressed: () {},
          ),
          AlertAction(
            title: '确定',
            style: AlertActionStyle.primary,
            onPressed: () {},
          ),
        ],
      );
      if (!mounted || input == null) return;
      final newPort = int.tryParse(input.trim());
      if (newPort == null || newPort <= 0 || newPort >= 65536) {
        AdaptiveSnackBar.show(context, message: '请输入有效的端口号 (1-65535)');
        return;
      }
      await _applyPort(newPort);
      return;
    }

    final controller = TextEditingController(text: _currentPort.toString());
    final newPort = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置远程访问端口'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: '端口 (1-65535)'),
        ),
        actions: [
          AdaptiveSettingsActionButton(
            label: '取消',
            onPressed: () => Navigator.of(context).pop(),
          ),
          AdaptiveSettingsActionButton(
            label: '确定',
            primary: true,
            onPressed: () {
              final port = int.tryParse(controller.text);
              if (port != null && port > 0 && port < 65536) {
                Navigator.of(context).pop(port);
              } else {
                AdaptiveSnackBar.show(
                  context,
                  message: '请输入有效的端口号 (1-65535)',
                );
              }
            },
          ),
        ],
      ),
    );

    if (newPort == null) return;
    await _applyPort(newPort);
  }

  Future<void> _applyPort(int newPort) async {
    if (newPort == _currentPort) return;
    final wasRunning = _webServerEnabled;
    setState(() {
      _currentPort = newPort;
    });
    final server = ServiceProvider.webServer;
    await server.setPort(newPort);
    if (!mounted) return;
    if (wasRunning) {
      if (server.isRunning) {
        AdaptiveSnackBar.show(context, message: '远程访问端口已更新，服务已重启');
        await _updateAccessUrls();
      } else {
        setState(() {
          _webServerEnabled = false;
          _accessUrls = [];
          _publicIpUrl = null;
        });
        _showStartServerErrorDialog(server.lastStartErrorMessage ?? '未知原因');
      }
      return;
    }
    AdaptiveSnackBar.show(context, message: '远程访问端口已更新');
  }

  String? get _recommendedQrUrl {
    String? firstLan;
    String? firstReachable;
    for (final url in _accessUrls) {
      final type = RemoteAccessAddressUtils.classifyUrl(url);
      if (type == RemoteAccessAddressType.lan) {
        firstLan ??= url;
      }
      if (type != RemoteAccessAddressType.local) {
        firstReachable ??= url;
      }
    }
    return firstLan ??
        _publicIpUrl ??
        firstReachable ??
        (_accessUrls.isNotEmpty ? _accessUrls.first : null);
  }

  List<String> get _qrCandidateUrls {
    final ordered = <String>[];
    final seen = <String>{};
    for (final url in _accessUrls) {
      if (seen.add(url)) ordered.add(url);
    }
    final publicUrl = _publicIpUrl;
    if (publicUrl != null && publicUrl.isNotEmpty && seen.add(publicUrl)) {
      ordered.add(publicUrl);
    }
    return ordered;
  }

  Future<void> _showQrDialog() async {
    final qrUrl = _recommendedQrUrl;
    if (qrUrl == null) return;
    final payload = RemoteAccessQrService.buildPayload(
      baseUrl: qrUrl,
      candidateBaseUrls: _qrCandidateUrls,
    );
    if (AdaptiveSettingsScope.isPhoneLayout(context)) {
      await CupertinoBottomSheet.show<void>(
        context: context,
        title: '手机扫码连接',
        floatingTitle: true,
        child: _buildPhoneQrContent(payload, qrUrl),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('手机扫码连接'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: QrImageView(
                  data: payload,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(qrUrl),
            ],
          ),
        ),
        actions: [
          AdaptiveSettingsActionButton(
            label: '复制地址',
            icon: Icons.copy,
            onPressed: () => _copyUrl(qrUrl),
          ),
          AdaptiveSettingsActionButton(
            label: '完成',
            primary: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneQrContent(String payload, String qrUrl) {
    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) => [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, topSpacing + 8, 20, 24),
          sliver: SliverList.list(
            children: [
              Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: QrImageView(
                      data: payload,
                      version: QrVersions.auto,
                      size: 220,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SelectableText(qrUrl, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              cupertino.CupertinoButton.filled(
                onPressed: () => _copyUrl(qrUrl),
                child: const Text('复制地址'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final remoteAccessSettings = context.watch<RemoteAccessSettingsProvider>();
    final showRemoteAccessQrCode = remoteAccessSettings.showRemoteAccessQrCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdaptiveSettingsCanvas(
          child: _buildRemoteAccessControl(
            context,
            showRemoteAccessQrCode: showRemoteAccessQrCode,
            onShowQrChanged: remoteAccessSettings.setShowRemoteAccessQrCode,
          ),
        ),
        if (_receiverEnabled) ...[
          const SizedBox(height: 16),
          AdaptiveSettingsCanvas(
            child: _buildTrustedDevicesControl(context),
          ),
        ],
      ],
    );
  }

  Widget _buildRemoteAccessControl(
    BuildContext context, {
    required bool showRemoteAccessQrCode,
    required ValueChanged<bool> onShowQrChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusText = _webServerEnabled ? '服务运行中' : '服务未启动';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRemoteHeader(
          context,
          icon: Icons.cast_connected,
          title: '远程访问与遥控',
          subtitle: '在同一网络内访问本机媒体库，也可以让手机或其他客户端遥控播放。',
          status: statusText,
          active: _webServerEnabled,
        ),
        const SizedBox(height: 16),
        _buildRemoteSwitchRow(
          context,
          icon: Icons.power_settings_new,
          title: '启用远程访问服务',
          subtitle: '允许其他 NipaPlay 客户端远程访问本机媒体库',
          value: _webServerEnabled,
          onChanged: _toggleWebServer,
        ),
        _buildRemoteSwitchRow(
          context,
          icon: Icons.settings_remote,
          title: '启用被遥控端',
          subtitle: '允许控制端读取播放器状态、菜单参数并进行遥控',
          value: _receiverEnabled,
          onChanged: _toggleReceiver,
        ),
        _buildRemoteSwitchRow(
          context,
          icon: Icons.auto_awesome,
          title: '软件打开自动开启',
          subtitle: '启动 NipaPlay 时自动开启远程访问服务',
          value: _autoStartEnabled,
          onChanged: _toggleAutoStart,
        ),
        _buildRemoteSwitchRow(
          context,
          icon: Icons.router,
          title: '启用 IPv6 访问地址',
          subtitle: '地址列表和二维码会包含可用的 IPv6 地址',
          value: _ipv6Enabled,
          onChanged: _toggleIpv6,
        ),
        _buildRemoteSwitchRow(
          context,
          icon: Icons.qr_code_2,
          title: '显示远程访问二维码',
          subtitle: '用于另一台设备扫码连接共享媒体库与遥控器',
          value: showRemoteAccessQrCode,
          onChanged: onShowQrChanged,
        ),
        _buildRemoteActionRow(
          context,
          icon: Icons.settings_ethernet,
          title: '远程访问端口',
          subtitle: '当前端口: $_currentPort',
          onTap: _showPortDialog,
          trailing: AdaptiveSettingsActionButton(
            label: '修改',
            onPressed: _showPortDialog,
          ),
        ),
        if (_webServerEnabled) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(
              height: 1,
              color: colorScheme.onSurface.withValues(alpha: 0.12),
            ),
          ),
          _buildAccessAddressPanel(
            context,
            showRemoteAccessQrCode: showRemoteAccessQrCode,
          ),
        ],
      ],
    );
  }

  Widget _buildRemoteHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String status,
    required bool active,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor =
        active ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: statusColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _buildStatusChip(context, status, active: active),
      ],
    );
  }

  Widget _buildStatusChip(
    BuildContext context,
    String label, {
    required bool active,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = active ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildRemoteSwitchRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return _buildRemoteActionRow(
      context,
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: () => onChanged(!value),
      trailing: AdaptiveSettingsSwitch(
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildRemoteActionRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
    bool destructive = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = destructive ? colorScheme.error : colorScheme.primary;

    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: accentColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: destructive
                            ? colorScheme.error
                            : colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccessAddressPanel(
    BuildContext context, {
    required bool showRemoteAccessQrCode,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '客户端连接地址',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        if (_accessUrls.isEmpty)
          _buildRemoteInfoLine(context, '正在获取地址...')
        else
          for (final url in _accessUrls) _buildAddressControl(context, url),
        if (_isLoadingPublicIp)
          _buildRemoteInfoLine(context, '正在获取公网 IP...')
        else if (_publicIpUrl != null)
          _buildAddressControl(context, _publicIpUrl!),
        if (showRemoteAccessQrCode) ...[
          const SizedBox(height: 12),
          _buildQrPreviewPanel(context),
        ],
      ],
    );
  }

  Widget _buildAddressControl(BuildContext context, String url) {
    final type = RemoteAccessAddressUtils.classifyUrl(url);
    final label = RemoteAccessAddressUtils.labelZh(type);
    final colorScheme = Theme.of(context).colorScheme;
    final color = _addressTypeColor(context, type);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _copyUrl(url),
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.onSurface.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.onSurface.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Icon(_addressTypeIcon(type), size: 20, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SelectableText(
                      url,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AdaptiveSettingsActionButton(
                label: '复制',
                icon: Icons.copy,
                onPressed: () => _copyUrl(url),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQrPreviewPanel(BuildContext context) {
    final qrUrl = _recommendedQrUrl;
    final colorScheme = Theme.of(context).colorScheme;
    if (qrUrl == null) {
      return _buildRemoteInfoLine(context, '正在生成二维码...');
    }

    final payload = RemoteAccessQrService.buildPayload(
      baseUrl: qrUrl,
      candidateBaseUrls: _qrCandidateUrls,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final useColumn = constraints.maxWidth < 520;
        final qrCode = Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(
            data: payload,
            version: QrVersions.auto,
            size: 132,
            backgroundColor: Colors.white,
          ),
        );
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '手机扫码连接',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '同一网络内的手机或平板可以扫码连接共享媒体库与遥控器。',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              qrUrl,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AdaptiveSettingsActionButton(
                  label: '复制地址',
                  icon: Icons.copy,
                  onPressed: () => _copyUrl(qrUrl),
                ),
                AdaptiveSettingsActionButton(
                  label: '放大',
                  icon: Icons.open_in_full,
                  onPressed: _showQrDialog,
                ),
              ],
            ),
          ],
        );

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.14),
            ),
          ),
          child: useColumn
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    qrCode,
                    const SizedBox(height: 12),
                    details,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    qrCode,
                    const SizedBox(width: 14),
                    Expanded(child: details),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildTrustedDevicesControl(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRemoteHeader(
          context,
          icon: Ionicons.shield_checkmark_outline,
          title: '受信任设备',
          subtitle: '已经确认过的遥控端会显示在这里，移除后下次连接需要重新确认。',
          status: '${_trustedDevices.length} 台',
          active: _trustedDevices.isNotEmpty,
        ),
        const SizedBox(height: 12),
        if (_isLoadingTrustedDevices)
          _buildRemoteInfoLine(context, '正在加载...')
        else if (_trustedDevices.isEmpty)
          _buildRemoteInfoLine(context, '暂无受信任设备')
        else
          for (final device in _trustedDevices)
            _buildTrustedDeviceControl(context, device),
      ],
    );
  }

  Widget _buildTrustedDeviceControl(
    BuildContext context,
    Map<String, dynamic> device,
  ) {
    final clientKey = device['clientKey'] as String?;
    return _buildRemoteActionRow(
      context,
      icon: Ionicons.phone_portrait_outline,
      title: device['clientName'] as String? ?? '未知设备',
      subtitle: _trustedDeviceSubtitle(device),
      trailing: AdaptiveSettingsActionButton(
        label: '移除',
        icon: Icons.delete_outline,
        destructive: true,
        onPressed:
            clientKey == null ? null : () => _removeTrustedDevice(clientKey),
      ),
      onTap: clientKey == null ? null : () => _removeTrustedDevice(clientKey),
      destructive: true,
    );
  }

  Widget _buildRemoteInfoLine(BuildContext context, String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
    );
  }

  Color _addressTypeColor(BuildContext context, RemoteAccessAddressType type) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (type) {
      case RemoteAccessAddressType.local:
        return colorScheme.onSurfaceVariant;
      case RemoteAccessAddressType.lan:
        return colorScheme.primary;
      case RemoteAccessAddressType.wan:
        return Colors.teal;
      case RemoteAccessAddressType.unknown:
        return colorScheme.secondary;
    }
  }

  String _trustedDeviceSubtitle(Map<String, dynamic> device) {
    final platform = device['platform'] as String? ?? '未知平台';
    final remoteIp = device['remoteIp'] as String? ?? '未知IP';
    final trustedAt = device['trustedAt'] as String? ?? '';
    var trustedTime = '未知时间';
    if (trustedAt.isNotEmpty) {
      try {
        final date = DateTime.parse(trustedAt);
        trustedTime =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }
    return '$platform · $remoteIp · 信任时间: $trustedTime';
  }

  IconData _addressTypeIcon(RemoteAccessAddressType type) {
    switch (type) {
      case RemoteAccessAddressType.local:
        return Icons.computer;
      case RemoteAccessAddressType.lan:
        return Icons.lan;
      case RemoteAccessAddressType.wan:
        return Icons.public;
      case RemoteAccessAddressType.unknown:
        return Icons.link;
    }
  }
}
