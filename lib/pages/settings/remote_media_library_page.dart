// remote_media_library_page.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/widgets/nipaplay_theme/network_media_server_dialog.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dialog.dart';
import 'package:nipaplay/widgets/nipaplay_theme/settings_card.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';

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
        // 检查 Provider 是否已初始化
        if (!jellyfinProvider.isInitialized && !embyProvider.isInitialized) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.blue),
                SizedBox(height: 16),
                Text(
                  '正在初始化远程媒体库服务...',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          );
        }
        
        // 检查是否有严重错误
        final hasJellyfinError = jellyfinProvider.hasError && 
                                 jellyfinProvider.errorMessage != null &&
                                 !jellyfinProvider.isConnected;
        final hasEmbyError = embyProvider.hasError && 
                            embyProvider.errorMessage != null &&
                            !embyProvider.isConnected;
        
        return ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            // 显示错误信息（如果有的话）
            if (hasJellyfinError || hasEmbyError) ...[
              _buildErrorCard(jellyfinProvider, embyProvider),
              const SizedBox(height: 20),
            ],
            
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

  Widget _buildErrorCard(JellyfinProvider jellyfinProvider, EmbyProvider embyProvider) {
    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline,
                color: Colors.red[400],
                size: 24,
              ),
              const SizedBox(width: 12),
              const Text(
                '服务初始化错误',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (jellyfinProvider.hasError && jellyfinProvider.errorMessage != null)
            _buildErrorItem('Jellyfin', jellyfinProvider.errorMessage!),
          if (embyProvider.hasError && embyProvider.errorMessage != null) ...[
            if (jellyfinProvider.hasError) const SizedBox(height: 8),
            _buildErrorItem('Emby', embyProvider.errorMessage!),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.yellow.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.yellow.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info, color: Colors.yellow, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '这些错误不会影响其他功能的正常使用。您可以尝试重新配置服务器连接。',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorItem(String serviceName, String errorMessage) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            serviceName,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            errorMessage,
            style: TextStyle(
              color: Colors.red[300],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJellyfinSection(JellyfinProvider jellyfinProvider) {
    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgPicture.asset(
                'assets/jellyfin.svg',
                colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                width: 24,
                height: 24,
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
                // 安全地查找媒体库，避免数组越界异常
                final library = availableLibraries.where((lib) => lib.id == libraryId).isNotEmpty
                    ? availableLibraries.firstWhere((lib) => lib.id == libraryId)
                    : null;
                
                if (library == null) {
                  // 如果找不到对应的库，显示ID
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '未知媒体库 ($libraryId)',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                      ),
                    ),
                  );
                }
                
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
    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgPicture.asset(
                'assets/emby.svg',
                colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                width: 24,
                height: 24,
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
                // 安全地查找媒体库，避免数组越界异常
                final library = availableLibraries.where((lib) => lib.id == libraryId).isNotEmpty
                    ? availableLibraries.firstWhere((lib) => lib.id == libraryId)
                    : null;
                
                if (library == null) {
                  // 如果找不到对应的库，显示ID
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '未知媒体库 ($libraryId)',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                      ),
                    ),
                  );
                }
                
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
          sigmaX: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0,
          sigmaY: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0,
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
              const Row(
                children: [
                  Icon(
                    Ionicons.cloud_outline,
                    color: Colors.white,
                    size: 24,
                  ),
                  SizedBox(width: 12),
                  Text(
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
    final result = await NetworkMediaServerDialog.show(context, MediaServerType.jellyfin);
    
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
    final result = await NetworkMediaServerDialog.show(context, MediaServerType.emby);
    
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

