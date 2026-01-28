import 'package:flutter/material.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/server_profile_model.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_login_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/fluent_settings_switch.dart';
import 'package:nipaplay/themes/nipaplay/widgets/multi_address_manager_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/utils/url_name_generator.dart';
import 'package:nipaplay/models/jellyfin_transcode_settings.dart';
import 'package:nipaplay/providers/jellyfin_transcode_provider.dart';
import 'package:nipaplay/providers/emby_transcode_provider.dart';

enum MediaServerType { jellyfin, emby }

// 通用媒体库接口
abstract class MediaLibrary {
  String get id;
  String get name;
  String get type;
}

// 通用媒体服务器提供者接口
abstract class MediaServerProvider {
  bool get isConnected;
  String? get serverUrl;
  String? get username;
  String? get errorMessage;
  List<MediaLibrary> get availableLibraries;
  Set<String> get selectedLibraryIds;
  
  Future<bool> connectToServer(String server, String username, String password, {String? addressName});
  Future<void> disconnectFromServer();
  Future<void> updateSelectedLibraries(Set<String> libraryIds);
}

// Jellyfin适配器
class JellyfinMediaLibraryAdapter implements MediaLibrary {
  final JellyfinLibrary _library;
  JellyfinMediaLibraryAdapter(this._library);
  
  @override
  String get id => _library.id;
  @override
  String get name => _library.name;
  @override
  String get type => _library.type ?? 'unknown';
}

class JellyfinProviderAdapter implements MediaServerProvider {
  final JellyfinProvider _provider;
  JellyfinProviderAdapter(this._provider);
  
  @override
  bool get isConnected => _provider.isConnected;
  @override
  String? get serverUrl => _provider.serverUrl;
  @override
  String? get username => _provider.username;
  @override
  String? get errorMessage => _provider.errorMessage;
  @override
  List<MediaLibrary> get availableLibraries => 
    _provider.availableLibraries.map((lib) => JellyfinMediaLibraryAdapter(lib)).toList();
  @override
  Set<String> get selectedLibraryIds => _provider.selectedLibraryIds.toSet();
  
  @override
  Future<bool> connectToServer(String server, String username, String password, {String? addressName}) =>
    _provider.connectToServer(server, username, password, addressName: addressName);
  @override
  Future<void> disconnectFromServer() => _provider.disconnectFromServer();
  @override
  Future<void> updateSelectedLibraries(Set<String> libraryIds) =>
    _provider.updateSelectedLibraries(libraryIds.toList());
}

// Emby适配器
class EmbyMediaLibraryAdapter implements MediaLibrary {
  final EmbyLibrary _library;
  EmbyMediaLibraryAdapter(this._library);
  
  @override
  String get id => _library.id;
  @override
  String get name => _library.name;
  @override
  String get type => _library.type ?? 'unknown';
}

class EmbyProviderAdapter implements MediaServerProvider {
  final EmbyProvider _provider;
  EmbyProviderAdapter(this._provider);
  
  @override
  bool get isConnected => _provider.isConnected;
  @override
  String? get serverUrl => _provider.serverUrl;
  @override
  String? get username => _provider.username;
  @override
  String? get errorMessage => _provider.errorMessage;
  @override
  List<MediaLibrary> get availableLibraries => 
    _provider.availableLibraries.map((lib) => EmbyMediaLibraryAdapter(lib)).toList();
  @override
  Set<String> get selectedLibraryIds => _provider.selectedLibraryIds.toSet();
  
  @override
  Future<bool> connectToServer(String server, String username, String password, {String? addressName}) =>
    _provider.connectToServer(server, username, password, addressName: addressName);
  @override
  Future<void> disconnectFromServer() => _provider.disconnectFromServer();
  @override
  Future<void> updateSelectedLibraries(Set<String> libraryIds) =>
    _provider.updateSelectedLibraries(libraryIds.toList());
}

class NetworkMediaServerDialog extends StatefulWidget {
  final MediaServerType serverType;
  
  const NetworkMediaServerDialog({
    super.key,
    required this.serverType,
  });

  @override
  State<NetworkMediaServerDialog> createState() => _NetworkMediaServerDialogState();

  static Future<bool?> show(BuildContext context, MediaServerType serverType) {
    final provider = _getProvider(context, serverType);
    
    if (provider.isConnected) {
      // 如果已连接，显示设置对话框
      final enableAnimation = Provider.of<AppearanceSettingsProvider>(
        context,
        listen: false,
      ).enablePageAnimation;

      return NipaplayWindow.show<bool>(
        context: context,
        enableAnimation: enableAnimation,
        barrierDismissible: true,
        child: NetworkMediaServerDialog(serverType: serverType),
      );
    } else {
      // 如果未连接，显示登录对话框
      final serverName = serverType == MediaServerType.jellyfin ? 'Jellyfin' : 'Emby';
      final defaultPort = serverType == MediaServerType.jellyfin ? '8096' : '8096';
      
      return BlurLoginDialog.show(
        context,
        title: '连接到${serverName}服务器',
        fields: [
          LoginField(
            key: 'server',
            label: '服务器地址',
            hint: '例如：http://192.168.1.100:$defaultPort',
            initialValue: provider.serverUrl,
          ),
          LoginField(
            key: 'username',
            label: '用户名',
            initialValue: provider.username,
          ),
          const LoginField(
            key: 'password',
            label: '密码',
            isPassword: true,
            required: false,
          ),
          const LoginField(
            key: 'address_name',
            label: '地址名称（可留空自动生成）',
            hint: '例如：家庭网络、公网访问',
            required: false,
          ),
        ],
        loginButtonText: '连接',
        onLogin: (values) async {
          // 生成地址名称（如果未提供则自动生成）
          final serverUrl = values['server']!;
          final addressName = UrlNameGenerator.generateAddressName(serverUrl, customName: values['address_name']);
          
          // 将地址名称传递给provider层
          final success = await provider.connectToServer(
            serverUrl,
            values['username']!,
            values['password']!,
            addressName: addressName,
          );
          
          return LoginResult(
            success: success,
            message: success ? '连接成功' : (provider.errorMessage ?? '连接失败，请检查服务器地址和登录信息'),
          );
        },
      );
    }
  }
  
  static MediaServerProvider _getProvider(BuildContext context, MediaServerType serverType) {
    switch (serverType) {
      case MediaServerType.jellyfin:
        return JellyfinProviderAdapter(Provider.of<JellyfinProvider>(context, listen: false));
      case MediaServerType.emby:
        return EmbyProviderAdapter(Provider.of<EmbyProvider>(context, listen: false));
    }
  }
}

class _LibrarySelectionTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final bool isSelected;
  final Color accentColor;
  final Color textColor;
  final Color subTextColor;
  final VoidCallback onTap;

  const _LibrarySelectionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.isSelected,
    required this.accentColor,
    required this.textColor,
    required this.subTextColor,
    required this.onTap,
  });

  @override
  State<_LibrarySelectionTile> createState() => _LibrarySelectionTileState();
}

class _LibrarySelectionTileState extends State<_LibrarySelectionTile> {
  bool _isHovered = false;
  bool _isPressed = false;

  void _setHovered(bool value) {
    if (_isHovered == value) return;
    setState(() {
      _isHovered = value;
    });
  }

  void _setPressed(bool value) {
    if (_isPressed == value) return;
    setState(() {
      _isPressed = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isActive = widget.isSelected || _isHovered || _isPressed;
    final Color titleColor =
        isActive ? widget.accentColor : widget.textColor;
    final Color subtitleColor = isActive
        ? widget.accentColor.withOpacity(0.7)
        : widget.subTextColor;
    final Color iconColor =
        isActive ? widget.accentColor : widget.iconColor;

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: isActive ? 1.03 : 1.0,
          alignment: Alignment.centerLeft,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(widget.icon, color: iconColor, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        locale: const Locale("zh-Hans", "zh"),
                        style: TextStyle(
                          color: subtitleColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NetworkMediaServerDialogState extends State<NetworkMediaServerDialog> {
  static const Color _accentColor = Color(0xFFFF2E55);

  Set<String> _currentSelectedLibraryIds = {};
  List<MediaLibrary> _currentAvailableLibraries = [];
  late MediaServerProvider _provider;
  List<ServerAddress> _serverAddresses = [];
  String? _currentAddressId;
  
  // 转码设置相关状态
  bool _transcodeSettingsExpanded = false;
  JellyfinVideoQuality _selectedQuality = JellyfinVideoQuality.bandwidth5m;
  bool _transcodeEnabled = true;

  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;
  Color get _textColor => Theme.of(context).colorScheme.onSurface;
  Color get _subTextColor => _textColor.withOpacity(0.7);
  Color get _mutedTextColor => _textColor.withOpacity(0.5);
  Color get _borderColor => _textColor.withOpacity(_isDarkMode ? 0.12 : 0.2);
  Color get _surfaceColor =>
      _isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F2);
  Color get _panelColor =>
      _isDarkMode ? const Color(0xFF262626) : const Color(0xFFE8E8E8);
  Color get _panelAltColor =>
      _isDarkMode ? const Color(0xFF2B2B2B) : const Color(0xFFF7F7F7);

  ButtonStyle _plainButtonStyle({Color? baseColor}) {
    final resolvedBase = baseColor ?? _textColor;
    return ButtonStyle(
      foregroundColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.disabled)) {
          return _mutedTextColor;
        }
        if (states.contains(MaterialState.hovered)) {
          return _accentColor;
        }
        return resolvedBase;
      }),
      overlayColor: MaterialStateProperty.all(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      padding: MaterialStateProperty.all(
        const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider = NetworkMediaServerDialog._getProvider(context, widget.serverType);

    // 初始化转码Provider（Jellyfin/Emby 各自独立）
    if (widget.serverType == MediaServerType.jellyfin) {
      try {
        final jProvider = Provider.of<JellyfinTranscodeProvider>(context, listen: false);
        jProvider.initialize().then((_) {
          if (mounted) {
            setState(() {
              _selectedQuality = jProvider.currentVideoQuality;
              _transcodeEnabled = jProvider.transcodeEnabled;
            });
          }
        });
      } catch (_) {
        // 回退到单例，避免在 Provider 未挂载（热重载等）时崩溃
        final jProvider = JellyfinTranscodeProvider();
        jProvider.initialize().then((_) {
          if (mounted) {
            setState(() {
              _selectedQuality = jProvider.currentVideoQuality;
              _transcodeEnabled = jProvider.transcodeEnabled;
            });
          }
        });
      }
    } else if (widget.serverType == MediaServerType.emby) {
      try {
        final eProvider = Provider.of<EmbyTranscodeProvider>(context, listen: false);
        eProvider.initialize().then((_) {
          if (mounted) {
            setState(() {
              _selectedQuality = eProvider.currentVideoQuality;
              _transcodeEnabled = eProvider.transcodeEnabled;
            });
          }
        });
      } catch (_) {
        final eProvider = EmbyTranscodeProvider();
        eProvider.initialize().then((_) {
          if (mounted) {
            setState(() {
              _selectedQuality = eProvider.currentVideoQuality;
              _transcodeEnabled = eProvider.transcodeEnabled;
            });
          }
        });
      }
    }

    if (_provider.isConnected) {
      _currentAvailableLibraries = List.from(_provider.availableLibraries);
      _currentSelectedLibraryIds = Set.from(_provider.selectedLibraryIds);
      
      // 加载多地址信息
      _loadMultiAddressInfo();
    } else {
      _currentAvailableLibraries = [];
      _currentSelectedLibraryIds = {};
      _serverAddresses = [];
      _currentAddressId = null;
    }
  }
  
  void _loadMultiAddressInfo() {
    // 根据服务器类型获取地址列表
    switch (widget.serverType) {
      case MediaServerType.jellyfin:
        final service = JellyfinService.instance;
        _serverAddresses = service.getServerAddresses();
        // 从当前服务器URL判断当前地址ID（这里简化处理）
        break;
      case MediaServerType.emby:
        final service = EmbyService.instance;
        _serverAddresses = service.getServerAddresses();
        break;
    }
  }
  
  Future<void> _handleAddAddress(String url, String name) async {
    try {
      bool success = false;
      switch (widget.serverType) {
        case MediaServerType.jellyfin:
          success = await JellyfinService.instance.addServerAddress(url, name);
          break;
        case MediaServerType.emby:
          success = await EmbyService.instance.addServerAddress(url, name);
          break;
      }
      
      if (success) {
        _loadMultiAddressInfo();
        setState(() {});
        if (mounted) {
          BlurSnackBar.show(context, '地址添加成功');
        }
      } else {
        if (mounted) {
          BlurSnackBar.show(context, '添加地址失败：未知原因');
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMsg = e.toString();
        if (errorMsg.startsWith('Exception: ')) {
          errorMsg = errorMsg.substring(11);
        }
        BlurSnackBar.show(context, '添加地址失败：$errorMsg');
      }
    }
  }
  
  Future<void> _handleRemoveAddress(String addressId) async {
    try {
      bool success = false;
      switch (widget.serverType) {
        case MediaServerType.jellyfin:
          success = await JellyfinService.instance.removeServerAddress(addressId);
          break;
        case MediaServerType.emby:
          success = await EmbyService.instance.removeServerAddress(addressId);
          break;
      }
      
      if (success) {
        _loadMultiAddressInfo();
        setState(() {});
        if (mounted) {
          BlurSnackBar.show(context, '地址删除成功');
        }
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '删除地址失败: $e');
      }
    }
  }
  
  Future<void> _handleSwitchAddress(String addressId) async {
    try {
      bool success = false;
      switch (widget.serverType) {
        case MediaServerType.jellyfin:
          success = await JellyfinService.instance.switchToAddress(addressId);
          break;
        case MediaServerType.emby:
          success = await EmbyService.instance.switchToAddress(addressId);
          break;
      }
      
      if (success) {
        _loadMultiAddressInfo();
        setState(() {});
        if (mounted) {
          BlurSnackBar.show(context, '已切换到新地址');
        }
      } else {
        if (mounted) {
          BlurSnackBar.show(context, '切换地址失败，请检查连接');
        }
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '切换地址失败: $e');
      }
    }
  }

  Future<void> _handleUpdatePriority(String addressId, int priority) async {
    try {
      bool success = false;
      switch (widget.serverType) {
        case MediaServerType.jellyfin:
          success = await JellyfinService.instance.updateServerPriority(addressId, priority);
          break;
        case MediaServerType.emby:
          success = await EmbyService.instance.updateServerPriority(addressId, priority);
          break;
      }
      
      if (success) {
        _loadMultiAddressInfo();
        setState(() {});
        if (mounted) {
          BlurSnackBar.show(context, '优先级已更新');
        }
      } else {
        if (mounted) {
          BlurSnackBar.show(context, '更新优先级失败');
        }
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '更新优先级失败: $e');
      }
    }
  }

  Future<void> _disconnectFromServer() async {
    await _provider.disconnectFromServer();
    if (mounted) {
      BlurSnackBar.show(context, '已断开连接');
      Navigator.of(context).pop(false);
    }
  }

  Future<void> _saveSelectedLibraries() async {
    try {
      await _provider.updateSelectedLibraries(_currentSelectedLibraryIds);
      if (mounted) {
        BlurSnackBar.show(context, '设置已保存');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '保存失败：$e');
      }
    }
  }

  String get _serverName {
    switch (widget.serverType) {
      case MediaServerType.jellyfin:
        return 'Jellyfin';
      case MediaServerType.emby:
        return 'Emby';
    }
  }

  String get _serverIconAsset {
    switch (widget.serverType) {
      case MediaServerType.jellyfin:
        return 'assets/jellyfin.svg';
      case MediaServerType.emby:
        return 'assets/emby.svg';
    }
  }

  bool get _supportsTranscode =>
      widget.serverType == MediaServerType.jellyfin ||
      widget.serverType == MediaServerType.emby;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final baseDialogWidth =
        globals.DialogSizes.getDialogWidth(screenSize.width);
    final maxDialogWidth = screenSize.width * 0.92;
    final resolvedDialogWidth =
        screenSize.width >= 900 ? 900.0 : baseDialogWidth;
    final dialogWidth = resolvedDialogWidth > maxDialogWidth
        ? maxDialogWidth
        : resolvedDialogWidth;

    return NipaplayWindowScaffold(
      maxWidth: dialogWidth,
      maxHeightFactor: 0.9,
      onClose: () => Navigator.of(context).maybePop(),
      backgroundColor: _surfaceColor,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 500),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWideLayout = constraints.maxWidth >= 760;
                return SingleChildScrollView(
                  child:
                      isWideLayout ? _buildWideContent() : _buildNarrowContent(),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWideContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildServerInfo(),
                  const SizedBox(height: 20),
                  if (_serverAddresses.isNotEmpty) ...[
                    MultiAddressManagerWidget(
                      addresses: _serverAddresses,
                      currentAddressId: _currentAddressId,
                      onAddAddress: _handleAddAddress,
                      onRemoveAddress: _handleRemoveAddress,
                      onSwitchAddress: _handleSwitchAddress,
                      onUpdatePriority: _handleUpdatePriority,
                    ),
                    const SizedBox(height: 20),
                  ],
                  _buildActionButtons(),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLibrariesSection(),
                  if (_supportsTranscode) ...[
                    const SizedBox(height: 20),
                    _buildTranscodeSection(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNarrowContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: 20),
        _buildServerInfo(),
        const SizedBox(height: 20),
        if (_serverAddresses.isNotEmpty) ...[
          MultiAddressManagerWidget(
            addresses: _serverAddresses,
            currentAddressId: _currentAddressId,
            onAddAddress: _handleAddAddress,
            onRemoveAddress: _handleRemoveAddress,
            onSwitchAddress: _handleSwitchAddress,
            onUpdatePriority: _handleUpdatePriority,
          ),
          const SizedBox(height: 20),
        ],
        _buildLibrariesSection(),
        if (_supportsTranscode) ...[
          const SizedBox(height: 20),
          _buildTranscodeSection(),
        ],
        const SizedBox(height: 4),
        _buildActionButtons(),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _accentColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _accentColor.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: SvgPicture.asset(
            _serverIconAsset,
            width: 28,
            height: 28,
            colorFilter: const ColorFilter.mode(
              _accentColor,
              BlendMode.srcIn,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$_serverName 服务器设置',
                style: TextStyle(
                  color: _textColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '管理媒体库连接和选择',
                locale:Locale("zh-Hans","zh"),
style: TextStyle(
                  color: _subTextColor,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildServerInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _accentColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.dns, color: _accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                '服务器:',
                locale:Locale("zh-Hans","zh"),
style: TextStyle(color: _subTextColor, fontSize: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _provider.serverUrl ?? '未知',
                  style: TextStyle(color: _textColor, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _accentColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.person, color: _accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                '用户:',
                locale:Locale("zh-Hans","zh"),
style: TextStyle(color: _subTextColor, fontSize: 14),
              ),
              const SizedBox(width: 8),
              Text(
                _provider.username ?? '匿名',
                style: TextStyle(color: _textColor, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLibrariesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _accentColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child:
                  const Icon(Icons.library_books, color: _accentColor, size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              '媒体库选择',
              locale:Locale("zh-Hans","zh"),
style: TextStyle(
                color: _textColor,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 300,
          decoration: BoxDecoration(
            color: _panelColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _borderColor),
          ),
          child: _currentAvailableLibraries.isEmpty
              ? _buildEmptyLibrariesState()
              : _buildLibrariesList(),
        ),
      ],
    );
  }

  Widget _buildEmptyLibrariesState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _textColor.withOpacity(_isDarkMode ? 0.08 : 0.06),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Icon(
                Icons.folder_off_outlined,
                color: _mutedTextColor,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '没有可用的媒体库',
              locale:Locale("zh-Hans","zh"),
style: TextStyle(
                color: _subTextColor,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '请检查服务器连接状态',
              locale:Locale("zh-Hans","zh"),
style: TextStyle(
                color: _mutedTextColor,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibrariesList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _currentAvailableLibraries.length,
      separatorBuilder: (context, index) => Divider(
        color: _borderColor,
        height: 1,
      ),
      itemBuilder: (context, index) {
        final library = _currentAvailableLibraries[index];
        final isSelected = _currentSelectedLibraryIds.contains(library.id);

        return _LibrarySelectionTile(
          key: ValueKey(library.id),
          title: library.name,
          subtitle: library.type,
          icon: _getLibraryTypeIcon(library.type),
          iconColor: _getLibraryTypeColor(library.type),
          isSelected: isSelected,
          accentColor: _accentColor,
          textColor: _textColor,
          subTextColor: _subTextColor,
          onTap: () {
            setState(() {
              if (isSelected) {
                _currentSelectedLibraryIds.remove(library.id);
              } else {
                _currentSelectedLibraryIds.add(library.id);
              }
            });
          },
        );
      },
    );
  }

  IconData _getLibraryTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'movies':
        return Icons.movie_outlined;
      case 'tvshows':
        return Icons.tv_outlined;
      case 'music':
        return Icons.music_note_outlined;
      case 'books':
        return Icons.book_outlined;
      default:
        return Icons.folder_outlined;
    }
  }

  Color _getLibraryTypeColor(String type) {
    return _subTextColor;
  }

  Widget _buildTranscodeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _transcodeSettingsExpanded = !_transcodeSettingsExpanded;
            });
          },
          borderRadius: BorderRadius.circular(12),
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _panelColor,
              borderRadius: _transcodeSettingsExpanded 
                  ? const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    )
                  : BorderRadius.circular(12),
              border: _transcodeSettingsExpanded
                  ? Border(
                      top: BorderSide(color: _borderColor),
                      left: BorderSide(color: _borderColor),
                      right: BorderSide(color: _borderColor),
                    )
                  : Border.all(color: _borderColor),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _accentColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:
                      const Icon(Icons.high_quality, color: _accentColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '转码设置',
                        locale:Locale("zh-Hans","zh"),
style: TextStyle(
                          color: _textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '当前默认质量: ${_selectedQuality.displayName}',
                        locale:Locale("zh-Hans","zh"),
style: TextStyle(
                          color: _subTextColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _transcodeSettingsExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.expand_more,
                    color: _subTextColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: _transcodeSettingsExpanded
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  decoration: BoxDecoration(
                    color: _panelAltColor,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                    border: Border(
                      left: BorderSide(color: _borderColor),
                      right: BorderSide(color: _borderColor),
                      bottom: BorderSide(color: _borderColor),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '启用转码',
                              locale:Locale("zh-Hans","zh"),
style: TextStyle(
                                color: _textColor.withOpacity(0.9),
                                fontSize: 14,
                              ),
                            ),
                          ),
                          FluentSettingsSwitch(
                            value: _transcodeEnabled,
                            onChanged: (value) =>
                                _handleTranscodeEnabledChanged(value),
                          ),
                        ],
                      ),
                      if (_transcodeEnabled) ...[
                        const SizedBox(height: 16),
                        Text(
                          '默认清晰度',
                          locale:Locale("zh-Hans","zh"),
style: TextStyle(
                            color: _textColor.withOpacity(0.9),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...JellyfinVideoQuality.values.map((quality) {
                          final isSelected = _selectedQuality == quality;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _handleQualityChanged(quality),
                                borderRadius: BorderRadius.circular(8),
                                splashFactory: NoSplash.splashFactory,
                                splashColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                hoverColor: Colors.transparent,
                                focusColor: Colors.transparent,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isSelected 
                                        ? _accentColor.withOpacity(
                                            _isDarkMode ? 0.25 : 0.2)
                                        : _panelAltColor,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected 
                                          ? _accentColor
                                          : _borderColor,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                        color: isSelected ? _accentColor : _subTextColor,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              quality.displayName,
                                              locale:Locale("zh-Hans","zh"),
style: TextStyle(
                                                color: isSelected ? _accentColor : _textColor,
                                                fontSize: 14,
                                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ],
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }

  Future<void> _handleTranscodeEnabledChanged(bool enabled) async {
    try {
      bool success = false;
      if (widget.serverType == MediaServerType.jellyfin) {
        try {
          final j = Provider.of<JellyfinTranscodeProvider>(context, listen: false);
          success = await j.setTranscodeEnabled(enabled);
        } catch (_) {
          // 回退到单例
          success = await JellyfinTranscodeProvider().setTranscodeEnabled(enabled);
        }
      } else if (widget.serverType == MediaServerType.emby) {
        try {
          final e = Provider.of<EmbyTranscodeProvider>(context, listen: false);
          success = await e.setTranscodeEnabled(enabled);
        } catch (_) {
          success = await EmbyTranscodeProvider().setTranscodeEnabled(enabled);
        }
      }

      if (success) {
        setState(() {
          _transcodeEnabled = enabled;
          // 如果关闭转码，自动将质量重置为原画
          if (!enabled) {
            _selectedQuality = JellyfinVideoQuality.original;
          }
        });
        if (mounted) {
          BlurSnackBar.show(context, enabled ? '转码已启用' : '转码已禁用');
        }
      } else {
        if (mounted) {
          BlurSnackBar.show(context, '设置失败');
        }
      }
    } catch (e) {
      debugPrint('更新转码启用状态失败: $e');
      if (mounted) {
        BlurSnackBar.show(context, '设置失败');
      }
    }
  }

  Future<void> _handleQualityChanged(JellyfinVideoQuality quality) async {
    if (_selectedQuality == quality) return;

    try {
      bool success = false;
      if (widget.serverType == MediaServerType.jellyfin) {
        try {
          final j = Provider.of<JellyfinTranscodeProvider>(context, listen: false);
          success = await j.setDefaultVideoQuality(quality);
          // 当选择非原画质量时，自动启用转码
          if (quality != JellyfinVideoQuality.original) {
            await j.setTranscodeEnabled(true);
          }
        } catch (_) {
          success = await JellyfinTranscodeProvider().setDefaultVideoQuality(quality);
          // 当选择非原画质量时，自动启用转码
          if (quality != JellyfinVideoQuality.original) {
            await JellyfinTranscodeProvider().setTranscodeEnabled(true);
          }
        }
      } else if (widget.serverType == MediaServerType.emby) {
        try {
          final e = Provider.of<EmbyTranscodeProvider>(context, listen: false);
          success = await e.setDefaultVideoQuality(quality);
          // 当选择非原画质量时，自动启用转码
          if (quality != JellyfinVideoQuality.original) {
            await e.setTranscodeEnabled(true);
          }
        } catch (_) {
          success = await EmbyTranscodeProvider().setDefaultVideoQuality(quality);
          // 当选择非原画质量时，自动启用转码
          if (quality != JellyfinVideoQuality.original) {
            await EmbyTranscodeProvider().setTranscodeEnabled(true);
          }
        }
      }

      if (success) {
        setState(() {
          _selectedQuality = quality;
        });
        if (mounted) {
          BlurSnackBar.show(context, '默认质量已设置为: ${quality.displayName}');
        }
      } else {
        if (mounted) {
          BlurSnackBar.show(context, '设置失败');
        }
      }
    } catch (e) {
      debugPrint('更新默认质量失败: $e');
      if (mounted) {
        BlurSnackBar.show(context, '设置失败');
      }
    }
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: TextButton.icon(
            onPressed: _disconnectFromServer,
            style: _plainButtonStyle(),
            icon: const Icon(Icons.link_off, size: 18),
            label: const Text('断开连接'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextButton.icon(
            onPressed: _saveSelectedLibraries,
            style: _plainButtonStyle(baseColor: _accentColor),
            icon: const Icon(Icons.save, size: 18),
            label: const Text('保存设置'),
          ),
        ),
      ],
    );
  }
}
