import 'dart:async';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/providers/remote_access_settings_provider.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/services/remote_access_qr_service.dart';
import 'package:nipaplay/services/remote_control_access_guard_service.dart';
import 'package:nipaplay/services/remote_control_settings.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/utils/remote_access_address_utils.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

class CupertinoRemoteAccessReceiverSection extends StatefulWidget {
  const CupertinoRemoteAccessReceiverSection({super.key});

  @override
  State<CupertinoRemoteAccessReceiverSection> createState() =>
      _CupertinoRemoteAccessReceiverSectionState();
}

class _CupertinoRemoteAccessReceiverSectionState
    extends State<CupertinoRemoteAccessReceiverSection> {
  bool _webServerEnabled = false;
  bool _receiverEnabled = true;
  bool _autoStartEnabled = false;
  bool _ipv6Enabled = false;
  bool _isLoadingPublicIp = false;
  bool _isLoadingTrustedDevices = false;
  int _currentPort = RemoteAccessQrService.defaultPort;
  String? _publicIpUrl;
  List<String> _accessUrls = const [];
  List<Map<String, dynamic>> _trustedDevices = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadWebServerState());
  }

  Future<void> _loadWebServerState() async {
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
    if (!mounted) return;
    setState(() {
      _isLoadingTrustedDevices = true;
    });
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
    try {
      final guardService = RemoteControlAccessGuardService.instance;
      await guardService.removeTrustedDevice(clientKey);
      if (!mounted) return;
      setState(() {
        _trustedDevices = _trustedDevices
            .where((device) => device['clientKey'] != clientKey)
            .toList(growable: false);
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
    unawaited(_fetchPublicIp());
  }

  Future<void> _fetchPublicIp() async {
    if (!_webServerEnabled || _isLoadingPublicIp) return;
    setState(() {
      _isLoadingPublicIp = true;
    });
    try {
      final response = await http
          .get(Uri.parse('https://api.ipify.org'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final ip = response.body.trim();
      if (ip.isEmpty || ip.contains('<') || ip.contains('>')) {
        throw Exception('获取到无效的公网 IP');
      }
      if (!mounted || !_webServerEnabled) return;
      setState(() {
        _publicIpUrl = 'http://$ip:$_currentPort';
      });
    } catch (e) {
      debugPrint('获取公网 IP 出错: $e');
      if (!mounted || !_webServerEnabled) return;
      setState(() {
        _publicIpUrl = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPublicIp = false;
        });
      }
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
      } else {
        setState(() {
          _webServerEnabled = false;
          _accessUrls = const [];
          _publicIpUrl = null;
        });
        _showStartServerErrorDialog(server.lastStartErrorMessage ?? '未知原因');
      }
      return;
    }

    await server.stopServer();
    if (!mounted) return;
    setState(() {
      _accessUrls = const [];
      _publicIpUrl = null;
    });
    AdaptiveSnackBar.show(context, message: '远程访问服务已停止');
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
        setState(() {
          _receiverEnabled = false;
        });
        await RemoteControlSettings.setReceiverEnabled(false);
        _showStartServerErrorDialog(server.lastStartErrorMessage ?? '未知原因');
        return;
      }
    }

    if (!mounted) return;
    AdaptiveSnackBar.show(context, message: enabled ? '被遥控端已开启' : '被遥控端已关闭');
  }

  Future<void> _toggleAutoStart(bool enabled) async {
    setState(() {
      _autoStartEnabled = enabled;
    });
    await ServiceProvider.webServer.setAutoStart(enabled);
    if (!mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: enabled ? '已开启自动启动远程访问' : '已关闭自动启动远程访问',
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
      _accessUrls = const [];
      _publicIpUrl = null;
    });
    _showStartServerErrorDialog(server.lastStartErrorMessage ?? '未知原因');
  }

  Future<void> _showPortDialog() async {
    final controller = TextEditingController(text: _currentPort.toString());
    final newPort = await showCupertinoDialog<int>(
      context: context,
      builder: (ctx) {
        return CupertinoAlertDialog(
          title: const Text('设置远程访问端口'),
          content: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: CupertinoTextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              placeholder: '1-65535',
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                final port = int.tryParse(controller.text);
                if (port != null && port > 0 && port < 65536) {
                  Navigator.of(ctx).pop(port);
                } else {
                  AdaptiveSnackBar.show(context, message: '请输入有效的端口号');
                }
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (newPort == null || newPort == _currentPort) return;

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
          _accessUrls = const [];
          _publicIpUrl = null;
        });
        _showStartServerErrorDialog(server.lastStartErrorMessage ?? '未知原因');
      }
    } else {
      AdaptiveSnackBar.show(context, message: '远程访问端口已更新');
    }
  }

  void _showStartServerErrorDialog(String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) {
        return CupertinoAlertDialog(
          title: const Text('远程访问服务启动失败'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(message),
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _copyUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    AdaptiveSnackBar.show(context, message: '访问地址已复制');
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
      if (seen.add(url)) {
        ordered.add(url);
      }
    }
    final publicIpUrl = _publicIpUrl;
    if (publicIpUrl != null &&
        publicIpUrl.isNotEmpty &&
        seen.add(publicIpUrl)) {
      ordered.add(publicIpUrl);
    }
    return ordered;
  }

  Widget _buildSwitch({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    if (PlatformInfo.isIOS26OrHigher()) {
      return AdaptiveSwitch(value: value, onChanged: onChanged);
    }
    return CupertinoSwitch(value: value, onChanged: onChanged);
  }

  Widget _buildSectionLabel(String text) {
    final style = CupertinoTheme.of(context).textTheme.textStyle.copyWith(
          fontSize: 13,
          color: CupertinoDynamicColor.resolve(
              CupertinoColors.systemGrey, context),
          letterSpacing: 0.2,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(text, style: style),
    );
  }

  @override
  Widget build(BuildContext context) {
    final remoteAccessSettings = context.watch<RemoteAccessSettingsProvider>();
    final sectionBackground = resolveSettingsSectionBackground(context);
    final tileBackground = resolveSettingsTileBackground(context);
    final iconColor = resolveSettingsIconColor(context);
    final showRemoteAccessQrCode = remoteAccessSettings.showRemoteAccessQrCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('本机远程访问'),
        const SizedBox(height: 8),
        CupertinoSettingsGroupCard(
          margin: EdgeInsets.zero,
          backgroundColor: sectionBackground,
          addDividers: true,
          dividerIndent: 16,
          children: [
            CupertinoSettingsTile(
              leading: Icon(CupertinoIcons.power, color: iconColor),
              title: const Text('启用远程访问服务'),
              subtitle: const Text('允许其他 NipaPlay 客户端访问本机媒体库'),
              backgroundColor: tileBackground,
              trailing: _buildSwitch(
                value: _webServerEnabled,
                onChanged: _toggleWebServer,
              ),
            ),
            CupertinoSettingsTile(
              leading: Icon(CupertinoIcons.game_controller, color: iconColor),
              title: const Text('启用被遥控端'),
              subtitle: const Text('允许控制端读取播放器状态、菜单参数并进行遥控'),
              backgroundColor: tileBackground,
              trailing: _buildSwitch(
                value: _receiverEnabled,
                onChanged: _toggleReceiver,
              ),
            ),
            CupertinoSettingsTile(
              leading:
                  Icon(CupertinoIcons.arrow_2_circlepath, color: iconColor),
              title: const Text('软件打开自动开启'),
              subtitle: const Text('启动 NipaPlay 时自动开启远程访问服务'),
              backgroundColor: tileBackground,
              trailing: _buildSwitch(
                value: _autoStartEnabled,
                onChanged: _toggleAutoStart,
              ),
            ),
            CupertinoSettingsTile(
              leading: Icon(CupertinoIcons.antenna_radiowaves_left_right,
                  color: iconColor),
              title: const Text('启用 IPv6 访问地址'),
              subtitle: const Text('地址列表和二维码会包含可用的 IPv6 地址'),
              backgroundColor: tileBackground,
              trailing: _buildSwitch(
                value: _ipv6Enabled,
                onChanged: _toggleIpv6,
              ),
            ),
            CupertinoSettingsTile(
              leading: Icon(CupertinoIcons.qrcode, color: iconColor),
              title: const Text('显示远程访问二维码'),
              subtitle: const Text('用于另一台设备扫码连接共享媒体库与遥控器'),
              backgroundColor: tileBackground,
              trailing: _buildSwitch(
                value: showRemoteAccessQrCode,
                onChanged: remoteAccessSettings.setShowRemoteAccessQrCode,
              ),
            ),
            CupertinoSettingsTile(
              leading:
                  Icon(CupertinoIcons.slider_horizontal_3, color: iconColor),
              title: const Text('端口设置'),
              subtitle: Text('当前端口: $_currentPort'),
              backgroundColor: tileBackground,
              trailing: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(32, 32),
                onPressed: _showPortDialog,
                child: const Icon(CupertinoIcons.pencil, size: 20),
              ),
            ),
          ],
        ),
        if (_webServerEnabled) ...[
          const SizedBox(height: 16),
          _buildAccessAddressGroup(
            sectionBackground: sectionBackground,
            tileBackground: tileBackground,
            iconColor: iconColor,
          ),
          if (showRemoteAccessQrCode) ...[
            const SizedBox(height: 16),
            _buildQrGroup(
              sectionBackground: sectionBackground,
              iconColor: iconColor,
            ),
          ],
        ],
        if (_receiverEnabled) ...[
          const SizedBox(height: 16),
          _buildTrustedDevicesGroup(
            sectionBackground: sectionBackground,
            tileBackground: tileBackground,
            iconColor: iconColor,
          ),
        ],
      ],
    );
  }

  Widget _buildAccessAddressGroup({
    required Color sectionBackground,
    required Color tileBackground,
    required Color iconColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('客户端连接地址'),
        const SizedBox(height: 8),
        CupertinoSettingsGroupCard(
          margin: EdgeInsets.zero,
          backgroundColor: sectionBackground,
          addDividers: true,
          dividerIndent: 16,
          children: [
            if (_accessUrls.isEmpty)
              CupertinoSettingsTile(
                leading: Icon(CupertinoIcons.link, color: iconColor),
                title: const Text('正在获取地址'),
                trailing: const CupertinoActivityIndicator(radius: 8),
                backgroundColor: tileBackground,
              )
            else
              ..._accessUrls.map(
                (url) => _buildAddressTile(
                  url: url,
                  backgroundColor: tileBackground,
                ),
              ),
            if (_isLoadingPublicIp)
              CupertinoSettingsTile(
                leading: Icon(CupertinoIcons.globe,
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.systemPurple, context)),
                title: const Text('外网'),
                subtitle: const Text('正在获取公网 IP...'),
                trailing: const CupertinoActivityIndicator(radius: 8),
                backgroundColor: tileBackground,
              )
            else if (_publicIpUrl != null)
              _buildAddressTile(
                url: _publicIpUrl!,
                backgroundColor: tileBackground,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildAddressTile({
    required String url,
    required Color backgroundColor,
  }) {
    final type = RemoteAccessAddressUtils.classifyUrl(url);
    final label = RemoteAccessAddressUtils.labelZh(type);
    final color = _addressTypeColor(type);
    final icon = _addressTypeIcon(type);
    return CupertinoSettingsTile(
      leading: Icon(icon, color: color),
      title: Text(label),
      subtitle: Text(
        url,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      backgroundColor: backgroundColor,
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(32, 32),
        onPressed: () => _copyUrl(url),
        child: Icon(CupertinoIcons.doc_on_doc, size: 19, color: color),
      ),
    );
  }

  IconData _addressTypeIcon(RemoteAccessAddressType type) {
    switch (type) {
      case RemoteAccessAddressType.local:
        return CupertinoIcons.device_phone_portrait;
      case RemoteAccessAddressType.lan:
        return CupertinoIcons.wifi;
      case RemoteAccessAddressType.wan:
        return CupertinoIcons.globe;
      case RemoteAccessAddressType.unknown:
        return CupertinoIcons.link;
    }
  }

  Color _addressTypeColor(RemoteAccessAddressType type) {
    final color = switch (type) {
      RemoteAccessAddressType.local => CupertinoColors.systemBlue,
      RemoteAccessAddressType.lan => CupertinoColors.activeGreen,
      RemoteAccessAddressType.wan => CupertinoColors.systemPurple,
      RemoteAccessAddressType.unknown => CupertinoColors.systemGrey,
    };
    return CupertinoDynamicColor.resolve(color, context);
  }

  Widget _buildQrGroup({
    required Color sectionBackground,
    required Color iconColor,
  }) {
    final qrUrl = _recommendedQrUrl;
    final qrCandidateUrls = _qrCandidateUrls;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('扫码连接'),
        const SizedBox(height: 8),
        CupertinoSettingsGroupCard(
          margin: EdgeInsets.zero,
          backgroundColor: sectionBackground,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: qrUrl == null
                  ? Row(
                      children: [
                        Icon(CupertinoIcons.qrcode, color: iconColor),
                        const SizedBox(width: 12),
                        const Expanded(child: Text('正在生成二维码...')),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: CupertinoColors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: QrImageView(
                                data: RemoteAccessQrService.buildPayload(
                                  baseUrl: qrUrl,
                                  candidateBaseUrls: qrCandidateUrls,
                                ),
                                version: QrVersions.auto,
                                size: 156,
                                backgroundColor: CupertinoColors.white,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '二维码地址',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    qrUrl,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: resolveSettingsSecondaryTextColor(
                                          context),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(30, 30),
                                    onPressed: () => _copyUrl(qrUrl),
                                    child: const Text('复制地址'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (qrCandidateUrls.length > 1) ...[
                          const SizedBox(height: 12),
                          Text(
                            '候选地址 ${qrCandidateUrls.length} 个，扫码后自动按顺序尝试',
                            style: TextStyle(
                              color: resolveSettingsSecondaryTextColor(context),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTrustedDevicesGroup({
    required Color sectionBackground,
    required Color tileBackground,
    required Color iconColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('受信任设备'),
        const SizedBox(height: 8),
        CupertinoSettingsGroupCard(
          margin: EdgeInsets.zero,
          backgroundColor: sectionBackground,
          addDividers: true,
          dividerIndent: 16,
          children: [
            if (_isLoadingTrustedDevices)
              CupertinoSettingsTile(
                leading: Icon(CupertinoIcons.shield, color: iconColor),
                title: const Text('正在加载'),
                trailing: const CupertinoActivityIndicator(radius: 8),
                backgroundColor: tileBackground,
              )
            else if (_trustedDevices.isEmpty)
              CupertinoSettingsTile(
                leading: Icon(CupertinoIcons.shield, color: iconColor),
                title: const Text('暂无受信任设备'),
                subtitle: const Text('新的控制端请求会在播放器上弹出确认'),
                backgroundColor: tileBackground,
              )
            else
              ..._trustedDevices.map(
                (device) => _buildTrustedDeviceTile(
                  device: device,
                  backgroundColor: tileBackground,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTrustedDeviceTile({
    required Map<String, dynamic> device,
    required Color backgroundColor,
  }) {
    final clientName = device['clientName'] as String? ?? '未知设备';
    final platform = device['platform'] as String? ?? '未知平台';
    final remoteIp = device['remoteIp'] as String? ?? '未知 IP';
    final trustedAt = device['trustedAt'] as String? ?? '';
    final clientKey = device['clientKey'] as String? ?? '';
    return CupertinoSettingsTile(
      leading: Icon(
        CupertinoIcons.device_phone_portrait,
        color: resolveSettingsIconColor(context),
      ),
      title: Text(clientName),
      subtitle:
          Text('$platform · $remoteIp · ${_formatTrustedTime(trustedAt)}'),
      backgroundColor: backgroundColor,
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(32, 32),
        onPressed:
            clientKey.isEmpty ? null : () => _removeTrustedDevice(clientKey),
        child: Icon(
          CupertinoIcons.delete,
          size: 20,
          color: CupertinoDynamicColor.resolve(
            CupertinoColors.destructiveRed,
            context,
          ),
        ),
      ),
    );
  }

  String _formatTrustedTime(String value) {
    if (value.isEmpty) return '未知时间';
    try {
      final date = DateTime.parse(value);
      final month = date.month.toString().padLeft(2, '0');
      final day = date.day.toString().padLeft(2, '0');
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '${date.year}-$month-$day $hour:$minute';
    } catch (_) {
      return value;
    }
  }
}
