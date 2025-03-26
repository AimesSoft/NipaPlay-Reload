import 'package:flutter/material.dart';
import 'package:nipaplay/utils/theme_colors.dart';
import 'package:nipaplay/widgets/rounded_button.dart';
import 'dart:ui';

double fontSize = 16;
double verticalPadding = 5;
double horizontalPadding = 40;
double paddingHeight = 15;

class LoginDialog extends StatefulWidget {
  final String title;  // 新增字段：用来接收标题文本

  const LoginDialog({super.key, required this.title});

  @override
  // ignore: library_private_types_in_public_api
  _LoginDialogState createState() => _LoginDialogState();
}

class _LoginDialogState extends State<LoginDialog> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent, // 设置背景为透明
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 300,
        padding: EdgeInsets.all(paddingHeight),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.transparent, // 设置模糊背景的颜色
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16), // 确保内容也被裁剪为圆角
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
            child: Container(
              padding: EdgeInsets.all(paddingHeight),
              // ignore: deprecated_member_use
              color: getBorderColor().withOpacity(0.7), // 确保内容背景是透明的，以便模糊效果可见
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 使用传入的 title 显示文本
                  Text(
                    widget.title,  // 使用传入的 title
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SizedBox(height: paddingHeight),
                  TextField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: '用户名',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      prefixIcon: const Icon(Icons.person),
                    ),
                  ),
                  SizedBox(height: paddingHeight),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscureText,
                    decoration: InputDecoration(
                      labelText: '密码',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureText ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureText = !_obscureText;
                          });
                        },
                      ),
                    ),
                  ),
                  SizedBox(height: paddingHeight),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      RoundedButton(
                        text: '登录',
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        fontSize: fontSize,
                        verticalPadding: verticalPadding,
                        horizontalPadding: horizontalPadding,
                        isSelected: false,
                      ),
                      RoundedButton(
                        text: '取消',
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        fontSize: fontSize,
                        verticalPadding: verticalPadding,
                        horizontalPadding: horizontalPadding,
                        isSelected: false,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

// 更新 showLoginDialog 方法，传入自定义的标题文本
void showLoginDialog(BuildContext context, String title) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return LoginDialog(title: title);  // 传入 title
    },
  );
}