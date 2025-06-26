import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nipaplay/services/windows_file_association_service.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/widgets/blur_snackbar.dart';

class FileAssociationSettings extends StatefulWidget {
  const FileAssociationSettings({super.key});

  @override
  State<FileAssociationSettings> createState() => _FileAssociationSettingsState();
}

class _FileAssociationSettingsState extends State<FileAssociationSettings> {
  bool _isRegistered = false;
  bool _isLoading = true;
  bool _hasAdminPrivileges = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    if (!Platform.isWindows) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final registered = await WindowsFileAssociationService.isRegistered();
      final hasAdmin = await WindowsFileAssociationService.hasAdminPrivileges();
      
      setState(() {
        _isRegistered = registered;
        _hasAdminPrivileges = hasAdmin;
        _isLoading = false;
      });
    } catch (e) {
      print('检查文件关联状态失败: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _installFileAssociation() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final success = await WindowsFileAssociationService.installFileAssociation();
      
      if (success) {
        if (mounted) {
          BlurSnackBar.show(context, '文件关联配置成功！');
        }
        await _checkStatus();
      } else {
        if (mounted) {
          BlurSnackBar.show(context, '文件关联配置失败，请检查权限或手动运行安装脚本');
        }
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '配置文件关联时出错: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _uninstallFileAssociation() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final success = await WindowsFileAssociationService.uninstallFileAssociation();
      
      if (success) {
        if (mounted) {
          BlurSnackBar.show(context, '文件关联已移除');
        }
        await _checkStatus();
      } else {
        if (mounted) {
          BlurSnackBar.show(context, '移除文件关联失败');
        }
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '移除文件关联时出错: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 仅在Windows平台显示
    if (!Platform.isWindows) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.link,
                  size: 24,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  '文件关联设置',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              // 状态显示
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isRegistered 
                    ? Colors.green.withOpacity(0.1)
                    : Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isRegistered 
                      ? Colors.green.withOpacity(0.3)
                      : Colors.orange.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isRegistered ? Icons.check_circle : Icons.info,
                      color: _isRegistered ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isRegistered 
                          ? 'NipaPlay已注册为视频文件的打开方式'
                          : 'NipaPlay尚未注册为视频文件的打开方式',
                        style: TextStyle(
                          color: _isRegistered ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 支持的格式
              Text(
                '支持的视频格式：',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: WindowsFileAssociationService.getSupportedExtensions()
                    .map((ext) => Chip(
                          label: Text(ext),
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        ))
                    .toList(),
              ),
              
              const SizedBox(height: 16),
              
              // 权限提示
              if (!_hasAdminPrivileges)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.blue.withOpacity(0.3),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.admin_panel_settings, color: Colors.blue),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '配置文件关联需要管理员权限，系统会提示您确认',
                          style: TextStyle(color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
              
              const SizedBox(height: 16),
              
              // 操作按钮
              Row(
                children: [
                  if (!_isRegistered) ...[
                    ElevatedButton.icon(
                      onPressed: _installFileAssociation,
                      icon: const Icon(Icons.add_link),
                      label: const Text('配置文件关联'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => WindowsFileAssociationService.openDefaultAppsSettings(),
                      icon: const Icon(Icons.settings),
                      label: const Text('打开系统设置'),
                    ),
                  ] else ...[
                    OutlinedButton.icon(
                      onPressed: _uninstallFileAssociation,
                      icon: const Icon(Icons.link_off),
                      label: const Text('移除文件关联'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => WindowsFileAssociationService.openDefaultAppsSettings(),
                      icon: const Icon(Icons.settings),
                      label: const Text('系统设置'),
                    ),
                  ],
                ],
              ),
              
              const SizedBox(height: 12),
              
              // 说明文字
              Text(
                _isRegistered 
                  ? '现在您可以双击视频文件来使用NipaPlay播放，或在右键菜单中选择NipaPlay。'
                  : '配置后，您可以右键点击视频文件，选择"打开方式"来使用NipaPlay播放。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
} 