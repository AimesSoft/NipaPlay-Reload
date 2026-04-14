import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/services/remote_control_settings.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/fluent_settings_switch.dart';

class RemoteReceiverPage extends StatefulWidget {
  const RemoteReceiverPage({super.key});

  @override
  State<RemoteReceiverPage> createState() => _RemoteReceiverPageState();
}

class _RemoteReceiverPageState extends State<RemoteReceiverPage> {
  bool _receiverEnabled = true;
  bool _webServerEnabled = false;
  int _port = 1180;
  List<String> _accessUrls = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final server = ServiceProvider.webServer;
    final receiverEnabled = await RemoteControlSettings.isReceiverEnabled();
    final urls =
        server.isRunning ? await server.getAccessUrls() : const <String>[];
    if (!mounted) return;
    setState(() {
      _receiverEnabled = receiverEnabled;
      _webServerEnabled = server.isRunning;
      _port = server.port;
      _accessUrls = urls;
    });
  }

  Future<void> _toggleReceiver(bool enabled) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _receiverEnabled = enabled;
    });
    try {
      await RemoteControlSettings.setReceiverEnabled(enabled);
      final server = ServiceProvider.webServer;
      if (enabled && !server.isRunning) {
        final started = await server.startServer();
        if (!mounted) return;
        if (!started) {
          BlurSnackBar.show(
            context,
            '被遥控端开启失败: ${server.lastStartErrorMessage ?? '未知错误'}',
          );
        }
      }
      await _loadState();
      if (!mounted) return;
      BlurSnackBar.show(context, enabled ? '被遥控端已开启' : '被遥控端已关闭');
    } catch (e) {
      if (!mounted) return;
      BlurSnackBar.show(context, '操作失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggleWebServer(bool enabled) async {
    if (_loading) return;
    setState(() {
      _loading = true;
    });
    try {
      final server = ServiceProvider.webServer;
      if (enabled) {
        final started = await server.startServer();
        if (!mounted) return;
        if (!started) {
          BlurSnackBar.show(
            context,
            '远程服务启动失败: ${server.lastStartErrorMessage ?? '未知错误'}',
          );
        }
      } else {
        await server.stopServer();
      }
      await _loadState();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _copyAddress(String url) {
    Clipboard.setData(ClipboardData(text: url));
    BlurSnackBar.show(context, '地址已复制');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Icon(
              Ionicons.tv_outline,
              color: colorScheme.onSurface,
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(
              '被遥控端',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '开启后，局域网内控制端可自动发现本设备并获取播放器菜单参数进行遥控。',
          style: TextStyle(
            color: colorScheme.onSurface.withValues(alpha: 0.72),
          ),
        ),
        const SizedBox(height: 18),
        _settingRow(
          icon: Icons.settings_remote,
          title: '启用被遥控端',
          subtitle: '仅控制遥控接口，不影响其他功能',
          trailing: FluentSettingsSwitch(
            value: _receiverEnabled,
            onChanged: _toggleReceiver,
          ),
        ),
        _settingRow(
          icon: Icons.wifi_tethering,
          title: '远程服务',
          subtitle: _webServerEnabled ? '运行中（端口 $_port）' : '未运行',
          trailing: FluentSettingsSwitch(
            value: _webServerEnabled,
            onChanged: _toggleWebServer,
          ),
        ),
        const SizedBox(height: 10),
        Divider(color: colorScheme.onSurface.withValues(alpha: 0.14)),
        const SizedBox(height: 10),
        Text(
          '连接地址',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (_accessUrls.isEmpty)
          Text(
            _webServerEnabled ? '正在获取地址...' : '请先开启远程服务',
            style:
                TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.7)),
          )
        else
          ..._accessUrls.map(_addressRow),
      ],
    );
  }

  Widget _addressRow(String url) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.link,
            size: 14,
            color: colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              url,
              style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.72)),
            ),
          ),
          IconButton(
            onPressed: () => _copyAddress(url),
            icon: const Icon(Icons.copy, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _settingRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 20, color: colorScheme.onSurface.withValues(alpha: 0.7)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
