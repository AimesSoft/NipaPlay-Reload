// remote_access_page.dart
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/fluent_settings_switch.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/utils/remote_access_address_utils.dart';

class RemoteAccessPage extends StatefulWidget {
  const RemoteAccessPage({super.key});

  @override
  State<RemoteAccessPage> createState() => _RemoteAccessPageState();
}

class _RemoteAccessPageState extends State<RemoteAccessPage> {
  // Remote access service state
  bool _webServerEnabled = false;
  bool _autoStartEnabled = false;
  List<String> _accessUrls = [];
  String? _publicIpUrl;
  bool _isLoadingPublicIp = false;
  int _currentPort = 1180;

  @override
  void initState() {
    super.initState();
    _loadWebServerState();
  }

  Future<void> _loadWebServerState() async {
    final server = ServiceProvider.webServer;
    await server.loadSettings();
    if (mounted) {
      setState(() {
        _webServerEnabled = server.isRunning;
        _autoStartEnabled = server.autoStart;
        _currentPort = server.port;
        if (_webServerEnabled) {
          _updateAccessUrls();
        }
      });
    }
  }

  Future<void> _updateAccessUrls() async {
    final urls = await ServiceProvider.webServer.getAccessUrls();
    if (mounted) {
      setState(() {
        _accessUrls = urls;
      });
      // 尝试获取公网IP
      _fetchPublicIp();
    }
  }
  
  Future<void> _fetchPublicIp() async {
    if (!_webServerEnabled) return;
    
    setState(() {
      _isLoadingPublicIp = true;
    });
    
    try {
      // 尝试从多个API获取公网IP
      final response = await http.get(Uri.parse('https://api.ipify.org')).timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception('获取公网IP超时'),
      );
      
      if (response.statusCode == 200) {
        final ip = response.body.trim();
        // 确保是有效的IP地址
        if (ip.isNotEmpty && !ip.contains('<') && !ip.contains('>')) {
          setState(() {
            _publicIpUrl = 'http://$ip:$_currentPort';
            _isLoadingPublicIp = false;
          });
        } else {
          throw Exception('获取到无效的公网IP');
        }
      } else {
        throw Exception('获取公网IP失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('获取公网IP出错: $e');
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
        BlurSnackBar.show(context, '远程访问服务已启动');
        _updateAccessUrls();
      } else {
        setState(() {
          _webServerEnabled = false;
          _accessUrls = [];
          _publicIpUrl = null;
        });
        _showStartServerErrorDialog(
          server.lastStartErrorMessage ?? '未知原因',
        );
      }
    } else {
      await server.stopServer();
      if (!mounted) return;
      BlurSnackBar.show(context, '远程访问服务已停止');
      setState(() {
        _accessUrls = [];
        _publicIpUrl = null;
      });
    }
  }

  Future<void> _toggleAutoStart(bool enabled) async {
    setState(() {
      _autoStartEnabled = enabled;
    });

    await ServiceProvider.webServer.setAutoStart(enabled);

    if (enabled) {
      BlurSnackBar.show(context, '已开启自动开启：下次启动将自动启用远程访问');
    } else {
      if (_webServerEnabled) {
        BlurSnackBar.show(context, '已关闭自动开启（当前服务仍在运行）');
      } else {
        BlurSnackBar.show(context, '已关闭自动开启');
      }
    }
  }

  void _copyUrl(String url) {
    Clipboard.setData(ClipboardData(text: url));
    BlurSnackBar.show(context, '访问地址已复制到剪贴板');
  }

  void _showStartServerErrorDialog(String message) {
    final colorScheme = Theme.of(context).colorScheme;
    BlurDialog.show(
      context: context,
      title: '远程访问服务启动失败',
      content: message,
      actions: [
        HoverScaleTextButton(
          text: '确定',
          idleColor: colorScheme.onSurface,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  void _showPortDialog() async {
    final colorScheme = Theme.of(context).colorScheme;
    final portController = TextEditingController(text: _currentPort.toString());
    final newPort = await BlurDialog.show<int>(
      context: context,
      title: '设置远程访问端口',
      contentWidget: TextField(
        controller: portController,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        cursorColor: const Color(0xFFFF2E55),
        decoration: InputDecoration(
          labelText: '端口 (1-65535)',
          labelStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: colorScheme.onSurface),
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: colorScheme.onSurface.withOpacity(0.38)),
          ),
        ),
        style: const TextStyle(color: Color(0xFFFF2E55)),
      ),
      actions: [
        HoverScaleTextButton(
          text: '取消',
          idleColor: colorScheme.onSurface.withOpacity(0.7),
          onPressed: () => Navigator.of(context).pop(),
        ),
        HoverScaleTextButton(
          text: '确定',
          idleColor: colorScheme.onSurface,
          onPressed: () {
            final port = int.tryParse(portController.text);
            if (port != null && port > 0 && port < 65536) {
              Navigator.of(context).pop(port);
            } else {
              BlurSnackBar.show(context, '请输入有效的端口号 (1-65535)');
            }
          },
        ),
      ],
    );

    if (newPort != null && newPort != _currentPort) {
      final wasRunning = _webServerEnabled;
      setState(() {
        _currentPort = newPort;
      });
      final server = ServiceProvider.webServer;
      await server.setPort(newPort);
      if (!mounted) return;
      if (wasRunning) {
        if (server.isRunning) {
          BlurSnackBar.show(context, '远程访问端口已更新，服务已重启');
          _updateAccessUrls();
        } else {
          setState(() {
            _webServerEnabled = false;
            _accessUrls = [];
            _publicIpUrl = null;
          });
          _showStartServerErrorDialog(
            server.lastStartErrorMessage ?? '未知原因',
          );
        }
      } else {
        BlurSnackBar.show(context, '远程访问端口已更新');
      }
    }
  }

  TextStyle _pageTextStyle(BuildContext context) {
    final textStyle = DefaultTextStyle.of(context).style;
    final themeFont = Theme.of(context).fontFamily;
    final fontFamily = textStyle.fontFamily ?? themeFont;
    return TextStyle(fontFamily: fontFamily);
  }

  TextStyle _monospaceStyle(BuildContext context, Color color) {
    final textStyle = DefaultTextStyle.of(context).style;
    final themeFont = Theme.of(context).fontFamily;
    final fallback = <String>[];
    final baseFont = textStyle.fontFamily;
    if (baseFont != null) {
      fallback.add(baseFont);
    }
    if (themeFont != null && themeFont != baseFont) {
      fallback.add(themeFont);
    }
    return TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: fallback.isEmpty ? null : fallback,
      color: color,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        _buildWebServerSection(),
      ],
    );
  }

  Widget _buildWebServerSection() {
    final colorScheme = Theme.of(context).colorScheme;
    return DefaultTextStyle.merge(
      style: _pageTextStyle(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Ionicons.globe_outline,
                color: colorScheme.onSurface,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                '远程访问',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              if (_webServerEnabled)
                Text(
                  '已启用',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          Text(
            '启用后可供其他 NipaPlay 客户端远程访问本机媒体库。此功能正在开发中，部分功能可能不完整。',
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.7),
              fontSize: 14,
            ),
          ),

          const SizedBox(height: 16),
          
          // 启用/禁用开关
          _buildSettingItem(
            icon: Icons.power_settings_new,
            title: '启用远程访问服务',
            subtitle: '允许其他 NipaPlay 客户端远程访问本机媒体库',
            trailing: FluentSettingsSwitch(
              value: _webServerEnabled,
              onChanged: _toggleWebServer,
            ),
          ),

          // 自动开启
          _buildSettingItem(
            icon: Icons.auto_awesome,
            title: '软件打开自动开启远程访问',
            subtitle: '启动 NipaPlay 时自动开启远程访问服务（不影响手动开关）',
            trailing: FluentSettingsSwitch(
              value: _autoStartEnabled,
              onChanged: _toggleAutoStart,
            ),
          ),

          const SizedBox(height: 8),
          Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
          const SizedBox(height: 8),

          if (_webServerEnabled) ...[
            // 访问地址
            _buildAccessAddressSection(),

            const SizedBox(height: 8),
            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
            const SizedBox(height: 8),
          ],

          // 端口设置
          _buildSettingItem(
            icon: Icons.settings_ethernet,
            title: '端口设置',
            subtitle: '当前端口: $_currentPort',
            trailing: _HoverScaleIconButton(
              icon: Icons.edit,
              onPressed: _showPortDialog,
              idleColor: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildAccessAddressSection() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.link,
                color: colorScheme.onSurface.withOpacity(0.7),
                size: 20,
              ),
              const SizedBox(width: 16),
              Text(
                '客户端连接地址',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '选择建议：\n'
            '• 本机：仅在这台设备上访问（localhost/127.0.0.1）\n'
            '• 内网：同一 Wi‑Fi/局域网的其他设备访问（推荐）\n'
            '• 外网：需要公网 IP + 路由器端口转发/防火墙放行后才能访问（注意安全）',
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.6),
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          if (_accessUrls.isEmpty)
            Text('正在获取地址...', style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)))
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._accessUrls.map((url) => _buildAddressItem(url)),
                if (_isLoadingPublicIp)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(colorScheme.onSurface),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '正在获取公网IP...',
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.7),
                          )
                        ),
                      ],
                    ),
                  )
                else if (_publicIpUrl != null)
                  _buildAddressItem(_publicIpUrl!),
              ],
            ),
        ],
      ),
    );
  }
  
  Widget _buildAddressItem(String url) {
    final colorScheme = Theme.of(context).colorScheme;
    final type = RemoteAccessAddressUtils.classifyUrl(url);
    final label = RemoteAccessAddressUtils.labelZh(type);
    final (iconData, tagColor) = switch (type) {
      RemoteAccessAddressType.local => (Icons.computer, colorScheme.primary),
      RemoteAccessAddressType.lan => (Icons.lan, colorScheme.secondary),
      RemoteAccessAddressType.wan => (Icons.public, colorScheme.tertiary),
      RemoteAccessAddressType.unknown => (Icons.link, colorScheme.onSurface.withOpacity(0.38)),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(iconData, color: tagColor, size: 14),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: tagColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              url,
              style: _monospaceStyle(
                context,
                colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.copy, color: colorScheme.onSurface),
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            onPressed: () => _copyUrl(url),
            //tooltip: '复制地址',
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: colorScheme.onSurface.withOpacity(0.7),
            size: 20,
          ),
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
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}

class _HoverScaleIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? idleColor;
  final Color hoverColor;
  final double size;
  final double hoverScale;
  final EdgeInsetsGeometry padding;

  const _HoverScaleIconButton({
    required this.icon,
    required this.onPressed,
    this.idleColor,
    this.hoverColor = const Color(0xFFFF2E55),
    this.size = 20,
    this.hoverScale = 1.1,
    this.padding = const EdgeInsets.all(6),
  });

  @override
  State<_HoverScaleIconButton> createState() => _HoverScaleIconButtonState();
}

class _HoverScaleIconButtonState extends State<_HoverScaleIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final baseColor =
        widget.idleColor ?? Theme.of(context).colorScheme.onSurface;
    final color = _isHovered ? widget.hoverColor : baseColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _isHovered ? widget.hoverScale : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          child: Padding(
            padding: widget.padding,
            child: Icon(widget.icon, size: widget.size, color: color),
          ),
        ),
      ),
    );
  }
}
