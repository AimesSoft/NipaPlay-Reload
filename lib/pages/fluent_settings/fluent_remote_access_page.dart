import 'dart:async';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/providers/service_provider.dart';

class FluentRemoteAccessPage extends StatefulWidget {
  const FluentRemoteAccessPage({super.key});

  @override
  State<FluentRemoteAccessPage> createState() => _FluentRemoteAccessPageState();
}

class _FluentRemoteAccessPageState extends State<FluentRemoteAccessPage> {
  bool _webServerEnabled = false;
  List<String> _accessUrls = const [];
  String? _publicIpUrl;
  bool _isLoadingPublicIp = false;
  bool _isBusy = false;
  int _currentPort = 8080;

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

      await server.setAutoStart(enabled);
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
      items.add(_AccessUrlTile(
        url: url,
        iconData: FluentIcons.plug_connected,
        onCopy: () => _copyUrl(url),
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
      items.add(_AccessUrlTile(
        url: _publicIpUrl!,
        iconData: FluentIcons.globe,
        onCopy: () => _copyUrl(_publicIpUrl!),
        isPublic: true,
      ));
    }

    return Column(children: items);
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
  final bool isPublic;

  const _AccessUrlTile({
    required this.url,
    required this.iconData,
    required this.onCopy,
    this.isPublic = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: theme.cardColor.withOpacity(0.6),
        border: Border.all(
          color: isPublic
              ? theme.accentColor.withOpacity(0.4)
              : theme.resources.controlStrokeColorDefault,
        ),
      ),
      child: Row(
        children: [
          Icon(iconData),
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
