import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/services/webdav_service.dart';

class WebDAVConnectionDialog {
  static Future<bool?> show(BuildContext context, {WebDAVConnection? editConnection}) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F2);
    return BlurDialog.show<bool>(
      context: context,
      title: editConnection == null ? '添加WebDAV服务器' : '编辑WebDAV服务器',
      backgroundColor: backgroundColor,
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
    } else {
      // 预填常见的局域网示例地址，减少从零输入的麻烦
      _urlController.text = 'http://192.168.1.1:5244/';
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
    const accentColor = Color(0xFFFF2E55);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = colorScheme.onSurface;
    final subTextColor = colorScheme.onSurface.withOpacity(0.7);
    final hintColor = colorScheme.onSurface.withOpacity(0.5);
    final borderColor = colorScheme.onSurface.withOpacity(isDark ? 0.25 : 0.2);
    final fillColor = isDark ? const Color(0xFF262626) : const Color(0xFFE8E8E8);
    final selectionTheme = TextSelectionThemeData(
      cursorColor: accentColor,
      selectionColor: accentColor.withOpacity(0.3),
      selectionHandleColor: accentColor,
    );
    final ButtonStyle plainButtonStyle = ButtonStyle(
      foregroundColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.disabled)) {
          return hintColor;
        }
        if (states.contains(MaterialState.hovered)) {
          return accentColor;
        }
        return textColor;
      }),
      overlayColor: MaterialStateProperty.all(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      padding: MaterialStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
    );
    final ButtonStyle accentButtonStyle = plainButtonStyle.copyWith(
      foregroundColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.disabled)) {
          return hintColor;
        }
        return accentColor;
      }),
    );

    InputDecoration buildDecoration({
      required String label,
      String? hint,
      Widget? suffixIcon,
    }) {
      return InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: subTextColor),
        hintText: hint,
        hintStyle: TextStyle(color: hintColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: accentColor),
        ),
        filled: true,
        fillColor: fillColor,
        suffixIcon: suffixIcon,
      );
    }

    return TextSelectionTheme(
      data: selectionTheme,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Text(
            'WebDAV服务器只会建立连接，不会自动扫描。\n您可以在连接后手动选择要扫描的文件夹。',
            style: TextStyle(
              color: subTextColor,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

            // 连接名称
            TextFormField(
              controller: _nameController,
              cursorColor: accentColor,
              style: TextStyle(color: textColor),
              decoration: buildDecoration(
                label: '连接名称（可选）',
                hint: '留空则自动生成',
              ),
              validator: (value) {
                // 连接名称现在是可选的，不需要验证
                return null;
              },
            ),

            const SizedBox(height: 16),

            // WebDAV URL
            TextFormField(
              controller: _urlController,
              cursorColor: accentColor,
              style: TextStyle(color: textColor),
              decoration: buildDecoration(
                label: 'WebDAV地址',
                hint: 'https://your-server.com/webdav',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入WebDAV地址';
                }
                if (!value.startsWith('http://') &&
                    !value.startsWith('https://')) {
                  return '请输入有效的URL地址';
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            // 用户名
            TextFormField(
              controller: _usernameController,
              cursorColor: accentColor,
              style: TextStyle(color: textColor),
              decoration: buildDecoration(
                label: '用户名',
                hint: '可选，如果服务器需要认证',
              ),
            ),

            const SizedBox(height: 16),

            // 密码
            TextFormField(
              controller: _passwordController,
              obscureText: !_passwordVisible,
              cursorColor: accentColor,
              style: TextStyle(color: textColor),
              decoration: buildDecoration(
                label: '密码',
                hint: '可选，如果服务器需要认证',
                suffixIcon: IconButton(
                  icon: Icon(
                    _passwordVisible ? Icons.visibility : Icons.visibility_off,
                    color: accentColor,
                  ),
                  onPressed: () {
                    setState(() {
                      _passwordVisible = !_passwordVisible;
                    });
                  },
                  style: IconButton.styleFrom(
                    overlayColor: Colors.transparent,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 按钮行
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () => Navigator.of(context).pop(false),
                  style: plainButtonStyle,
                  child: const Text('取消'),
                ),

                const SizedBox(width: 12),

                TextButton(
                  onPressed: _isLoading ? null : _testConnection,
                  style: accentButtonStyle,
                  child: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(accentColor),
                          ),
                        )
                      : const Text('测试连接'),
                ),

                const SizedBox(width: 12),

                TextButton(
                  onPressed: _isLoading ? null : _saveConnection,
                  style: accentButtonStyle,
                  child: Text(widget.editConnection == null ? '添加' : '保存'),
                ),
              ],
            ),
          ],
        ),
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
      
      String connectionName = _nameController.text.trim();
      
      // 如果没有提供连接名称，自动生成用于测试
      if (connectionName.isEmpty) {
        try {
          final uri = Uri.parse(_urlController.text.trim());
          final username = _usernameController.text.trim();
          
          if (username.isNotEmpty) {
            connectionName = '${uri.host}@$username';
          } else {
            connectionName = uri.host;
          }
        } catch (e) {
          connectionName = '测试连接';
        }
      }
      
      final connection = WebDAVConnection(
        name: connectionName,
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
      String connectionName = _nameController.text.trim();
      
      // 如果没有提供连接名称，自动生成
      if (connectionName.isEmpty) {
        final uri = Uri.parse(_urlController.text.trim());
        final username = _usernameController.text.trim();
        
        if (username.isNotEmpty) {
          connectionName = '${uri.host}@$username';
        } else {
          connectionName = uri.host;
        }
      }
      
      final connection = WebDAVConnection(
        name: connectionName,
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
