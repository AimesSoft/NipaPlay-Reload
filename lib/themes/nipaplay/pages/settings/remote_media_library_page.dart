// remote_media_library_page.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/models/dandanplay_remote_model.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/dandanplay_remote_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_server_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_login_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_card.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/shared_remote_library_settings_section.dart';

class RemoteMediaLibraryPage extends StatefulWidget {
  const RemoteMediaLibraryPage({super.key});

  @override
  State<RemoteMediaLibraryPage> createState() => _RemoteMediaLibraryPageState();
}

class _RemoteMediaLibraryPageState extends State<RemoteMediaLibraryPage> {
  @override
  Widget build(BuildContext context) {
    return Consumer3<JellyfinProvider, EmbyProvider, DandanplayRemoteProvider>(
      builder: (context, jellyfinProvider, embyProvider, dandanProvider, child) {
        // 检查 Provider 是否已初始化
        if (!jellyfinProvider.isInitialized &&
            !embyProvider.isInitialized &&
            !dandanProvider.isInitialized) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.blue),
                SizedBox(height: 16),
                Text(
                  '正在初始化远程媒体库服务...',
                  locale:Locale("zh-Hans","zh"),
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
        final hasDandanError = (dandanProvider.errorMessage?.isNotEmpty ?? false) &&
            !dandanProvider.isConnected &&
            dandanProvider.isInitialized;
        
        return ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            // 显示错误信息（如果有的话）
            if (hasJellyfinError || hasEmbyError || hasDandanError) ...[
              _buildErrorCard(
                jellyfinProvider,
                embyProvider,
                dandanProvider,
                hasDandanError,
              ),
              const SizedBox(height: 20),
            ],
            
            // Jellyfin服务器配置部分
            _buildJellyfinSection(jellyfinProvider),

            const SizedBox(height: 20),

            // Emby服务器配置部分
            _buildEmbySection(embyProvider),

            const SizedBox(height: 20),

            // 弹弹play 远程服务
            _buildDandanplaySection(dandanProvider),

            const SizedBox(height: 20),

            const SharedRemoteLibrarySettingsSection(),

            const SizedBox(height: 20),

            // 其他远程媒体库服务 (预留)
            _buildOtherServicesSection(),
          ],
        );
      },
    );
  }

  Widget _buildErrorCard(
    JellyfinProvider jellyfinProvider,
    EmbyProvider embyProvider,
    DandanplayRemoteProvider dandanProvider,
    bool hasDandanError,
  ) {
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
                locale:Locale("zh-Hans","zh"),
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
          if (hasDandanError) ...[
            if (jellyfinProvider.hasError || embyProvider.hasError)
              const SizedBox(height: 8),
            _buildErrorItem('弹弹play', dandanProvider.errorMessage ?? '未知错误'),
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
                    locale:Locale("zh-Hans","zh"),
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
            locale:Locale("zh-Hans","zh"),
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
                locale:Locale("zh-Hans","zh"),
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
                    locale:Locale("zh-Hans","zh"),
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
                  locale:Locale("zh-Hans","zh"),
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
              const Text('服务器:', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70, fontSize: 14)),
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
              const Text('用户:', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70, fontSize: 14)),
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
              const Text('媒体库:', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70, fontSize: 14)),
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
                locale:Locale("zh-Hans","zh"),
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
                        locale:Locale("zh-Hans","zh"),
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
                  locale:Locale("zh-Hans","zh"),
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
              const Text('服务器:', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70, fontSize: 14)),
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
              const Text('用户:', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70, fontSize: 14)),
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
              const Text('媒体库:', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70, fontSize: 14)),
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

  Widget _buildDandanplaySection(DandanplayRemoteProvider provider) {
    final bool isConnected = provider.isConnected;
    final bool isLoading = provider.isLoading;
    final String? errorMessage = provider.errorMessage;

    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(
                'assets/dandanplay.png',
                width: 32,
                height: 32,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 12),
              const Text(
                '弹弹play 远程访问',
                locale:Locale("zh-Hans","zh"),
style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              if (isLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              else if (isConnected)
                _buildStatusChip('已同步', Colors.green)
              else if (provider.serverUrl != null)
                _buildStatusChip('连接失败', Colors.orange)
              else
                _buildStatusChip('未配置', Colors.white70),
            ],
          ),
          const SizedBox(height: 16),
          if ((errorMessage?.isNotEmpty ?? false) && !isLoading) ...[
            _buildDandanErrorBanner(errorMessage!),
            const SizedBox(height: 16),
          ],
          if (!isConnected) ...[
            const Text(
              '通过弹弹play桌面端开启远程访问后，可在此直接浏览和播放家中 NAS/电脑上的弹幕番剧。',
              locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: _buildGlassButton(
                onPressed: () => _showDandanplayConnectDialog(provider),
                icon: Icons.link,
                label: '连接弹弹play远程服务',
              ),
            ),
          ] else ...[
            _buildDandanServerInfo(provider),
            const SizedBox(height: 16),
            _buildDandanStats(provider),
            const SizedBox(height: 16),
            _buildDandanAnimePreview(provider),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildGlassButton(
                    onPressed: isLoading
                        ? null
                        : () => _showDandanplayConnectDialog(provider),
                    icon: Icons.settings,
                    label: '管理连接',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildGlassButton(
                    onPressed: isLoading
                        ? null
                        : () => _refreshDandanLibrary(provider),
                    icon: Icons.refresh,
                    label: isLoading ? '同步中...' : '刷新媒体库',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _buildGlassButton(
                onPressed:
                    isLoading ? null : () => _disconnectDandanplay(provider),
                icon: Icons.logout,
                label: '断开连接',
                isDestructive: true,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDandanErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.redAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.red[200], fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildDandanServerInfo(DandanplayRemoteProvider provider) {
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
          _buildInfoRow(
            icon: Icons.dns,
            iconColor: const Color(0xFFFFC857),
            label: '服务器地址',
            value: provider.serverUrl ?? '未配置',
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            icon: Icons.sync,
            iconColor: const Color(0xFFFFC857),
            label: '最近同步',
            value: _formatDandanTimestamp(provider.lastSyncedAt),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color iconColor = Colors.white70,
  }) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 16),
        const SizedBox(width: 8),
        Text(
          '$label:',
          locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildDandanStats(DandanplayRemoteProvider provider) {
    final stats = [
      {
        'label': '番剧条目',
        'value': '${provider.animeGroups.length}',
        'icon': Ionicons.tv_outline,
      },
      {
        'label': '视频文件',
        'value': '${provider.episodes.length}',
        'icon': Ionicons.videocam_outline,
      },
      {
        'label': '最近同步',
        'value': _formatDandanTimestamp(provider.lastSyncedAt),
        'icon': Ionicons.refresh_outline,
      },
    ];

    final children = <Widget>[];
    for (var i = 0; i < stats.length; i++) {
      final stat = stats[i];
      final isLast = i == stats.length - 1;
      children.add(
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : 12),
            child: _buildDandanStatTile(
              icon: stat['icon'] as IconData,
              label: stat['label'] as String,
              value: stat['value'] as String,
            ),
          ),
        ),
      );
    }

    return Row(children: children);
  }

  Widget _buildDandanStatTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.white.withOpacity(0.04),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDandanAnimePreview(DandanplayRemoteProvider provider) {
    final List<DandanplayRemoteAnimeGroup> preview =
        provider.animeGroups.take(3).toList();

    if (preview.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.white.withOpacity(0.04),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: const Text(
          '暂无远程媒体记录，可尝试刷新或确认远程访问设置。',
          locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '最近更新',
          locale:Locale("zh-Hans","zh"),
style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        ...preview.map(_buildDandanAnimeGroupTile),
      ],
    );
  }

  Widget _buildDandanAnimeGroupTile(DandanplayRemoteAnimeGroup group) {
    final DandanplayRemoteEpisode latest = group.latestEpisode;
    final String subtitle =
        '${latest.episodeTitle} · ${_formatDandanTimestamp(latest.lastPlay ?? latest.created)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.white.withOpacity(0.04),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          const Icon(Ionicons.play_outline, color: Colors.white70, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white54, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withOpacity(0.08),
            ),
            child: Text(
              '共 ${group.episodeCount} 集',
              locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDandanTimestamp(DateTime? timestamp) {
    if (timestamp == null) {
      return '暂无记录';
    }
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inMinutes < 1) {
      return '刚刚';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes} 分钟前';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours} 小时前';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays} 天前';
    }
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${timestamp.year}-${twoDigits(timestamp.month)}-${twoDigits(timestamp.day)} '
        '${twoDigits(timestamp.hour)}:${twoDigits(timestamp.minute)}';
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
                    locale:Locale("zh-Hans","zh"),
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
                locale:Locale("zh-Hans","zh"),
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
          child: const Text('取消', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('断开连接', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.red)),
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
    VoidCallback? onPressed,
    required IconData icon,
    required String label,
    bool isDestructive = false,
  }) {
    bool isHovered = false;
    return StatefulBuilder(
      builder: (context, setState) {
        final bool isDisabled = onPressed == null;
        final Color accentColor = isDestructive
            ? const Color(0xFFFF6B6B)
            : Colors.white;
        final double backgroundOpacity = isDisabled
            ? 0.06
            : (isHovered ? 0.22 : 0.12);
        final double borderOpacity = isDisabled
            ? 0.15
            : (isHovered ? 0.4 : 0.2);

        void updateHover(bool value) {
          if (isDisabled) {
            return;
          }
          setState(() => isHovered = value);
        }

        final Color backgroundColor = isDestructive
            ? const Color(0xFFFF6B6B).withOpacity(backgroundOpacity)
            : Colors.white.withOpacity(backgroundOpacity);
        final Color borderColor = isDestructive
            ? const Color(0xFFFF6B6B).withOpacity(borderOpacity)
            : Colors.white.withOpacity(borderOpacity);
        final Color iconColor = isDisabled
            ? Colors.white38
            : accentColor;

        return MouseRegion(
          onEnter: (_) => updateHover(true),
          onExit: (_) => updateHover(false),
          cursor: isDisabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: borderColor,
                    width: 0.5,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: isDisabled ? null : onPressed,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            color: iconColor,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            label,
                            style: TextStyle(
                              color: isDisabled
                                  ? Colors.white54
                                  : Colors.white,
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
          child: const Text('取消', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('断开连接', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.red)),
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

  Future<void> _showDandanplayConnectDialog(
      DandanplayRemoteProvider provider) async {
    final hasExisting = provider.serverUrl?.isNotEmpty == true;
    final result = await BlurLoginDialog.show(
      context,
      title: hasExisting ? '更新弹弹play远程连接' : '连接弹弹play远程服务',
      loginButtonText: hasExisting ? '保存' : '连接',
      fields: [
        LoginField(
          key: 'baseUrl',
          label: '远程服务地址',
          hint: '例如 http://192.168.1.2:23333',
          initialValue: provider.serverUrl ?? '',
        ),
        LoginField(
          key: 'token',
          label: 'API密钥 (可选)',
          hint: provider.tokenRequired
              ? '服务器已启用 API 验证'
              : '若服务器开启验证请填写',
          isPassword: true,
          required: false,
        ),
      ],
      onLogin: (values) async {
        final baseUrl = values['baseUrl'] ?? '';
        final token = values['token'];
        if (baseUrl.isEmpty) {
          return const LoginResult(success: false, message: '请输入远程服务地址');
        }
        try {
          await provider.connect(baseUrl, token: token);
          return const LoginResult(
            success: true,
            message: '已连接至弹弹play远程服务',
          );
        } catch (e) {
          return LoginResult(success: false, message: e.toString());
        }
      },
    );

    if (result == true && mounted) {
      BlurSnackBar.show(context, '弹弹play远程服务配置已更新');
    }
  }

  Future<void> _refreshDandanLibrary(
      DandanplayRemoteProvider provider) async {
    try {
      await provider.refresh();
      if (mounted) {
        BlurSnackBar.show(context, '远程媒体库已刷新');
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '刷新失败: $e');
      }
    }
  }

  Future<void> _disconnectDandanplay(
      DandanplayRemoteProvider provider) async {
    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: '断开弹弹play远程服务',
      content: '确定要断开与弹弹play远程服务的连接吗？\n\n这将清除已保存的地址与 API 密钥。',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('断开连接', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.red)),
        ),
      ],
    );

    if (confirm == true) {
      try {
        await provider.disconnect();
        if (mounted) {
          BlurSnackBar.show(context, '已断开与弹弹play远程服务的连接');
        }
      } catch (e) {
        if (mounted) {
          BlurSnackBar.show(context, '断开连接时出错: $e');
        }
      }
    }
  }
}
