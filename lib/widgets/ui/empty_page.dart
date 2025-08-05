import 'package:flutter/material.dart';

/// 空页面组件
/// 用于显示"这里什么都没有"的占位内容
class EmptyPage extends StatelessWidget {
  const EmptyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '这里什么都没有',
        style: TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }
}