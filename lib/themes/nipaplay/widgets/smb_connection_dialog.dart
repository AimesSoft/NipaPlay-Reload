import 'package:flutter/material.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';

class SMBConnectionDialog {
  static Future<bool?> show(
    BuildContext context, {
    SMBConnection? editConnection,
  }) {
    return BlurDialog.show<bool>(
      context: context,
      title: editConnection == null ? '添加SMB服务器' : '编辑SMB服务器',
      contentWidget: _SMBConnectionForm(editConnection: editConnection),
    );
  }
}

class _SMBConnectionForm extends StatefulWidget {
  final SMBConnection? editConnection;

  const _SMBConnectionForm({this.editConnection});

  @override
  State<_SMBConnectionForm> createState() => _SMBConnectionFormState();
}

class _SMBConnectionFormState extends State<_SMBConnectionForm> {
  static const Color _accentColor = Color(0xFFFF2E55);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _domainController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSubmitting = false;
  bool _passwordVisible = false;

  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;
  Color get _textColor => Theme.of(context).colorScheme.onSurface;
  Color get _subTextColor => _textColor.withOpacity(0.7);
  Color get _mutedTextColor => _textColor.withOpacity(0.5);
  Color get _borderColor => _textColor.withOpacity(_isDarkMode ? 0.25 : 0.2);
  Color get _fillColor =>
      _isDarkMode ? const Color(0xFF262626) : const Color(0xFFE8E8E8);

  TextSelectionThemeData get _selectionTheme => TextSelectionThemeData(
        cursorColor: _accentColor,
        selectionColor: _accentColor.withOpacity(0.3),
        selectionHandleColor: _accentColor,
      );

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
        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final connection = widget.editConnection;
    if (connection != null) {
      _nameController.text = connection.name;
      _hostController.text = connection.host;
      _portController.text = connection.port.toString();
      _domainController.text = connection.domain;
      _usernameController.text = connection.username;
      _passwordController.text = connection.password;
    } else {
      _portController.text = '445';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _domainController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor =
        _isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F2);

    return TextSelectionTheme(
      data: _selectionTheme,
      child: Container(
        color: surfaceColor,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            Text(
              'SMB服务器支持Samba/CIFS共享，可在局域网中直接浏览视频文件。\n'
              '建议优先使用IP地址并确保设备在同一网络内。',
              style: TextStyle(
                color: _subTextColor,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            _buildTextField(
              controller: _nameController,
              label: '连接名称（可选）',
              hint: '留空则使用主机名',
            ),
            const SizedBox(height: 14),
            _buildTextField(
              controller: _hostController,
              label: '主机/IP 地址',
              hint: '例如：192.168.1.10 或 nas.local（IPv6: [fe80::1]）',
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入主机或IP地址';
                }
                if (value.contains('://')) {
                  return '无需包含协议，请直接输入主机或IP';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            _buildTextField(
              controller: _portController,
              label: '端口',
              hint: '默认 445',
              keyboardType: TextInputType.number,
              validator: (value) {
                final trimmed = value?.trim() ?? '';
                if (trimmed.isEmpty) {
                  return null;
                }
                final port = int.tryParse(trimmed);
                if (port == null || port <= 0 || port > 65535) {
                  return '端口范围应为 1-65535';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            _buildTextField(
              controller: _domainController,
              label: '域（可选）',
              hint: '多数情况下可留空',
            ),
            const SizedBox(height: 14),
            _buildTextField(
              controller: _usernameController,
              label: '用户名（可选）',
              hint: '留空将使用匿名访问',
            ),
            const SizedBox(height: 14),
            _buildTextField(
              controller: _passwordController,
              label: '密码（可选）',
              hint: '留空将使用匿名访问',
              obscureText: !_passwordVisible,
              suffixIcon: IconButton(
                icon: Icon(
                  _passwordVisible ? Icons.visibility : Icons.visibility_off,
                  color: _accentColor,
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
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(false),
                  style: _plainButtonStyle(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _isSubmitting ? null : _handleSubmit,
                  style: _plainButtonStyle(baseColor: _accentColor),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(_accentColor),
                          ),
                        )
                      : const Text('保存'),
                ),
              ],
            ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      obscureText: obscureText,
      cursorColor: _accentColor,
      style: TextStyle(color: _textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: _subTextColor),
        hintText: hint,
        hintStyle: TextStyle(color: _mutedTextColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _accentColor),
        ),
        filled: true,
        fillColor: _fillColor,
        suffixIcon: suffixIcon,
      ),
    );
  }

  Future<void> _handleSubmit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final port =
        int.tryParse(_portController.text.trim()) ?? widget.editConnection?.port ?? 445;

    final connection = SMBConnection(
      name: _nameController.text.trim(),
      host: _hostController.text.trim(),
      port: port,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      domain: _domainController.text.trim(),
    );

    bool success = false;
    if (widget.editConnection == null) {
      success = await SMBService.instance.addConnection(connection);
    } else {
      success = await SMBService.instance.updateConnection(
        widget.editConnection!.name,
        connection,
      );
    }

    if (!mounted) return;
    if (success) {
      BlurSnackBar.show(
        context,
        widget.editConnection == null ? 'SMB连接添加成功！' : 'SMB连接已更新！',
      );
      Navigator.of(context).pop(true);
    } else {
      BlurSnackBar.show(context, '连接失败，请检查主机或凭据是否正确');
      setState(() {
        _isSubmitting = false;
      });
    }
  }
}
