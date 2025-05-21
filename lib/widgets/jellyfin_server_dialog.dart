import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/widgets/blur_snackbar.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';

class JellyfinServerDialog extends StatefulWidget {
  const JellyfinServerDialog({super.key});

  @override
  State<JellyfinServerDialog> createState() => _JellyfinServerDialogState();

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (dialogContext) => const JellyfinServerDialog(),
    );
  }
}

class _JellyfinServerDialogState extends State<JellyfinServerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isConnecting = false; // 用于连接过程中的加载指示

  // 本地状态，用于UI交互，与Provider同步
  Set<String> _currentSelectedLibraryIds = {};
  List<JellyfinLibrary> _currentAvailableLibraries = [];

  late JellyfinProvider _jellyfinProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 在这里安全地访问Provider
    _jellyfinProvider = Provider.of<JellyfinProvider>(context); // listen: true 默认

    // 从Provider初始化UI相关的状态
    _serverController.text = _jellyfinProvider.serverUrl ?? '';
    _usernameController.text = _jellyfinProvider.username ?? '';
    _passwordController.text = ''; // 密码不预填

    if (_jellyfinProvider.isConnected) {
      // 直接从provider获取最新的库信息
      _currentAvailableLibraries = List.from(_jellyfinProvider.availableLibraries);
      _currentSelectedLibraryIds = Set.from(_jellyfinProvider.selectedLibraryIds);
    } else {
      _currentAvailableLibraries = [];
      _currentSelectedLibraryIds = {};
    }
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _connectToServer() async {
    if (_formKey.currentState?.validate() != true) return;

    setState(() { _isConnecting = true; });

    final success = await _jellyfinProvider.connectToServer(
      _serverController.text.trim(),
      _usernameController.text.trim(),
      _passwordController.text,
    );

    if (mounted) {
      setState(() { _isConnecting = false; });
      if (success) {
        BlurSnackBar.show(context, '连接成功');
        // UI会自动更新因为Provider会notifyListeners
      } else {
        BlurSnackBar.show(context, _jellyfinProvider.errorMessage ?? '连接失败，请检查服务器地址和登录信息');
      }
    }
  }

  Future<void> _disconnectFromServer() async {
    await _jellyfinProvider.disconnectFromServer();
    if (mounted) {
      BlurSnackBar.show(context, '已断开连接');
      // UI会自动更新
    }
  }

  Future<void> _saveSelectedLibraries() async {
    await _jellyfinProvider.updateSelectedLibraries(_currentSelectedLibraryIds.toList());
    if (mounted) {
      Navigator.of(context).pop(true);
      BlurSnackBar.show(context, '设置已保存');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 使用 Consumer 或者直接在 build 方法中读取 Provider.of 来响应状态变化
    // JellyfinProvider _provider = Provider.of<JellyfinProvider>(context); // 可以在这里获取最新的状态

    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassmorphicContainer(
        width: 400,
        height: _jellyfinProvider.isConnected ? 500 : 350, // 根据Provider状态调整高度
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
          padding: const EdgeInsets.all(24.0),
          // 直接根据Provider的连接状态来决定显示哪个视图
          child: _jellyfinProvider.isConnected 
                 ? _buildConnectedView() 
                 : _buildConnectionForm(),
        ),
      ),
    );
  }

  Widget _buildConnectionForm() {
    // 表单的控制器 (_serverController, _usernameController) 已在 didChangeDependencies 中
    // 根据 provider 的 serverUrl 和 username (即使未连接也可能存在上次保存的值) 进行了初始化。
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('连接到Jellyfin服务器', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            TextFormField(
              controller: _serverController,
              // ... 其他属性和校验 ...
              enabled: !_isConnecting,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _usernameController,
              // ... 其他属性 ...
              enabled: !_isConnecting,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              // ... 其他属性 ...
              enabled: !_isConnecting,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: _isConnecting ? null : _connectToServer,
                child: _isConnecting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('连接'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedView() {
    // 此视图现在也依赖于 _jellyfinProvider 的状态 (如 serverUrl, username)
    // 以及本地的 _currentAvailableLibraries 和 _currentSelectedLibraryIds 进行交互
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Jellyfin服务器设置', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green[400], size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text('已连接到 ${_jellyfinProvider.serverUrl ?? "未知服务器"}', overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70))),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.person, color: Colors.blue, size: 16),
            const SizedBox(width: 8),
            Text('用户: ${_jellyfinProvider.username ?? "匿名"}', style: const TextStyle(color: Colors.white70)),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Ionicons.library_outline, size: 18),
            const SizedBox(width: 8),
            const Text('可用的电视剧媒体库', style: TextStyle(fontWeight: FontWeight.bold)),
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
              ? const Center(child: Text('没有找到电视剧媒体库', style: TextStyle(color: Colors.white70)))
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
