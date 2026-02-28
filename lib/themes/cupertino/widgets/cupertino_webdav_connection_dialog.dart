import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/services/webdav_service.dart';

class CupertinoWebDAVConnectionDialog {
  static Future<bool?> show(
    BuildContext context, {
    WebDAVConnection? editConnection,
    Future<bool> Function(WebDAVConnection)? onSave,
    Future<bool> Function(WebDAVConnection)? onTest,
  }) {
    final title = editConnection == null ? '添加 WebDAV 服务器' : '编辑 WebDAV 服务器';
    return CupertinoBottomSheet.show<bool>(
      context: context,
      title: title,
      floatingTitle: true,
      child: _CupertinoWebDAVConnectionSheet(
        editConnection: editConnection,
        onSave: onSave,
        onTest: onTest,
      ),
    );
  }
}

class _CupertinoWebDAVConnectionSheet extends StatefulWidget {
  const _CupertinoWebDAVConnectionSheet({
    required this.editConnection,
    required this.onSave,
    required this.onTest,
  });

  final WebDAVConnection? editConnection;
  final Future<bool> Function(WebDAVConnection)? onSave;
  final Future<bool> Function(WebDAVConnection)? onTest;

  @override
  State<_CupertinoWebDAVConnectionSheet> createState() =>
      _CupertinoWebDAVConnectionSheetState();
}

class _CupertinoWebDAVConnectionSheetState
    extends State<_CupertinoWebDAVConnectionSheet> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isSaving = false;
  bool _isTesting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final edit = widget.editConnection;
    if (edit != null) {
      _nameController.text = edit.name;
      _urlController.text = edit.url;
      _usernameController.text = edit.username;
      _passwordController.text = edit.password;
    } else {
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

  String? _validateInputs() {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      return '请输入 WebDAV 地址';
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return '请输入有效的 URL（http/https）';
    }
    return null;
  }

  String _resolveConnectionName() {
    final input = _nameController.text.trim();
    if (input.isNotEmpty) return input;
    try {
      final uri = Uri.parse(_urlController.text.trim());
      final username = _usernameController.text.trim();
      if (uri.host.isNotEmpty) {
        return username.isNotEmpty ? '${uri.host}@$username' : uri.host;
      }
    } catch (_) {}
    return 'WebDAV 连接';
  }

  WebDAVConnection _buildConnection() {
    return WebDAVConnection(
      name: _resolveConnectionName(),
      url: _urlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
    );
  }

  Future<void> _handleTest() async {
    if (_isSaving || _isTesting) return;
    final validation = _validateInputs();
    if (validation != null) {
      setState(() {
        _errorMessage = validation;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _errorMessage = null;
    });

    final connection = _buildConnection();
    bool success = false;
    try {
      success = widget.onTest != null
          ? await widget.onTest!(connection)
          : await WebDAVService.instance.testConnection(connection);
    } catch (e) {
      success = false;
      if (mounted) {
        AdaptiveSnackBar.show(
          context,
          message: '测试失败：$e',
          type: AdaptiveSnackBarType.error,
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _errorMessage = success ? null : '连接测试失败，请检查地址和认证信息';
    });

    if (success) {
      AdaptiveSnackBar.show(
        context,
        message: '连接测试成功',
        type: AdaptiveSnackBarType.success,
      );
    } else {
      AdaptiveSnackBar.show(
        context,
        message: '连接测试失败',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Future<void> _handleSave() async {
    if (_isSaving || _isTesting) return;
    final validation = _validateInputs();
    if (validation != null) {
      setState(() {
        _errorMessage = validation;
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final connection = _buildConnection();
    bool success = false;
    try {
      if (widget.onSave != null) {
        success = await widget.onSave!(connection);
      } else {
        if (widget.editConnection != null) {
          await WebDAVService.instance
              .removeConnection(widget.editConnection!.name);
        }
        success = await WebDAVService.instance.addConnection(connection);
      }
    } catch (e) {
      success = false;
      if (mounted) {
        AdaptiveSnackBar.show(
          context,
          message: '保存失败：$e',
          type: AdaptiveSnackBarType.error,
        );
      }
    }

    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isSaving = false;
        _errorMessage = '保存失败，请检查地址和认证信息';
      });
    }
  }

  Widget _buildField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    String? placeholder,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    bool obscureText = false,
  }) {
    final Color fillColor =
        CupertinoDynamicColor.resolve(CupertinoColors.systemGrey5, context);
    final Color labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 6),
        CupertinoTextField(
          controller: controller,
          placeholder: placeholder,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          obscureText: obscureText,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final Color secondaryLabel =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final Color errorColor =
        CupertinoDynamicColor.resolve(CupertinoColors.systemRed, context);

    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) {
        return [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, topSpacing + 8, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '连接 WebDAV 服务器后可浏览目录并选择媒体文件夹。',
                    style: TextStyle(fontSize: 13, color: secondaryLabel),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      style: TextStyle(fontSize: 12, color: errorColor),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildField(
                    context,
                    label: '连接名称（可选）',
                    controller: _nameController,
                    placeholder: '留空自动生成',
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    context,
                    label: 'WebDAV 地址',
                    controller: _urlController,
                    placeholder: 'https://your-server.com/webdav',
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    context,
                    label: '用户名（可选）',
                    controller: _usernameController,
                    placeholder: '可留空',
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    context,
                    label: '密码（可选）',
                    controller: _passwordController,
                    placeholder: '可留空',
                    obscureText: true,
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      onPressed: _isSaving || _isTesting ? null : _handleTest,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _isTesting
                          ? const CupertinoActivityIndicator(radius: 8)
                          : const Text('测试连接'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton.filled(
                      onPressed: _isSaving || _isTesting ? null : _handleSave,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _isSaving
                          ? const CupertinoActivityIndicator(radius: 8)
                          : const Text('保存'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(height: 16 + bottomPadding),
          ),
        ];
      },
    );
  }
}
