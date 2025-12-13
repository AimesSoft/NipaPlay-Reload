import 'dart:async';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/utils/remote_access_address_utils.dart';

class FluentRemoteAccessPage extends StatefulWidget {
  const FluentRemoteAccessPage({super.key});

  @override
  State<FluentRemoteAccessPage> createState() => _FluentRemoteAccessPageState();
}

class _FluentRemoteAccessPageState extends State<FluentRemoteAccessPage> {
  bool _webServerEnabled = false;
  bool _autoStartEnabled = false;
  List<String> _accessUrls = const [];
  String? _publicIpUrl;
  bool _isLoadingPublicIp = false;
  bool _isBusy = false;
  int _currentPort = 1180;

  @override
  void initState() {
    super.initState();
    _loadWebServerState();
  }

  Future<void> _loadWebServerState() async {
    final server = ServiceProvider.webServer;
    await server.loadSettings();
    if (!mounted) return;

    setState(() {
      _webServerEnabled = server.isRunning;
      _autoStartEnabled = server.autoStart;
      _currentPort = server.port;
    });

    if (_webServerEnabled) {
      await _updateAccessUrls();
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
    if (!_webServerEnabled) {
      return;
    }

    setState(() {
      _isLoadingPublicIp = true;
    });

    try {
      final response = await http
          .get(Uri.parse('https://api.ipify.org'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final ip = response.body.trim();
        if (ip.isNotEmpty && !ip.contains('<') && !ip.contains('>')) {
          setState(() {
            _publicIpUrl = 'http://$ip:$_currentPort';
          });
        }
      }
    } catch (e) {
      debugPrint('[RemoteAccess] 获取公网IP失败: $e');
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
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _webServerEnabled = enabled;
    });

    final server = ServiceProvider.webServer;
    try {
      if (enabled) {
        final success = await server.startServer(port: _currentPort);
        if (success) {
          _showInfoBar('Web服务器已启动', severity: InfoBarSeverity.success);
          await _updateAccessUrls();
        } else {
          _showInfoBar('Web服务器启动失败', severity: InfoBarSeverity.error);
          setState(() {
            _webServerEnabled = false;
          });
        }
      } else {
        await server.stopServer();
        _showInfoBar('Web服务器已停止');
        setState(() {
          _accessUrls = const [];
          _publicIpUrl = null;
        });
      }
    } catch (e) {
      _showInfoBar('操作失败: $e', severity: InfoBarSeverity.error);
      setState(() {
        _webServerEnabled = !enabled;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _toggleAutoStart(bool enabled) async {
    if (_isBusy) return;
    setState(() {
      _autoStartEnabled = enabled;
    });

    try {
      await ServiceProvider.webServer.setAutoStart(enabled);
      if (enabled) {
        _showInfoBar('已开启自动开启：下次启动将自动启用远程访问', severity: InfoBarSeverity.success);
      } else {
        if (_webServerEnabled) {
          _showInfoBar('已关闭自动开启（当前服务仍在运行）', severity: InfoBarSeverity.info);
        } else {
          _showInfoBar('已关闭自动开启', severity: InfoBarSeverity.info);
        }
      }
    } catch (e) {
      _showInfoBar('操作失败: $e', severity: InfoBarSeverity.error);
      setState(() {
        _autoStartEnabled = !enabled;
      });
    }
  }

  void _copyUrl(String url) {
    Clipboard.setData(ClipboardData(text: url));
    _showInfoBar('访问地址已复制到剪贴板', severity: InfoBarSeverity.success);
  }

  Future<void> _showPortDialog() async {
    final controller = TextEditingController(text: _currentPort.toString());
    int? newPort;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return ContentDialog(
          title: const Text('设置服务器端口'),
          content: TextBox(
            controller: controller,
            placeholder: '端口 (1-65535)',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          actions: [
            Button(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final value = int.tryParse(controller.text);
                if (value == null || value <= 0 || value >= 65536) {
                  _showInfoBar('请输入有效的端口号 (1-65535)', severity: InfoBarSeverity.warning);
                  return;
                }
                newPort = value;
                Navigator.pop(context);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );

    if (newPort != null && newPort != _currentPort) {
      setState(() {
        _currentPort = newPort!;
      });
      final server = ServiceProvider.webServer;
      await server.setPort(newPort!);
      _showInfoBar('端口已更新，将重新应用配置');
      if (_webServerEnabled) {
        await _toggleWebServer(true);
      }
    }
  }

  void _showInfoBar(
    String message, {
    InfoBarSeverity severity = InfoBarSeverity.info,
  }) {
    displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: Text(_infoBarTitle(severity)),
        severity: severity,
        content: Text(message),
        action: IconButton(
          icon: const Icon(FluentIcons.clear),
          onPressed: close,
        ),
      ),
    );
  }

  String _infoBarTitle(InfoBarSeverity severity) {
    switch (severity) {
      case InfoBarSeverity.success:
        return '成功';
      case InfoBarSeverity.warning:
        return '警告';
      case InfoBarSeverity.error:
        return '错误';
      case InfoBarSeverity.info:
      default:
        return '提示';
    }
  }

  Widget _buildAccessAddresses() {
    if (!_webServerEnabled) {
      return const SizedBox.shrink();
    }

    final textStyle = FluentTheme.of(context).typography.caption;

    if (_accessUrls.isEmpty && !_isLoadingPublicIp) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Text('正在获取访问地址...', style: textStyle),
      );
    }

    final items = <Widget>[];
    for (final url in _accessUrls) {
      final type = RemoteAccessAddressUtils.classifyUrl(url);
      final label = RemoteAccessAddressUtils.labelZh(type);
      final iconData = switch (type) {
        RemoteAccessAddressType.local => FluentIcons.home,
        RemoteAccessAddressType.lan => FluentIcons.wifi,
        RemoteAccessAddressType.wan => FluentIcons.globe,
        RemoteAccessAddressType.unknown => FluentIcons.plug_connected,
      };

      items.add(_AccessUrlTile(
        url: url,
        iconData: iconData,
        onCopy: () => _copyUrl(url),
        type: type,
        typeLabel: label,
      ));
    }

    if (_isLoadingPublicIp) {
      items.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            const SizedBox(width: 16, height: 16, child: ProgressRing(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text('正在获取公网IP...', style: textStyle),
          ],
        ),
      ));
    } else if (_publicIpUrl != null) {
      final type = RemoteAccessAddressUtils.classifyUrl(_publicIpUrl!);
      final label = RemoteAccessAddressUtils.labelZh(type);
      items.add(_AccessUrlTile(
        url: _publicIpUrl!,
        iconData: FluentIcons.globe,
        onCopy: () => _copyUrl(_publicIpUrl!),
        type: type,
        typeLabel: label,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '选择建议：\n'
          '• 本机：仅在这台设备上访问（localhost/127.0.0.1）\n'
          '• 内网：同一 Wi‑Fi/局域网的其他设备访问（推荐）\n'
          '• 外网：需要公网 IP + 路由器端口转发/防火墙放行后才能访问（注意安全）',
          style: textStyle?.copyWith(height: 1.35),
        ),
        const SizedBox(height: 12),
        ...items,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(title: Text('远程访问')),
      content: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(FluentIcons.globe, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Web 远程访问',
                            style: FluentTheme.of(context)
                                .typography
                                .subtitle
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          if (_webServerEnabled)
                            InfoBadge(
                              source: const Text('运行中'),
                              color: const Color(0xFF107C10),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '启用后可通过浏览器访问此设备的媒体库，并支持其他 NipaPlay 客户端连接。',
                        style: FluentTheme.of(context).typography.body,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: InfoLabel(
                              label: '启用 Web 服务器',
                              child: Text(
                                '允许远程访问媒体库',
                                style: FluentTheme.of(context)
                                    .typography
                                    .caption,
                              ),
                            ),
                          ),
                          ToggleSwitch(
                            checked: _webServerEnabled,
                            onChanged: _isBusy ? null : _toggleWebServer,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: InfoLabel(
                              label: '软件打开自动开启远程访问',
                              child: Text(
                                '启动 NipaPlay 时自动开启 Web 远程访问（不影响手动开关）',
                                style: FluentTheme.of(context).typography.caption,
                              ),
                            ),
                          ),
                          ToggleSwitch(
                            checked: _autoStartEnabled,
                            onChanged: _isBusy ? null : _toggleAutoStart,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      AnimatedOpacity(
                        opacity: _webServerEnabled ? 1 : 0.4,
                        duration: const Duration(milliseconds: 200),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InfoLabel(
                              label: '访问地址',
                              child: _buildAccessAddresses(),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                InfoLabel(
                                  label: '端口',
                                  child: Text('$_currentPort'),
                                ),
                                const SizedBox(width: 12),
                                Button(
                                  onPressed:
                                      _webServerEnabled ? _showPortDialog : _showPortDialog,
                                  child: const Text('修改端口'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class _AccessUrlTile extends StatelessWidget {
  final String url;
  final IconData iconData;
  final VoidCallback onCopy;
  final RemoteAccessAddressType type;
  final String typeLabel;

  const _AccessUrlTile({
    required this.url,
    required this.iconData,
    required this.onCopy,
    required this.type,
    required this.typeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final tagColor = switch (type) {
      RemoteAccessAddressType.local => const Color(0xFF0078D4),
      RemoteAccessAddressType.lan => const Color(0xFF107C10),
      RemoteAccessAddressType.wan => const Color(0xFFD83B01),
      RemoteAccessAddressType.unknown => theme.resources.controlStrokeColorDefault,
    };

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: theme.cardColor.withOpacity(0.6),
        border: Border.all(
          color: tagColor.withOpacity(0.45),
        ),
      ),
      child: Row(
        children: [
          Icon(iconData),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: tagColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: tagColor.withOpacity(0.35)),
            ),
            child: Text(
              typeLabel,
              style: theme.typography.caption?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              url,
              style: theme.typography.body?.copyWith(fontFamily: 'monospace'),
            ),
          ),
          IconButton(
            icon: const Icon(FluentIcons.copy),
            onPressed: onCopy,
            style: ButtonStyle(
              padding: ButtonState.all(const EdgeInsets.all(6)),
            ),
          ),
        ],
      ),
    );
  }
}
