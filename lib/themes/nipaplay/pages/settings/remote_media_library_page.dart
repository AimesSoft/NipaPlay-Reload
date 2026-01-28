// remote_media_library_page.dart
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/models/dandanplay_remote_model.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/dandanplay_remote_provider.dart';
import 'package:nipaplay/services/media_server_device_id_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_server_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_login_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:nipaplay/themes/nipaplay/widgets/shared_remote_library_settings_section.dart';

class RemoteMediaLibraryPage extends StatefulWidget {
  const RemoteMediaLibraryPage({super.key});

  @override
  State<RemoteMediaLibraryPage> createState() => _RemoteMediaLibraryPageState();
}

class _RemoteMediaLibraryPageState extends State<RemoteMediaLibraryPage> {
  Future<_MediaServerDeviceIdInfo>? _deviceIdInfoFuture;

  @override
  void initState() {
    super.initState();
    _deviceIdInfoFuture = _loadDeviceIdInfo();
  }

  static String _clientPlatformLabel() {
    if (kIsWeb || kDebugMode) {
      return 'Flutter';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'Ios';
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.macOS:
        return 'Macos';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.fuchsia:
        return 'Fuchsia';
    }
  }

  Future<_MediaServerDeviceIdInfo> _loadDeviceIdInfo() async {
    String appName = 'NipaPlay';
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (packageInfo.appName.isNotEmpty) {
        appName = packageInfo.appName;
      }
    } catch (_) {}

    final platform = _clientPlatformLabel();
    final customDeviceId =
        await MediaServerDeviceIdService.instance.getCustomDeviceId();
    final generatedDeviceId =
        await MediaServerDeviceIdService.instance.getOrCreateGeneratedDeviceId();
    final effectiveDeviceId =
        await MediaServerDeviceIdService.instance.getEffectiveDeviceId(
      appName: appName,
      platform: platform,
    );

    return _MediaServerDeviceIdInfo(
      appName: appName,
      platform: platform,
      effectiveDeviceId: effectiveDeviceId,
      generatedDeviceId: generatedDeviceId,
      customDeviceId: customDeviceId,
    );
  }

  void _refreshDeviceIdInfo() {
    setState(() {
      _deviceIdInfoFuture = _loadDeviceIdInfo();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<JellyfinProvider, EmbyProvider, DandanplayRemoteProvider>(
      builder: (context, jellyfinProvider, embyProvider, dandanProvider, child) {
        final colorScheme = Theme.of(context).colorScheme;
        // 检查 Provider 是否已初始化
        if (!jellyfinProvider.isInitialized &&
            !embyProvider.isInitialized &&
            !dandanProvider.isInitialized) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  '正在初始化远程媒体库服务...',
                  locale: const Locale("zh-Hans","zh"),
                  style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
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

            const SizedBox(height: 20),

            // 设备标识（Jellyfin/Emby）
            _buildDeviceIdSection(),
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
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.error_outline,
              color: colorScheme.error,
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(
              '服务初始化错误',
              locale: const Locale("zh-Hans","zh"),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info, color: colorScheme.tertiary, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '这些错误不会影响其他功能的正常使用。您可以尝试重新配置服务器连接。',
                locale: const Locale("zh-Hans","zh"),
                style: TextStyle(
                  color: colorScheme.onSurface.withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildErrorItem(String serviceName, String errorMessage) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          serviceName,
          style: TextStyle(
            color: colorScheme.error,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          errorMessage,
          locale: const Locale("zh-Hans","zh"),
          style: TextStyle(
            color: colorScheme.error.withOpacity(0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildJellyfinSection(JellyfinProvider jellyfinProvider) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SvgPicture.asset(
              'assets/jellyfin.svg',
              colorFilter: ColorFilter.mode(
                colorScheme.onSurface,
                BlendMode.srcIn,
              ),
              width: 24,
              height: 24,
            ),
            const SizedBox(width: 12),
            Text(
              'Jellyfin 媒体服务器',
              locale: const Locale("zh-Hans","zh"),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            if (jellyfinProvider.isConnected)
              const Text(
                '已连接',
                locale: Locale("zh-Hans","zh"),
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
            
        const SizedBox(height: 16),
            
        if (!jellyfinProvider.isConnected) ...[
          Text(
            'Jellyfin是一个免费的媒体服务器软件，可以让您在任何设备上流式传输您的媒体收藏。',
            locale: const Locale("zh-Hans","zh"),
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.7),
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
    );
  }

  Widget _buildServerInfo(JellyfinProvider jellyfinProvider) {
    final colorScheme = Theme.of(context).colorScheme;
    final labelStyle = TextStyle(
      color: colorScheme.onSurface.withOpacity(0.7),
      fontSize: 14,
    );
    final valueStyle = TextStyle(
      color: colorScheme.onSurface,
      fontSize: 14,
    );
    return Column(
      children: [
        Row(
          children: [
            Icon(Icons.dns, color: colorScheme.primary, size: 16),
            const SizedBox(width: 8),
            Text('服务器:', locale: const Locale("zh-Hans","zh"), style: labelStyle),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                jellyfinProvider.serverUrl ?? '未知',
                style: valueStyle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.person, color: colorScheme.primary, size: 16),
            const SizedBox(width: 8),
            Text('用户:', locale: const Locale("zh-Hans","zh"), style: labelStyle),
            const SizedBox(width: 8),
            Text(
              jellyfinProvider.username ?? '匿名',
              style: valueStyle,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLibraryInfo(JellyfinProvider jellyfinProvider) {
    final selectedLibraries = jellyfinProvider.selectedLibraryIds;
    final availableLibraries = jellyfinProvider.availableLibraries;
    final colorScheme = Theme.of(context).colorScheme;
    final labelStyle = TextStyle(
      color: colorScheme.onSurface.withOpacity(0.7),
      fontSize: 14,
    );
    final valueStyle = TextStyle(
      color: colorScheme.onSurface,
      fontSize: 14,
    );
    final errorColor = colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Ionicons.library_outline, color: colorScheme.primary, size: 16),
            const SizedBox(width: 8),
            Text('媒体库:', locale: const Locale("zh-Hans","zh"), style: labelStyle),
            const SizedBox(width: 8),
            Text(
              '已选择 ${selectedLibraries.length} / ${availableLibraries.length}',
              style: valueStyle,
            ),
          ],
        ),
        if (selectedLibraries.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: selectedLibraries.map((libraryId) {
              final library = availableLibraries.where((lib) => lib.id == libraryId).isNotEmpty
                  ? availableLibraries.firstWhere((lib) => lib.id == libraryId)
                  : null;
              if (library == null) {
                return Text(
                  '未知媒体库 ($libraryId)',
                  style: TextStyle(
                    color: errorColor,
                    fontSize: 12,
                  ),
                );
              }
              return Text(
                library.name,
                style: TextStyle(
                  color: colorScheme.primary,
                  fontSize: 12,
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildEmbySection(EmbyProvider embyProvider) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SvgPicture.asset(
              'assets/emby.svg',
              colorFilter: ColorFilter.mode(
                colorScheme.onSurface,
                BlendMode.srcIn,
              ),
              width: 24,
              height: 24,
            ),
            const SizedBox(width: 12),
            Text(
              'Emby 媒体服务器',
              locale: const Locale("zh-Hans","zh"),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            if (embyProvider.isConnected)
              const Text(
                '已连接',
                locale: Locale("zh-Hans","zh"),
                style: TextStyle(
                  color: Color(0xFF52B54B),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        if (!embyProvider.isConnected) ...[
          Text(
            'Emby是一个强大的个人媒体服务器，可以让您在任何设备上组织、播放和流式传输您的媒体收藏。',
            locale: const Locale("zh-Hans","zh"),
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.7),
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
    );
  }

  Widget _buildDeviceIdSection() {
    final colorScheme = Theme.of(context).colorScheme;
    return FutureBuilder<_MediaServerDeviceIdInfo>(
      future: _deviceIdInfoFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '正在加载设备标识...',
                locale: const Locale("zh-Hans", "zh"),
                style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
              ),
            ],
          );
        }

        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '设备标识',
                locale: const Locale("zh-Hans", "zh"),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '加载失败: ${snapshot.error}',
                locale: const Locale("zh-Hans", "zh"),
                style: TextStyle(color: colorScheme.error, fontSize: 13),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _buildGlassButton(
                  onPressed: _refreshDeviceIdInfo,
                  icon: Icons.refresh,
                  label: '重试',
                ),
              ),
            ],
          );
        }

        final info = snapshot.data;
        if (info == null) {
          return Text(
            '设备标识加载失败',
            locale: const Locale("zh-Hans", "zh"),
            style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
          );
        }

        final hasCustom = info.customDeviceId != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fingerprint, color: colorScheme.onSurface),
                const SizedBox(width: 12),
                Text(
                  '设备标识（Jellyfin/Emby）',
                  locale: const Locale("zh-Hans", "zh"),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                if (hasCustom)
                  Text(
                    '已自定义',
                    locale: const Locale("zh-Hans", "zh"),
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '用于区分不同设备，避免多台 iOS 设备被识别为同一设备导致互踢登出。',
              locale: const Locale("zh-Hans", "zh"),
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            _buildDeviceIdValueRow('当前 DeviceId', info.effectiveDeviceId),
            const SizedBox(height: 8),
            if (!hasCustom)
              _buildDeviceIdValueRow('自动生成标识', info.generatedDeviceId),
            if (hasCustom) ...[
              const SizedBox(height: 8),
              _buildDeviceIdValueRow('自定义 DeviceId', info.customDeviceId!),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info, color: colorScheme.tertiary, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '修改 DeviceId 后，建议断开并重新连接 Jellyfin/Emby 以确保生效。',
                    locale: const Locale("zh-Hans", "zh"),
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildGlassButton(
                    onPressed: () => _showCustomDeviceIdDialog(info),
                    icon: Icons.edit,
                    label: hasCustom ? '修改 DeviceId' : '自定义 DeviceId',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildGlassButton(
                    onPressed: hasCustom
                        ? () async {
                            try {
                              await MediaServerDeviceIdService.instance
                                  .setCustomDeviceId(null);
                              if (!context.mounted) return;
                              _refreshDeviceIdInfo();
                              BlurSnackBar.show(context, '已恢复自动生成的设备ID');
                            } catch (e) {
                              if (!context.mounted) return;
                              BlurSnackBar.show(context, '操作失败: $e');
                            }
                          }
                        : null,
                    icon: Icons.refresh,
                    label: '恢复自动生成',
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildDeviceIdValueRow(String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          locale: const Locale("zh-Hans", "zh"),
          style: TextStyle(
            color: colorScheme.onSurface.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        SelectableText(
          value,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 13,
            height: 1.2,
          ),
        ),
      ],
    );
  }

  Future<void> _showCustomDeviceIdDialog(_MediaServerDeviceIdInfo info) async {
    final controller = TextEditingController(text: info.customDeviceId ?? '');
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accentColor = Color(0xFFFF2E55);
    final textColor = colorScheme.onSurface;
    final secondaryTextColor = textColor.withOpacity(0.7);
    final hintColor = textColor.withOpacity(0.5);
    final borderColor = textColor.withOpacity(isDark ? 0.25 : 0.2);
    final fillColor = isDark ? const Color(0xFF262626) : const Color(0xFFE8E8E8);
    final selectionTheme = TextSelectionThemeData(
      cursorColor: accentColor,
      selectionColor: accentColor.withOpacity(0.3),
      selectionHandleColor: accentColor,
    );

    await BlurDialog.show<void>(
      context: context,
      title: '自定义 DeviceId',
      contentWidget: TextSelectionTheme(
        data: selectionTheme,
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '留空表示使用自动生成的设备标识。\n\n建议只使用字母/数字/下划线/短横线，长度不超过128，且不要包含双引号或换行。',
                locale: const Locale("zh-Hans", "zh"),
                style: TextStyle(
                  color: secondaryTextColor,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLength: 128,
                cursorColor: accentColor,
                style: const TextStyle(color: accentColor),
                decoration: InputDecoration(
                  hintText: '例如: My-iPhone-01',
                  hintStyle: TextStyle(color: hintColor),
                  counterStyle: TextStyle(color: hintColor),
                  filled: true,
                  fillColor: fillColor,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: borderColor, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: accentColor, width: 1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(),
          text: '取消',
          idleColor: secondaryTextColor,
        ),
        HoverScaleTextButton(
          onPressed: () async {
            try {
              await MediaServerDeviceIdService.instance
                  .setCustomDeviceId(controller.text);
              if (!mounted) return;
              Navigator.of(context).pop();
              _refreshDeviceIdInfo();
              BlurSnackBar.show(context, '设备ID已更新，重新连接后生效');
            } on FormatException {
              if (mounted) {
                BlurSnackBar.show(
                    context, 'DeviceId 无效：请避免双引号/换行，且长度 ≤ 128');
              }
            } catch (e) {
              if (mounted) {
                BlurSnackBar.show(context, '保存失败: $e');
              }
            }
          },
          text: '保存',
          idleColor: textColor,
        ),
      ],
    );
  }

  Widget _buildEmbyServerInfo(EmbyProvider embyProvider) {
    final colorScheme = Theme.of(context).colorScheme;
    final labelStyle = TextStyle(
      color: colorScheme.onSurface.withOpacity(0.7),
      fontSize: 14,
    );
    final valueStyle = TextStyle(
      color: colorScheme.onSurface,
      fontSize: 14,
    );
    return Column(
      children: [
        Row(
          children: [
            const Icon(Icons.dns, color: Color(0xFF52B54B), size: 16),
            const SizedBox(width: 8),
            Text('服务器:', locale: const Locale("zh-Hans","zh"), style: labelStyle),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                embyProvider.serverUrl ?? '未知',
                style: valueStyle,
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
            Text('用户:', locale: const Locale("zh-Hans","zh"), style: labelStyle),
            const SizedBox(width: 8),
            Text(
              embyProvider.username ?? '匿名',
              style: valueStyle,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmbyLibraryInfo(EmbyProvider embyProvider) {
    final selectedLibraries = embyProvider.selectedLibraryIds;
    final availableLibraries = embyProvider.availableLibraries;
    final colorScheme = Theme.of(context).colorScheme;
    final labelStyle = TextStyle(
      color: colorScheme.onSurface.withOpacity(0.7),
      fontSize: 14,
    );
    final valueStyle = TextStyle(
      color: colorScheme.onSurface,
      fontSize: 14,
    );
    final errorColor = colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Ionicons.library_outline, color: Color(0xFF52B54B), size: 16),
            const SizedBox(width: 8),
            Text('媒体库:', locale: const Locale("zh-Hans","zh"), style: labelStyle),
            const SizedBox(width: 8),
            Text(
              '已选择 ${selectedLibraries.length} / ${availableLibraries.length}',
              style: valueStyle,
            ),
          ],
        ),
        if (selectedLibraries.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: selectedLibraries.map((libraryId) {
              final library = availableLibraries.where((lib) => lib.id == libraryId).isNotEmpty
                  ? availableLibraries.firstWhere((lib) => lib.id == libraryId)
                  : null;
              if (library == null) {
                return Text(
                  '未知媒体库 ($libraryId)',
                  style: TextStyle(
                    color: errorColor,
                    fontSize: 12,
                  ),
                );
              }
              return Text(
                library.name,
                style: const TextStyle(
                  color: Color(0xFF52B54B),
                  fontSize: 12,
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildDandanplaySection(DandanplayRemoteProvider provider) {
    final bool isConnected = provider.isConnected;
    final bool isLoading = provider.isLoading;
    final String? errorMessage = provider.errorMessage;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
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
            Text(
              '弹弹play 远程访问',
              locale: const Locale("zh-Hans","zh"),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            if (isLoading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                ),
              )
            else if (isConnected)
              _buildStatusChip('已同步', Colors.green)
            else if (provider.serverUrl != null)
              _buildStatusChip('连接失败', Colors.orange)
            else
              _buildStatusChip(
                '未配置',
                colorScheme.onSurface.withOpacity(0.6),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if ((errorMessage?.isNotEmpty ?? false) && !isLoading) ...[
          _buildDandanErrorBanner(errorMessage!),
          const SizedBox(height: 16),
        ],
        if (!isConnected) ...[
          Text(
            '通过弹弹play桌面端开启远程访问后，可在此直接浏览和播放家中 NAS/电脑上的弹幕番剧。',
            locale: const Locale("zh-Hans","zh"),
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.7),
              fontSize: 14,
            ),
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
    );
  }

  Widget _buildDandanErrorBanner(String message) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.warning_amber_rounded,
          color: colorScheme.error,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            locale: const Locale("zh-Hans","zh"),
            style: TextStyle(
              color: colorScheme.error,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildDandanServerInfo(DandanplayRemoteProvider provider) {
    return Column(
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
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? iconColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolvedIconColor =
        iconColor ?? colorScheme.onSurface.withOpacity(0.7);
    return Row(
      children: [
        Icon(icon, color: resolvedIconColor, size: 16),
        const SizedBox(width: 8),
        Text(
          '$label:',
          locale:Locale("zh-Hans","zh"),
style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7), fontSize: 14),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
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
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: colorScheme.onSurface.withOpacity(0.7), size: 18),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          locale: const Locale("zh-Hans","zh"),
          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildDandanAnimePreview(DandanplayRemoteProvider provider) {
    final List<DandanplayRemoteAnimeGroup> preview =
        provider.animeGroups.take(3).toList();

    if (preview.isEmpty) {
      final colorScheme = Theme.of(context).colorScheme;
      return Text(
        '暂无远程媒体记录，可尝试刷新或确认远程访问设置。',
        locale: const Locale("zh-Hans","zh"),
        style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 13),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '最近更新',
          locale: const Locale("zh-Hans","zh"),
          style: TextStyle(
            color: colorScheme.onSurface.withOpacity(0.7),
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

    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Ionicons.play_outline,
              color: colorScheme.onSurface.withOpacity(0.7), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.title,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  locale: const Locale("zh-Hans","zh"),
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.6),
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '共 ${group.episodeCount} 集',
            locale: const Locale("zh-Hans","zh"),
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.7),
              fontSize: 12,
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
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Ionicons.cloud_outline,
              color: colorScheme.onSurface,
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(
              '其他媒体服务',
              locale: const Locale("zh-Hans","zh"),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        Text(
          '更多远程媒体服务支持正在开发中...',
          locale: const Locale("zh-Hans","zh"),
          style: TextStyle(
            color: colorScheme.onSurface.withOpacity(0.7),
            fontSize: 14,
          ),
        ),
        
        const SizedBox(height: 16),
        
        // 预留的服务列表
        ..._buildFutureServices(context),
      ],
    );
  }

  List<Widget> _buildFutureServices(BuildContext context) {
    final services = [
      {'name': 'DLNA/UPnP', 'icon': Ionicons.wifi_outline, 'status': '计划中'},
    ];
    final colorScheme = Theme.of(context).colorScheme;

    return services.map((service) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              service['icon'] as IconData,
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                service['name'] as String,
                style: TextStyle(color: colorScheme.onSurface.withOpacity(0.8)),
              ),
            ),
            Text(
              service['status'] as String,
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.6),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }).toList();
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
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70)),
        ),
        HoverScaleTextButton(
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
        final colorScheme = Theme.of(context).colorScheme;
        final Color baseTextColor = colorScheme.onSurface;
        final Color destructiveColor = colorScheme.error;
        final Color accentColor = isDestructive ? destructiveColor : baseTextColor;
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
            ? destructiveColor.withOpacity(backgroundOpacity)
            : colorScheme.surface.withOpacity(backgroundOpacity);
        final Color borderColor = isDestructive
            ? destructiveColor.withOpacity(borderOpacity)
            : baseTextColor.withOpacity(borderOpacity);
        final Color iconColor = isDisabled
            ? baseTextColor.withOpacity(0.38)
            : accentColor;
        final Color labelColor = isDisabled
            ? baseTextColor.withOpacity(0.5)
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
                              color: labelColor,
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
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70)),
        ),
        HoverScaleTextButton(
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
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70)),
        ),
        HoverScaleTextButton(
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

class _MediaServerDeviceIdInfo {
  const _MediaServerDeviceIdInfo({
    required this.appName,
    required this.platform,
    required this.effectiveDeviceId,
    required this.generatedDeviceId,
    required this.customDeviceId,
  });

  final String appName;
  final String platform;
  final String effectiveDeviceId;
  final String generatedDeviceId;
  final String? customDeviceId;
}
