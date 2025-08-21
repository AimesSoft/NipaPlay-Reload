import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_button.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_login_dialog.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/providers/appearance_settings_provider.dart';

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
  
  Future<bool> connectToServer(String server, String username, String password);
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
  Future<bool> connectToServer(String server, String username, String password) =>
    _provider.connectToServer(server, username, password);
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
  Future<bool> connectToServer(String server, String username, String password) =>
    _provider.connectToServer(server, username, password);
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
      return showDialog<bool>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withOpacity(0.5),
        builder: (dialogContext) => NetworkMediaServerDialog(serverType: serverType),
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
        ],
        loginButtonText: '连接',
        onLogin: (values) async {
          final success = await provider.connectToServer(
            values['server']!,
            values['username']!,
            values['password']!,
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

class _NetworkMediaServerDialogState extends State<NetworkMediaServerDialog> {
  Set<String> _currentSelectedLibraryIds = {};
  List<MediaLibrary> _currentAvailableLibraries = [];
  late MediaServerProvider _provider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider = NetworkMediaServerDialog._getProvider(context, widget.serverType);

    if (_provider.isConnected) {
      _currentAvailableLibraries = List.from(_provider.availableLibraries);
      _currentSelectedLibraryIds = Set.from(_provider.selectedLibraryIds);
    } else {
      _currentAvailableLibraries = [];
      _currentSelectedLibraryIds = {};
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

  IconData get _serverIcon {
    switch (widget.serverType) {
      case MediaServerType.jellyfin:
        return Ionicons.play_circle_outline;
      case MediaServerType.emby:
        return Ionicons.tv_outline;
    }
  }

  Color get _serverColor {
    switch (widget.serverType) {
      case MediaServerType.jellyfin:
        return Colors.blue;
      case MediaServerType.emby:
        return const Color(0xFF52B54B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = globals.DialogSizes.getDialogWidth(screenSize.width);
    final appearanceSettings = context.watch<AppearanceSettingsProvider>();
    final blurValue = appearanceSettings.enableWidgetBlurEffect ? 25.0 : 0.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: screenSize.height * 0.8,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.15),
                Colors.white.withOpacity(0.05),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurValue, sigmaY: blurValue),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 20),
                    _buildServerInfo(),
                    const SizedBox(height: 20),
                    _buildLibrariesSection(),
                    const SizedBox(height: 24),
                    _buildActionButtons(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _serverColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _serverColor.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Icon(
            _serverIcon,
            color: _serverColor,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$_serverName 服务器设置',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '管理媒体库连接和选择',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
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
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.dns, color: Colors.blue, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('服务器:', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _provider.serverUrl ?? '未知',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
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
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.person, color: Colors.green, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('用户:', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(width: 8),
              Text(
                _provider.username ?? '匿名',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLibrariesSection() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.library_books, color: Colors.purple, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                '媒体库选择',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: _currentAvailableLibraries.isEmpty
                  ? _buildEmptyLibrariesState()
                  : _buildLibrariesList(),
            ),
          ),
        ],
      ),
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
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Icon(
                Icons.folder_off_outlined,
                color: Colors.white.withOpacity(0.5),
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '没有可用的媒体库',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '请检查服务器连接状态',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
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
      padding: const EdgeInsets.all(12),
      itemCount: _currentAvailableLibraries.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final library = _currentAvailableLibraries[index];
        final isSelected = _currentSelectedLibraryIds.contains(library.id);
        
        return Container(
          decoration: BoxDecoration(
            color: isSelected 
                ? _serverColor.withOpacity(0.15)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected 
                  ? _serverColor.withOpacity(0.3)
                  : Colors.white.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: CheckboxListTile(
            value: isSelected,
            onChanged: (bool? value) {
              setState(() {
                if (value == true) {
                  _currentSelectedLibraryIds.add(library.id);
                } else {
                  _currentSelectedLibraryIds.remove(library.id);
                }
              });
            },
            title: Text(
              library.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              library.type,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _getLibraryTypeColor(library.type).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getLibraryTypeIcon(library.type),
                color: _getLibraryTypeColor(library.type),
                size: 20,
              ),
            ),
            activeColor: _serverColor,
            checkColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
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
    switch (type.toLowerCase()) {
      case 'movies':
        return Colors.red;
      case 'tvshows':
        return Colors.blue;
      case 'music':
        return Colors.green;
      case 'books':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: BlurButton(
            icon: Icons.link_off,
            text: '断开连接',
            onTap: _disconnectFromServer,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: BlurButton(
            icon: Icons.save,
            text: '保存设置',
            onTap: _saveSelectedLibraries,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          ),
        ),
      ],
    );
  }
}
