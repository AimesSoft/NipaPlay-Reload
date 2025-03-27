// login_dialog.dart
import 'package:flutter/material.dart';
import 'package:nipaplay/utils/theme_colors.dart';
import 'package:nipaplay/utils/theme_utils.dart';
import 'package:nipaplay/widgets/rounded_button.dart';
import 'dart:ui';
import 'themed_text_field.dart'; // 导入新的 ThemedTextField

double fontSize = 16;
double verticalPadding = 5;
double horizontalPadding = 40;
double paddingHeight = 15;

class LoginDialog extends StatefulWidget {
  final String title;

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
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 300,
        padding: EdgeInsets.all(paddingHeight),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.transparent,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
            child: Container(
              padding: EdgeInsets.all(paddingHeight),
              // ignore: deprecated_member_use
              color: getBorderColor().withOpacity(0.7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    style: getBarTitleTextStyle(context),
                  ),
                  SizedBox(height: paddingHeight),
                  ThemedTextField(
                    controller: _usernameController,
                    label: '用户名',
                    obscureText: false,
                    onVisibilityChanged: null,
                  ),
                  SizedBox(height: paddingHeight),
                  ThemedTextField(
                    controller: _passwordController,
                    label: '密码',
                    obscureText: _obscureText,
                    onVisibilityChanged: () {
                      setState(() {
                        _obscureText = !_obscureText;
                      });
                    },
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

void showLoginDialog(BuildContext context, String title) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return LoginDialog(title: title);
    },
  );
}