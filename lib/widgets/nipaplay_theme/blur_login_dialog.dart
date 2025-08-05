import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

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
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => BlurLoginDialog(
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
  final Map<String, TextEditingController> _controllers = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 为每个字段创建控制器
    for (final field in widget.fields) {
      _controllers[field.key] = TextEditingController(text: field.initialValue);
    }
  }

  @override
  void dispose() {
    // 释放所有控制器
    for (final controller in _controllers.values) {
      controller.dispose();
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
          BlurSnackBar.show(context, result.message ?? '登录失败');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        BlurSnackBar.show(context, '登录失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 使用预计算的对话框宽度和高度
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = globals.DialogSizes.getDialogWidth(screenSize.width);
    final dialogHeight = globals.DialogSizes.loginDialogHeight;
    
    // 获取键盘高度，用于动态调整底部间距
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: keyboardHeight),
          child: Container(
            width: dialogWidth,
            // 使用预计算的固定高度，确保对话框完整显示
            height: dialogHeight,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 5,
                  spreadRadius: 1,
                  offset: const Offset(1, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 固定标题区域
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                
                // 可滚动输入字段区域
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 输入字段
                        ...widget.fields.asMap().entries.map((entry) {
                          final index = entry.key;
                          final field = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: TextField(
                              controller: _controllers[field.key],
                              style: const TextStyle(color: Colors.white),
                              obscureText: field.isPassword,
                              textInputAction: index == widget.fields.length - 1 
                                  ? TextInputAction.done 
                                  : TextInputAction.next,
                              onSubmitted: (value) {
                                if (index == widget.fields.length - 1) {
                                  if (!_isLoading) _handleLogin();
                                } else {
                                  FocusScope.of(context).nextFocus();
                                }
                              },
                              decoration: InputDecoration(
                                labelText: field.label,
                                hintText: field.hint,
                                labelStyle: const TextStyle(color: Colors.white70),
                                hintStyle: const TextStyle(color: Colors.white54),
                                enabledBorder: const UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white30),
                                ),
                                focusedBorder: const UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white),
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
                
                // 固定登录按钮区域
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 0.5,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isLoading ? null : _handleLogin,
                      borderRadius: BorderRadius.circular(8),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Text(
                                    widget.loginButtonText,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                        ),
                      ),
                    ),
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