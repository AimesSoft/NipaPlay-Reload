import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/widgets/blur_button.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'dart:io';

// 渲染修复策略
enum LinuxRenderFixMode {
  none, // 不使用任何修复
  invisibleMenu, // 使用不可见设置菜单
  forcedVulkan, // 强制使用Vulkan渲染
  forcedOpenGL, // 强制使用OpenGL渲染
  customColor, // 自定义背景色
}

class DeveloperOptionsPage extends StatefulWidget {
  const DeveloperOptionsPage({super.key});

  @override
  State<DeveloperOptionsPage> createState() => _DeveloperOptionsPageState();
}

class _DeveloperOptionsPageState extends State<DeveloperOptionsPage> {
  static const String _linuxRenderFixModeKey = 'linux_render_fix_mode';
  static const String _steamdeckDetectedKey = 'steamdeck_detected';
  
  LinuxRenderFixMode _selectedMode = LinuxRenderFixMode.none;
  bool _isSteamDeck = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _detectSteamDeck();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt(_linuxRenderFixModeKey) ?? 0;
    final isSteamDeck = prefs.getBool(_steamdeckDetectedKey) ?? false;
    
    setState(() {
      _selectedMode = LinuxRenderFixMode.values[modeIndex];
      _isSteamDeck = isSteamDeck;
      _isLoading = false;
    });
  }

  Future<void> _detectSteamDeck() async {
    if (Platform.isLinux) {
      try {
        final result = await Process.run('cat', ['/etc/os-release']);
        final isSteamOS = result.stdout.toString().toLowerCase().contains('steamos');
        
        if (isSteamOS) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(_steamdeckDetectedKey, true);
          
          setState(() {
            _isSteamDeck = true;
          });
        }
      } catch (e) {
        debugPrint('检测SteamDeck失败: $e');
      }
    }
  }

  Future<void> _saveRenderFixMode(LinuxRenderFixMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_linuxRenderFixModeKey, mode.index);
    
    setState(() {
      _selectedMode = mode;
    });
    
    // 需要重启应用才能生效
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要重启应用'),
        content: const Text('渲染修复模式已更改，需要重启应用才能生效。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('开发者选项'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 开发者警告
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning, color: Colors.orange),
                            const SizedBox(width: 8),
                            Text(
                              '开发者选项',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '这些选项仅供高级用户使用。更改这些设置可能会导致应用表现异常。请谨慎操作。',
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // SteamDeck检测结果
                  if (Platform.isLinux)
                    Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: _isSteamDeck 
                            ? Colors.blue.withOpacity(0.2) 
                            : Colors.grey.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _isSteamDeck ? Colors.blue : Colors.grey,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _isSteamDeck ? Icons.check_circle : Icons.info,
                                color: _isSteamDeck ? Colors.blue : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _isSteamDeck ? 'SteamDeck 已检测到' : 'Linux 系统',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: _isSteamDeck ? Colors.blue : Colors.grey,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isSteamDeck
                                ? '您当前在SteamDeck上运行NipaPlay。以下设置可以解决SteamDeck上的视频渲染问题。'
                                : '您当前在普通Linux系统上运行NipaPlay。如果遇到视频渲染问题，可以尝试以下设置。',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  
                  const SizedBox(height: 24),
                  
                  // Linux渲染修复选项（只在Linux上显示）
                  if (Platform.isLinux) ...[
                    Text(
                      'Linux/SteamDeck 渲染修复',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '这些选项用于解决Linux/SteamDeck上的视频渲染问题，特别是在窗口模式下视频显示异常的情况。',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    
                    // 渲染修复模式选择
                    _buildRenderFixModeOption(
                      context,
                      LinuxRenderFixMode.none,
                      '不使用修复',
                      '默认选项，不应用任何渲染修复。',
                    ),
                    
                    _buildRenderFixModeOption(
                      context,
                      LinuxRenderFixMode.invisibleMenu,
                      '不可见设置菜单（推荐）',
                      '在窗口播放模式下添加透明的设置菜单，修复颜色问题而不影响界面。',
                    ),
                    
                    _buildRenderFixModeOption(
                      context,
                      LinuxRenderFixMode.forcedVulkan,
                      '强制使用Vulkan渲染',
                      '强制视频播放器使用Vulkan渲染API，可能会解决某些显卡的兼容性问题。',
                    ),
                    
                    _buildRenderFixModeOption(
                      context,
                      LinuxRenderFixMode.forcedOpenGL,
                      '强制使用OpenGL渲染',
                      '强制视频播放器使用OpenGL渲染API，某些情况下更稳定。',
                    ),
                    
                    _buildRenderFixModeOption(
                      context,
                      LinuxRenderFixMode.customColor,
                      '自定义背景色',
                      '调整视频播放器的背景色，可能解决颜色失真问题。',
                    ),
                  ],
                  
                  const SizedBox(height: 24),
                  
                  // 其他开发者选项可以添加在这里
                ],
              ),
            ),
    );
  }

  Widget _buildRenderFixModeOption(
    BuildContext context,
    LinuxRenderFixMode mode,
    String title,
    String description,
  ) {
    final isSelected = _selectedMode == mode;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: InkWell(
        onTap: () => _saveRenderFixMode(mode),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: isSelected 
                ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                : Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected 
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.withOpacity(0.3),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Radio<LinuxRenderFixMode>(
                value: mode,
                groupValue: _selectedMode,
                onChanged: (value) {
                  if (value != null) {
                    _saveRenderFixMode(value);
                  }
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 