import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/widgets/blur_snackbar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:flutter/services.dart';

// Define the key for SharedPreferences
const String globalFilterAdultContentKey = 'global_filter_adult_content';
const String defaultPageIndexKey = 'default_page_index';

class GeneralPage extends StatefulWidget {
  const GeneralPage({super.key});

  @override
  State<GeneralPage> createState() => _GeneralPageState();
}

class _GeneralPageState extends State<GeneralPage> {
  bool _filterAdultContent = true;
  int _defaultPageIndex = 0;
  final GlobalKey _defaultPageDropdownKey = GlobalKey();

  // Web Server State
  bool _webServerEnabled = false;
  List<String> _accessUrls = [];
  int _currentPort = 8080;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _loadWebServerState();
  }

  Future<void> _loadWebServerState() async {
    final server = ServiceProvider.webServer;
    await server.loadSettings();
    if (mounted) {
      setState(() {
        _webServerEnabled = server.isRunning;
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
        BlurSnackBar.show(context, 'Web服务器已启动');
        _updateAccessUrls();
      } else {
        BlurSnackBar.show(context, 'Web服务器启动失败');
        setState(() {
          _webServerEnabled = false;
        });
      }
    } else {
      await server.stopServer();
      BlurSnackBar.show(context, 'Web服务器已停止');
      setState(() {
        _accessUrls = [];
      });
    }
    // 保存自动启动设置
    await ServiceProvider.webServer.setAutoStart(enabled);
  }

  void _copyUrls() {
    final allUrls = _accessUrls.join('\\n');
    Clipboard.setData(ClipboardData(text: allUrls));
    BlurSnackBar.show(context, '所有访问地址已复制到剪贴板');
  }

  void _showPortDialog() async {
    final portController = TextEditingController(text: _currentPort.toString());
    final newPort = await BlurDialog.show<int>(
      context: context,
      title: '设置Web服务器端口',
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
      BlurSnackBar.show(context, 'Web服务器端口已更新，正在重启服务...');
      _updateAccessUrls();
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _filterAdultContent = prefs.getBool(globalFilterAdultContentKey) ?? true;
        _defaultPageIndex = prefs.getInt(defaultPageIndexKey) ?? 0;
      });
    }
  }

  Future<void> _saveFilterPreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(globalFilterAdultContentKey, value);
  }

  Future<void> _saveDefaultPagePreference(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(defaultPageIndexKey, index);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        ListTile(
          title: const Text(
            "默认展示页面",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          subtitle: const Text(
            "选择应用启动后默认显示的页面",
            style: TextStyle(color: Colors.white70),
          ),
          trailing: BlurDropdown<int>(
            dropdownKey: _defaultPageDropdownKey,
            items: [
              DropdownMenuItemData(title: "视频播放", value: 0, isSelected: _defaultPageIndex == 0),
              DropdownMenuItemData(title: "媒体库", value: 1, isSelected: _defaultPageIndex == 1),
              DropdownMenuItemData(title: "新番更新", value: 2, isSelected: _defaultPageIndex == 2),
              DropdownMenuItemData(title: "设置", value: 3, isSelected: _defaultPageIndex == 3),
            ],
            onItemSelected: (index) {
              setState(() {
                _defaultPageIndex = index;
              });
              _saveDefaultPagePreference(index);
            },
          ),
        ),
        const Divider(color: Colors.white12, height: 1),
        SwitchListTile(
          title: const Text(
            "过滤成人内容 (全局)",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          subtitle: const Text(
            "在新番列表等处隐藏成人内容",
            style: TextStyle(color: Colors.white70),
          ),
          value: _filterAdultContent,
          onChanged: (bool value) {
            setState(() {
              _filterAdultContent = value;
            });
            _saveFilterPreference(value);
          },
          activeColor: Colors.white,
          inactiveThumbColor: Colors.white,
          inactiveTrackColor: const Color.fromARGB(255, 0, 0, 0),
          //secondary: Icon(Ionicons.eye_off_outline, color: _filterAdultContent ? const Color.fromARGB(255, 255, 255, 255) : const Color.fromARGB(184, 236, 236, 236)),
        ),
        const Divider(color: Colors.white12, height: 1),
        _buildWebServerSettings(),
        const Divider(color: Colors.white12, height: 1),
        ListTile(
          title: const Text(
            "清除图片缓存",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          subtitle: const Text(
            "清除所有缓存的图片文件",
            style: TextStyle(color: Colors.white70),
          ),
          trailing: const Icon(Ionicons.trash_outline, color: Colors.white),
          onTap: () async {
            final bool? confirm = await BlurDialog.show<bool>(
              context: context,
              title: '确认清除缓存',
              content: '确定要清除所有缓存的图片文件吗？',
              actions: [
                TextButton(
                  child: const Text(
                    '取消',
                    style: TextStyle(color: Colors.white70),
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                TextButton(
                  child: const Text(
                    '确定',
                    style: TextStyle(color: Colors.white),
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            );

            if (confirm == true) {
              try {
                await ImageCacheManager.instance.clearCache();
                if (context.mounted) {
                  BlurSnackBar.show(context, '图片缓存已清除');
                }
              } catch (e) {
                if (context.mounted) {
                  BlurSnackBar.show(context, '清除缓存失败: $e');
                }
              }
            }
          },
        ),
        const Divider(color: Colors.white12, height: 1),
      ],
    );
  }

  Widget _buildWebServerSettings() {
    return Card(
      color: Colors.white.withOpacity(0.1),
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 16.0, top: 16.0, right: 16.0, bottom: 8.0),
            child: Text(
              "远程访问（试验性）",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
          ),
          SwitchListTile(
            title: const Text(
              "启用Web服务器",
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              "允许通过浏览器访问应用（功能开发中）",
              style: TextStyle(color: Colors.white70),
            ),
            value: _webServerEnabled,
            onChanged: _toggleWebServer,
            activeColor: Colors.white,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color.fromARGB(255, 0, 0, 0),
          ),
          if (_webServerEnabled) ...[
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              title: const Text(
                "访问地址",
                style: TextStyle(color: Colors.white),
              ),
              subtitle: _accessUrls.isEmpty
                  ? const Text("正在获取地址...", style: TextStyle(color: Colors.white70))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _accessUrls
                          .map((url) => Text(url,
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  color: Colors.white70)))
                          .toList(),
                    ),
              trailing: IconButton(
                icon: const Icon(Icons.copy, color: Colors.white),
                onPressed: _copyUrls,
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              title: const Text(
                "端口设置",
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                "当前端口: $_currentPort",
                style: const TextStyle(color: Colors.white70),
              ),
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
} 