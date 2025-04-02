import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/widgets/blur_snackbar.dart';

class GeneralPage extends StatelessWidget {
  const GeneralPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        ListTile(
          title: const Text(
            "清除图片缓存",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          subtitle: const Text(
            "清除所有缓存的图片文件",
            style: TextStyle(color: Colors.white70),
          ),
          trailing: const Icon(Ionicons.trash_outline, color: Colors.white),
          onTap: () async {
            // 显示确认对话框
            final bool? confirm = await BlurDialog.show<bool>(
              context: context,
              title: '确认清除缓存',
              content: '确定要清除所有缓存的图片文件吗？',
              actions: [
                TextButton(
                  child: const Text(
                    '取消',
                    style: TextStyle(color: Colors.white70),
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                TextButton(
                  child: const Text(
                    '确定',
                    style: TextStyle(color: Colors.white),
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            );

            if (confirm == true) {
              try {
                await ImageCacheManager.instance.clearCache();
                if (context.mounted) {
                  BlurSnackBar.show(context, '图片缓存已清除');
                }
              } catch (e) {
                if (context.mounted) {
                  BlurSnackBar.show(context, '清除缓存失败: $e');
                }
              }
            }
          },
        ),
      ],
    );
  }
} 