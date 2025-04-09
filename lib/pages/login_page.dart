import 'package:flutter/material.dart';
import '../services/dandanplay_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  // ... (existing code)
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // ... (existing code)

  Future<void> _handleLogin() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入用户名和密码')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await DandanplayService.login(
        _usernameController.text,
        _passwordController.text,
      );

      if (result['success'] == true) {
        // 保存登录信息
        await DandanplayService.saveLoginInfo(
          result['token'],
          _usernameController.text,
          result['screenName'] ?? _usernameController.text,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('登录成功')),
          );
          Navigator.of(context).pop();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? '登录失败')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('登录失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ... (existing code)
  }
} 