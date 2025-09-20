import 'package:flutter/material.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dialog.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/services/webdav_service.dart';

class WebDAVConnectionDialog {
  static Future<bool?> show(BuildContext context, {WebDAVConnection? editConnection}) async {
    return BlurDialog.show<bool>(
      context: context,
      title: editConnection == null ? '添加WebDAV服务器' : '编辑WebDAV服务器',
      contentWidget: _WebDAVForm(editConnection: editConnection),
    );
  }
}

class _WebDAVForm extends StatefulWidget {
  final WebDAVConnection? editConnection;
  
  const _WebDAVForm({this.editConnection});
  
  @override
  State<_WebDAVForm> createState() => _WebDAVFormState();
}

class _WebDAVFormState extends State<_WebDAVForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isLoading = false;
  bool _passwordVisible = false;
  
  @override
  void initState() {
    super.initState();
    if (widget.editConnection != null) {
      _nameController.text = widget.editConnection!.name;
      _urlController.text = widget.editConnection!.url;
      _usernameController.text = widget.editConnection!.username;
      _passwordController.text = widget.editConnection!.password;
    }
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'WebDAV服务器只会建立连接，不会自动扫描。\n您可以在连接后手动选择要扫描的文件夹。',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          
          // 连接名称
          TextFormField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: '连接名称',
              labelStyle: const TextStyle(color: Colors.white70),
              hintText: '例如：我的NAS',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white30),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white30),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.lightBlueAccent),
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '请输入连接名称';
              }
              return null;
            },
          ),
          
          const SizedBox(height: 16),
          
          // WebDAV URL
          TextFormField(
            controller: _urlController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'WebDAV地址',
              labelStyle: const TextStyle(color: Colors.white70),
              hintText: 'https://your-server.com/webdav',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white30),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white30),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.lightBlueAccent),
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '请输入WebDAV地址';
              }
              if (!value.startsWith('http://') && !value.startsWith('https://')) {
                return '请输入有效的URL地址';
              }
              return null;
            },
          ),
          
          const SizedBox(height: 16),
          
          // 用户名
          TextFormField(
            controller: _usernameController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: '用户名',
              labelStyle: const TextStyle(color: Colors.white70),
              hintText: '可选，如果服务器需要认证',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white30),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white30),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.lightBlueAccent),
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 密码
          TextFormField(
            controller: _passwordController,
            obscureText: !_passwordVisible,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: '密码',
              labelStyle: const TextStyle(color: Colors.white70),
              hintText: '可选，如果服务器需要认证',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white30),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white30),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.lightBlueAccent),
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              suffixIcon: IconButton(
                icon: Icon(
                  _passwordVisible ? Icons.visibility : Icons.visibility_off,
                  color: Colors.white70,
                ),
                onPressed: () {
                  setState(() {
                    _passwordVisible = !_passwordVisible;
                  });
                },
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // 按钮行
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _isLoading ? null : () {
                  Navigator.of(context).pop(false);
                },
                child: const Text(
                  '取消',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              
              const SizedBox(width: 12),
              
              TextButton(
                onPressed: _isLoading ? null : _testConnection,
                child: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                        ),
                      )
                    : const Text(
                        '测试连接',
                        style: TextStyle(color: Colors.orangeAccent),
                      ),
              ),
              
              const SizedBox(width: 12),
              
              ElevatedButton(
                onPressed: _isLoading ? null : _saveConnection,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.lightBlueAccent.withOpacity(0.2),
                  foregroundColor: Colors.lightBlueAccent,
                ),
                child: Text(widget.editConnection == null ? '添加' : '保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      print('🧪 开始测试WebDAV连接...');
      final connection = WebDAVConnection(
        name: _nameController.text.trim(),
        url: _urlController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
      );
      
      print('📋 连接信息:');
      print('  名称: ${connection.name}');
      print('  地址: ${connection.url}');
      print('  用户名: ${connection.username}');
      print('  密码: ${connection.password.isNotEmpty ? '[已设置]' : '[未设置]'}');
      
      final isValid = await WebDAVService.instance.testConnection(connection);
      
      if (mounted) {
        if (isValid) {
          BlurSnackBar.show(context, '连接测试成功！');
        } else {
          BlurSnackBar.show(context, '连接测试失败，请检查地址和认证信息，查看控制台获取详细错误');
        }
      }
    } catch (e, stackTrace) {
      print('❌ 测试连接时发生异常: $e');
      print('📍 异常堆栈: $stackTrace');
      if (mounted) {
        BlurSnackBar.show(context, '连接测试异常：$e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  Future<void> _saveConnection() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final connection = WebDAVConnection(
        name: _nameController.text.trim(),
        url: _urlController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
      );
      
      if (widget.editConnection != null) {
        // 如果是编辑模式，先删除旧连接
        await WebDAVService.instance.removeConnection(widget.editConnection!.name);
      }
      
      final success = await WebDAVService.instance.addConnection(connection);
      
      if (mounted) {
        if (success) {
          BlurSnackBar.show(context, '${widget.editConnection == null ? "添加" : "保存"}WebDAV连接成功！');
          Navigator.of(context).pop(true);
        } else {
          BlurSnackBar.show(context, '连接失败，请检查地址和认证信息');
        }
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '保存连接失败：$e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}