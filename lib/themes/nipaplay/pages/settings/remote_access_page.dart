// remote_access_page.dart
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_card.dart';
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
      if (success) {
        BlurSnackBar.show(context, '远程访问服务已启动');
        _updateAccessUrls();
      } else {
        BlurSnackBar.show(context, '远程访问服务启动失败');
        setState(() {
          _webServerEnabled = false;
        });
      }
    } else {
      await server.stopServer();
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

  void _showPortDialog() async {
    final portController = TextEditingController(text: _currentPort.toString());
    final newPort = await BlurDialog.show<int>(
      context: context,
      title: '设置远程访问端口',
      contentWidget: TextField(
        controller: portController,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: '端口 (1-65535)',
          labelStyle: TextStyle(color: Colors.white70),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white),
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white38),
          ),
        ),
        style: const TextStyle(color: Colors.white),
      ),
      actions: [
        TextButton(
          child: const Text('取消', style: TextStyle(color: Colors.white70)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        TextButton(
          child: const Text('确定', style: TextStyle(color: Colors.white)),
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
      setState(() {
        _currentPort = newPort;
      });
      await ServiceProvider.webServer.setPort(newPort);
      BlurSnackBar.show(context, '远程访问端口已更新，正在重启服务...');
      _updateAccessUrls();
    }
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
    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Ionicons.globe_outline,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 12),
              const Text(
                '远程访问',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              if (_webServerEnabled)
                Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                      child: const Text(
                        '已启用',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              
              const SizedBox(height: 16),

              const Text(
                '启用后可供其他 NipaPlay 客户端远程访问本机媒体库。此功能正在开发中，部分功能可能不完整。',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 16),
              
              // 启用/禁用开关
              _buildSettingItem(
                icon: Icons.power_settings_new,
                title: '启用远程访问服务',
                subtitle: '允许其他 NipaPlay 客户端远程访问本机媒体库',
                trailing: Switch(
                  value: _webServerEnabled,
                  onChanged: _toggleWebServer,
                  activeColor: Colors.white,
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: const Color.fromARGB(255, 0, 0, 0),
                ),
              ),

              // 自动开启
              _buildSettingItem(
                icon: Icons.auto_awesome,
                title: '软件打开自动开启远程访问',
                subtitle: '启动 NipaPlay 时自动开启远程访问服务（不影响手动开关）',
                trailing: Switch(
                  value: _autoStartEnabled,
                  onChanged: _toggleAutoStart,
                  activeColor: Colors.white,
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: const Color.fromARGB(255, 0, 0, 0),
                ),
              ),
              
              if (_webServerEnabled) ...[
                const SizedBox(height: 8),
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 8),
                
                // 访问地址
                _buildAccessAddressSection(),
                
                const SizedBox(height: 8),
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 8),
                
                // 端口设置
                _buildSettingItem(
                  icon: Icons.settings_ethernet,
                  title: '端口设置',
                  subtitle: '当前端口: $_currentPort',
                  trailing: IconButton(
                    icon: const Icon(Icons.edit, color: Colors.white),
                    onPressed: _showPortDialog,
                  ),
                ),
              ],
        ],
      ),
    );
  }
  
  Widget _buildAccessAddressSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.link,
                color: Colors.white70,
                size: 20,
              ),
              SizedBox(width: 16),
              Text(
                '客户端连接地址',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '选择建议：\n'
            '• 本机：仅在这台设备上访问（localhost/127.0.0.1）\n'
            '• 内网：同一 Wi‑Fi/局域网的其他设备访问（推荐）\n'
            '• 外网：需要公网 IP + 路由器端口转发/防火墙放行后才能访问（注意安全）',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          if (_accessUrls.isEmpty)
            const Text('正在获取地址...', style: TextStyle(color: Colors.white70))
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._accessUrls.map((url) => _buildAddressItem(url)),
                if (_isLoadingPublicIp)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          '正在获取公网IP...',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: Colors.white70
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
    final type = RemoteAccessAddressUtils.classifyUrl(url);
    final label = RemoteAccessAddressUtils.labelZh(type);
    final (iconData, tagColor) = switch (type) {
      RemoteAccessAddressType.local => (Icons.computer, Colors.blueAccent),
      RemoteAccessAddressType.lan => (Icons.lan, Colors.greenAccent),
      RemoteAccessAddressType.wan => (Icons.public, Colors.orangeAccent),
      RemoteAccessAddressType.unknown => (Icons.link, Colors.white38),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(
            iconData,
            color: Colors.white38,
            size: 14,
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: tagColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tagColor.withOpacity(0.35)),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              url,
              style: const TextStyle(
                fontFamily: 'monospace',
                color: Colors.white70
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: Colors.white70,
            size: 20,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white70,
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
