import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nipaplay/utils/network_checker.dart';

class NetworkCheckDialog extends StatefulWidget {
  const NetworkCheckDialog({super.key});

  @override
  State<NetworkCheckDialog> createState() => _NetworkCheckDialogState();
}

class _NetworkCheckDialogState extends State<NetworkCheckDialog> with SingleTickerProviderStateMixin {
  bool _isChecking = true;
  bool _isConnected = false;
  String _message = '正在检查网络连接...';
  Map<String, dynamic> _checkResults = {};
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  
  @override
  void initState() {
    super.initState();
    
    // 初始化动画控制器
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    
    // 创建渐变和缩放动画
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );
    
    // 开始动画
    _animationController.forward();
    
    // 执行网络检查
    _checkNetwork();
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  Future<void> _checkNetwork() async {
    try {
      // 检查百度连接
      final baiduResult = await NetworkChecker.checkConnection(
        url: 'https://www.baidu.com',
        timeout: 5,
      );
      
      // 延迟一下再检查其他站点，确保有足够的动画展示时间
      await Future.delayed(const Duration(milliseconds: 800));
      
      // 检查腾讯连接
      final tencentResult = await NetworkChecker.checkConnection(
        url: 'https://www.qq.com',
        timeout: 5,
      );
      
      bool isConnected = baiduResult['connected'] || tencentResult['connected'];
      
      // 更新状态前先执行淡出动画
      await _animationController.reverse();
      
      setState(() {
        _isChecking = false;
        _isConnected = isConnected;
        _message = isConnected 
            ? '网络连接正常' 
            : '网络连接异常，请检查网络设置';
        _checkResults = {
          'baidu': baiduResult,
          'tencent': tencentResult,
        };
      });
      
      // 显示结果时执行淡入动画
      await _animationController.forward();
      
      // 如果连接成功，3秒后自动关闭对话框
      if (isConnected) {
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      await _animationController.reverse();
      
      setState(() {
        _isChecking = false;
        _isConnected = false;
        _message = '网络检查过程中发生异常: $e';
      });
      
      await _animationController.forward();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
              ),
              elevation: 0,
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).dialogBackgroundColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isChecking) ...[
                      const SizedBox(
                        width: 60,
                        height: 60,
                        child: CircularProgressIndicator(),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _message,
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ] else ...[
                      Icon(
                        _isConnected ? Icons.check_circle : Icons.error,
                        color: _isConnected ? Colors.green : Colors.red,
                        size: 60,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _message,
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('确定'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
} 