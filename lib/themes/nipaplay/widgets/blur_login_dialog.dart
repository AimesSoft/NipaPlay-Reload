import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';

/// 通用的毛玻璃登录对话框组件
/// 基于弹弹play登录对话框的样式设计
class BlurLoginDialog extends StatefulWidget {
  final String title;
  final List<LoginField> fields;
  final String loginButtonText;
  final Future<LoginResult> Function(Map<String, String> values) onLogin;
  final VoidCallback? onCancel;

  const BlurLoginDialog({
    super.key,
    required this.title,
    required this.fields,
    this.loginButtonText = '登录',
    required this.onLogin,
    this.onCancel,
  });

  @override
  State<BlurLoginDialog> createState() => _BlurLoginDialogState();

  /// 显示登录对话框
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required List<LoginField> fields,
    String loginButtonText = '登录',
    required Future<LoginResult> Function(Map<String, String> values) onLogin,
    VoidCallback? onCancel,
  }) {
    final enableAnimation = Provider.of<AppearanceSettingsProvider>(
      context,
      listen: false,
    ).enablePageAnimation;

    return NipaplayWindow.show<bool>(
      context: context,
      enableAnimation: enableAnimation,
      barrierDismissible: true,
      child: BlurLoginDialog(
        title: title,
        fields: fields,
        loginButtonText: loginButtonText,
        onLogin: onLogin,
        onCancel: onCancel,
      ),
    );
  }
}

class _BlurLoginDialogState extends State<BlurLoginDialog> {
  static const Color _accentColor = Color(0xFFFF2E55);

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 为每个字段创建控制器和焦点节点
    for (final field in widget.fields) {
      _controllers[field.key] = TextEditingController(text: field.initialValue);
      _focusNodes[field.key] = FocusNode();
    }
    
    // 在下一帧自动聚焦到第一个输入框（适用于Android TV）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.fields.isNotEmpty && mounted) {
        _focusNodes[widget.fields.first.key]?.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    // 释放所有控制器和焦点节点
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  Future<void> _handleLogin() async {
    // 收集所有字段的值
    final values = <String, String>{};
    for (final field in widget.fields) {
      final value = _controllers[field.key]?.text ?? '';
      if (field.required && value.trim().isEmpty) {
        BlurSnackBar.show(context, '请输入${field.label}');
        return;
      }
      values[field.key] = value.trim();
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await widget.onLogin(values);
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        if (result.success) {
          Navigator.of(context).pop(true);
          if (result.message != null) {
            BlurSnackBar.show(context, result.message!);
          }
        } else {
          BlurSnackBar.show(context, result.message ?? '${widget.loginButtonText}失败');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        BlurSnackBar.show(context, '${widget.loginButtonText}失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = globals.DialogSizes.getDialogWidth(screenSize.width);
    final dialogHeight = globals.DialogSizes.loginDialogHeight;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = colorScheme.onSurface.withOpacity(0.7);
    final hintColor = colorScheme.onSurface.withOpacity(0.5);
    final borderColor = colorScheme.onSurface.withOpacity(isDark ? 0.25 : 0.2);
    final surfaceColor =
        isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F2);
    final selectionTheme = TextSelectionThemeData(
      cursorColor: _accentColor,
      selectionColor: _accentColor.withOpacity(0.3),
      selectionHandleColor: _accentColor,
    );
    final buttonStyle = ButtonStyle(
      foregroundColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.disabled)) {
          return hintColor;
        }
        return _accentColor;
      }),
      overlayColor: MaterialStateProperty.all(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      padding: MaterialStateProperty.all(
        const EdgeInsets.symmetric(vertical: 12),
      ),
    );

    return NipaplayWindowScaffold(
      maxWidth: dialogWidth,
      maxHeightFactor: 0.9,
      onClose: () => Navigator.of(context).maybePop(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: surfaceColor,
          child: TextSelectionTheme(
            data: selectionTheme,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: keyboardHeight),
              child: SizedBox(
                height: dialogHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ) ??
                            TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                        textAlign: TextAlign.left,
                      ),
                      const SizedBox(height: 24),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ...widget.fields.asMap().entries.map((entry) {
                                final index = entry.key;
                                final field = entry.value;
                                final isLastField =
                                    index == widget.fields.length - 1;
                                final nextField =
                                    isLastField ? null : widget.fields[index + 1];

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: TextField(
                                    controller: _controllers[field.key],
                                    focusNode: _focusNodes[field.key],
                                    cursorColor: _accentColor,
                                    style: TextStyle(color: colorScheme.onSurface),
                                    obscureText: field.isPassword,
                                    textInputAction: isLastField
                                        ? TextInputAction.done
                                        : TextInputAction.next,
                                    onSubmitted: (value) {
                                      if (isLastField) {
                                        if (!_isLoading) _handleLogin();
                                      } else {
                                        if (nextField != null) {
                                          _focusNodes[nextField.key]
                                              ?.requestFocus();
                                        }
                                      }
                                    },
                                    decoration: InputDecoration(
                                      labelText: field.label,
                                      hintText: field.hint,
                                      labelStyle: TextStyle(color: labelColor),
                                      hintStyle: TextStyle(color: hintColor),
                                      enabledBorder: UnderlineInputBorder(
                                        borderSide: BorderSide(color: borderColor),
                                      ),
                                      focusedBorder: const UnderlineInputBorder(
                                        borderSide: BorderSide(color: _accentColor),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          style: buttonStyle,
                          child: _isLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      _accentColor,
                                    ),
                                  ),
                                )
                              : Text(
                                  widget.loginButtonText,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
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
  }
}

/// 登录字段配置
class LoginField {
  final String key;
  final String label;
  final String? hint;
  final bool isPassword;
  final bool required;
  final String? initialValue;

  const LoginField({
    required this.key,
    required this.label,
    this.hint,
    this.isPassword = false,
    this.required = true,
    this.initialValue,
  });
}

/// 登录结果
class LoginResult {
  final bool success;
  final String? message;

  const LoginResult({
    required this.success,
    this.message,
  });
} 
