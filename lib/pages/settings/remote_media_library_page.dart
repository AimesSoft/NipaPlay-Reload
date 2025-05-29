// remote_media_library_page.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/widgets/jellyfin_server_dialog.dart';
import 'package:nipaplay/widgets/emby_server_dialog.dart';
import 'package:nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/widgets/blur_dialog.dart';

class RemoteMediaLibraryPage extends StatefulWidget {
  const RemoteMediaLibraryPage({super.key});

  @override
  State<RemoteMediaLibraryPage> createState() => _RemoteMediaLibraryPageState();
}

class _RemoteMediaLibraryPageState extends State<RemoteMediaLibraryPage> {
  @override
  Widget build(BuildContext context) {
    return Consumer2<JellyfinProvider, EmbyProvider>(
      builder: (context, jellyfinProvider, embyProvider, child) {
        return ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            // Jellyfin服务器配置部分
            _buildJellyfinSection(jellyfinProvider),
            
            const SizedBox(height: 20),
            
            // Emby服务器配置部分
            _buildEmbySection(embyProvider),
            
            const SizedBox(height: 20),
            
            // 其他远程媒体库服务 (预留)
            _buildOtherServicesSection(),
          ],
        );
      },
    );
  }

  Widget _buildJellyfinSection(JellyfinProvider jellyfinProvider) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 25,
          sigmaY: 25,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white.withOpacity(0.3),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 0.5,
            ),
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Ionicons.server_outline,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Jellyfin 媒体服务器',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  if (jellyfinProvider.isConnected)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green, width: 1),
                      ),
                      child: const Text(
                        '已连接',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              if (!jellyfinProvider.isConnected) ...[
                const Text(
                  'Jellyfin是一个免费的媒体服务器软件，可以让您在任何设备上流式传输您的媒体收藏。',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: _buildGlassButton(
                    onPressed: () => _showJellyfinServerDialog(),
                    icon: Icons.add,
                    label: '连接Jellyfin服务器',
                  ),
                ),
              ] else ...[
                // 已连接状态显示服务器信息
                _buildServerInfo(jellyfinProvider),
                
                const SizedBox(height: 16),
                
                // 媒体库信息
                _buildLibraryInfo(jellyfinProvider),
                
                const SizedBox(height: 16),
                
                // 操作按钮
                Row(
                  children: [
                    Expanded(
                      child: _buildGlassButton(
                        onPressed: () => _showJellyfinServerDialog(),
                        icon: Icons.settings,
                        label: '管理服务器',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildGlassButton(
                        onPressed: () => _disconnectServer(jellyfinProvider),
                        icon: Icons.logout,
                        label: '断开连接',
                        isDestructive: true,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServerInfo(JellyfinProvider jellyfinProvider) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.dns, color: Colors.blue, size: 16),
              const SizedBox(width: 8),
              const Text('服务器:', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  jellyfinProvider.serverUrl ?? '未知',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.person, color: Colors.blue, size: 16),
              const SizedBox(width: 8),
              const Text('用户:', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(width: 8),
              Text(
                jellyfinProvider.username ?? '匿名',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryInfo(JellyfinProvider jellyfinProvider) {
    final selectedLibraries = jellyfinProvider.selectedLibraryIds;
    final availableLibraries = jellyfinProvider.availableLibraries;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Ionicons.library_outline, color: Colors.blue, size: 16),
              const SizedBox(width: 8),
              const Text('媒体库:', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(width: 8),
              Text(
                '已选择 ${selectedLibraries.length} / ${availableLibraries.length}',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
          if (selectedLibraries.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: selectedLibraries.map((libraryId) {
                final library = availableLibraries.firstWhere(
                  (lib) => lib.id == libraryId,
                  orElse: () => availableLibraries.first,
                );
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    library.name,
                    style: const TextStyle(
                      color: Colors.blue,
                      fontSize: 12,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmbySection(EmbyProvider embyProvider) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 25,
          sigmaY: 25,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white.withOpacity(0.3),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 0.5,
            ),
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Ionicons.server_outline,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Emby 媒体服务器',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  if (embyProvider.isConnected)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF52B54B).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF52B54B), width: 1),
                      ),
                      child: const Text(
                        '已连接',
                        style: TextStyle(
                          color: Color(0xFF52B54B),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              if (!embyProvider.isConnected) ...[
                const Text(
                  'Emby是一个强大的个人媒体服务器，可以让您在任何设备上组织、播放和流式传输您的媒体收藏。',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: _buildGlassButton(
                    onPressed: () => _showEmbyServerDialog(),
                    icon: Icons.add,
                    label: '连接Emby服务器',
                  ),
                ),
              ] else ...[
                // 已连接状态显示服务器信息
                _buildEmbyServerInfo(embyProvider),
                
                const SizedBox(height: 16),
                
                // 媒体库信息
                _buildEmbyLibraryInfo(embyProvider),
                
                const SizedBox(height: 16),
                
                // 操作按钮
                Row(
                  children: [
                    Expanded(
                      child: _buildGlassButton(
                        onPressed: () => _showEmbyServerDialog(),
                        icon: Icons.settings,
                        label: '管理服务器',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildGlassButton(
                        onPressed: () => _disconnectEmbyServer(embyProvider),
                        icon: Icons.logout,
                        label: '断开连接',
                        isDestructive: true,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmbyServerInfo(EmbyProvider embyProvider) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.dns, color: Color(0xFF52B54B), size: 16),
              const SizedBox(width: 8),
              const Text('服务器:', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  embyProvider.serverUrl ?? '未知',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.person, color: Color(0xFF52B54B), size: 16),
              const SizedBox(width: 8),
              const Text('用户:', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(width: 8),
              Text(
                embyProvider.username ?? '匿名',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmbyLibraryInfo(EmbyProvider embyProvider) {
    final selectedLibraries = embyProvider.selectedLibraryIds;
    final availableLibraries = embyProvider.availableLibraries;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Ionicons.library_outline, color: Color(0xFF52B54B), size: 16),
              const SizedBox(width: 8),
              const Text('媒体库:', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(width: 8),
              Text(
                '已选择 ${selectedLibraries.length} / ${availableLibraries.length}',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
          if (selectedLibraries.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: selectedLibraries.map((libraryId) {
                final library = availableLibraries.firstWhere(
                  (lib) => lib.id == libraryId,
                  orElse: () => availableLibraries.first,
                );
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF52B54B).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    library.name,
                    style: const TextStyle(
                      color: Color(0xFF52B54B),
                      fontSize: 12,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOtherServicesSection() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 25,
          sigmaY: 25,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white.withOpacity(0.3),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 0.5,
            ),
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Ionicons.cloud_outline,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '其他媒体服务',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              const Text(
                '更多远程媒体服务支持正在开发中...',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 预留的服务列表
              ..._buildFutureServices(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFutureServices() {
    final services = [
      {'name': 'DLNA/UPnP', 'icon': Ionicons.wifi_outline, 'status': '计划中'},
      {'name': 'WebDAV', 'icon': Ionicons.cloud_outline, 'status': '计划中'},
    ];

    return services.map((service) => ListTile(
      leading: Icon(
        service['icon'] as IconData,
        color: Colors.white,
      ),
      title: Text(
        service['name'] as String,
        style: const TextStyle(color: Colors.white70),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          service['status'] as String,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 12,
          ),
        ),
      ),
      onTap: null, // 暂时禁用
    )).toList();
  }

  Future<void> _showJellyfinServerDialog() async {
    final result = await JellyfinServerDialog.show(context);
    
    if (result == true) {
      if (mounted) {
        BlurSnackBar.show(context, 'Jellyfin服务器设置已更新');
      }
    }
  }

  Future<void> _disconnectServer(JellyfinProvider jellyfinProvider) async {
    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: '断开连接',
      content: '确定要断开与Jellyfin服务器的连接吗？\n\n这将清除服务器信息和登录状态。',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消', style: TextStyle(color: Colors.white70)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('断开连接', style: TextStyle(color: Colors.red)),
        ),
      ],
    );

    if (confirm == true) {
      try {
        await jellyfinProvider.disconnectFromServer();
        if (mounted) {
          BlurSnackBar.show(context, '已断开与Jellyfin服务器的连接');
        }
      } catch (e) {
        if (mounted) {
          BlurSnackBar.show(context, '断开连接时出错: $e');
        }
      }
    }
  }

  Widget _buildGlassButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    bool isDestructive = false,
  }) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool isHovered = false;
        
        return MouseRegion(
          onEnter: (_) => setState(() => isHovered = true),
          onExit: (_) => setState(() => isHovered = false),
          cursor: SystemMouseCursors.click,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(isHovered ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withOpacity(isHovered ? 0.4 : 0.2),
                    width: 0.5,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onPressed,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEmbyServerDialog() async {
    final result = await EmbyServerDialog.show(context);
    
    if (result == true) {
      if (mounted) {
        BlurSnackBar.show(context, 'Emby服务器设置已更新');
      }
    }
  }

  Future<void> _disconnectEmbyServer(EmbyProvider embyProvider) async {
    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: '断开连接',
      content: '确定要断开与Emby服务器的连接吗？\n\n这将清除服务器信息和登录状态。',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消', style: TextStyle(color: Colors.white70)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('断开连接', style: TextStyle(color: Colors.red)),
        ),
      ],
    );

    if (confirm == true) {
      try {
        await embyProvider.disconnectFromServer();
        if (mounted) {
          BlurSnackBar.show(context, '已断开与Emby服务器的连接');
        }
      } catch (e) {
        if (mounted) {
          BlurSnackBar.show(context, '断开连接时出错: $e');
        }
      }
    }
  }
}

