import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_login_dialog.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

class EmbyServerDialog extends StatefulWidget {
  const EmbyServerDialog({super.key});

  @override
  State<EmbyServerDialog> createState() => _EmbyServerDialogState();

  static Future<bool?> show(BuildContext context) {
    final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
    
    if (embyProvider.isConnected) {
      // 如果已连接，显示设置对话框
      return showDialog<bool>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withOpacity(0.5),
        builder: (dialogContext) => const EmbyServerDialog(),
      );
    } else {
      // 如果未连接，显示登录对话框
      return BlurLoginDialog.show(
        context,
        title: '连接到Emby服务器',
        fields: [
          LoginField(
            key: 'server',
            label: '服务器地址',
            hint: '例如：http://192.168.1.100:8096',
            initialValue: embyProvider.serverUrl,
          ),
          LoginField(
            key: 'username',
            label: '用户名',
            initialValue: embyProvider.username,
          ),
          const LoginField(
            key: 'password',
            label: '密码',
            isPassword: true,
            required: false, // 密码可以为空
          ),
        ],
        loginButtonText: '连接',
        onLogin: (values) async {
          final success = await embyProvider.connectToServer(
            values['server']!,
            values['username']!,
            values['password']!,
          );
          
          return LoginResult(
            success: success,
            message: success ? '连接成功' : (embyProvider.errorMessage ?? '连接失败，请检查服务器地址和登录信息'),
          );
        },
      );
    }
  }
}

class _EmbyServerDialogState extends State<EmbyServerDialog> {
  // 本地状态，用于UI交互，与Provider同步
  Set<String> _currentSelectedLibraryIds = {};
  List<EmbyLibrary> _currentAvailableLibraries = [];

  late EmbyProvider _embyProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 在这里安全地访问Provider
    _embyProvider = Provider.of<EmbyProvider>(context); // listen: true 默认

    if (_embyProvider.isConnected) {
      // 直接从provider获取最新的库信息
      _currentAvailableLibraries = List.from(_embyProvider.availableLibraries);
      _currentSelectedLibraryIds = Set.from(_embyProvider.selectedLibraryIds);
    } else {
      _currentAvailableLibraries = [];
      _currentSelectedLibraryIds = {};
    }
  }

  Future<void> _disconnectFromServer() async {
    await _embyProvider.disconnectFromServer();
    if (mounted) {
      BlurSnackBar.show(context, '已断开连接');
      Navigator.of(context).pop(false); // 关闭对话框
    }
  }

  Future<void> _saveSelectedLibraries() async {
    await _embyProvider.updateSelectedLibraries(_currentSelectedLibraryIds.toList());
    if (mounted) {
      Navigator.of(context).pop(true);
      BlurSnackBar.show(context, '设置已保存');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height;
    final isPhone = screenSize.shortestSide < 600;
    
    // 使用预计算的对话框宽度和高度
    final dialogWidth = globals.DialogSizes.getDialogWidth(screenSize.width);
    final dialogHeight = globals.DialogSizes.serverDialogHeight;
    
    // 获取键盘高度，用于动态调整底部间距
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: keyboardHeight),
        child: GlassmorphicContainer(
          width: dialogWidth,
          height: dialogHeight,
          borderRadius: 20,
          blur: 20,
          alignment: Alignment.center,
          border: 1.5,
          linearGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF212121).withOpacity(0.6),
              const Color(0xFF424242).withOpacity(0.6),
            ],
            stops: const [0.1, 1],
          ),
          borderGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF424242).withOpacity(0.5),
              const Color(0xFF424242).withOpacity(0.5),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(isPhone ? 20.0 : 24.0),
            child: _buildConnectedView(),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectedView() {
    // 此视图现在也依赖于 _embyProvider 的状态 (如 serverUrl, username)
    // 以及本地的 _currentAvailableLibraries 和 _currentSelectedLibraryIds 进行交互
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Emby服务器设置', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green[400], size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text('已连接到 ${_embyProvider.serverUrl ?? "未知服务器"}', overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70))),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.person, color: Colors.blue, size: 16),
            const SizedBox(width: 8),
            Text('用户: ${_embyProvider.username ?? "匿名"}', style: const TextStyle(color: Colors.white70)),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Ionicons.library_outline, size: 18),
            const SizedBox(width: 8),
            const Text('可用的媒体库', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            GestureDetector(
              onTap: () {
                setState(() { // 修改的是本地的 _currentSelectedLibraryIds
                  if (_currentSelectedLibraryIds.length == _currentAvailableLibraries.length && _currentAvailableLibraries.isNotEmpty) {
                    _currentSelectedLibraryIds.clear();
                  } else {
                    _currentSelectedLibraryIds = _currentAvailableLibraries.map((lib) => lib.id).toSet();
                  }
                });
              },
              child: Text(
                (_currentSelectedLibraryIds.length == _currentAvailableLibraries.length && _currentAvailableLibraries.isNotEmpty) ? '取消全选' : '全选',
                style: TextStyle(color: Colors.blue[300], fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _currentAvailableLibraries.isEmpty
              ? const Center(child: Text('没有找到媒体库', style: TextStyle(color: Colors.white70)))
              : ListView.builder(
                  itemCount: _currentAvailableLibraries.length,
                  itemBuilder: (context, index) {
                    final library = _currentAvailableLibraries[index];
                    final isSelected = _currentSelectedLibraryIds.contains(library.id);
                    return CheckboxListTile(
                      title: Text(library.name),
                      subtitle: Text('${library.totalItems ?? 0} 个项目', style: const TextStyle(fontSize: 12)),
                      value: isSelected,
                      onChanged: (value) {
                        setState(() { // 修改的是本地的 _currentSelectedLibraryIds
                          if (value == true) {
                            _currentSelectedLibraryIds.add(library.id);
                          } else {
                            _currentSelectedLibraryIds.remove(library.id);
                          }
                        });
                      },
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  },
                ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: _disconnectFromServer,
              icon: const Icon(Icons.link_off),
              label: const Text('断开连接'),
              style: TextButton.styleFrom(foregroundColor: Colors.red[300]),
            ),
            ElevatedButton(
              onPressed: _saveSelectedLibraries,
              child: const Text('保存设置'),
            ),
          ],
        ),
      ],
    );
  }
}
