import 'package:flutter/material.dart';
import 'package:nipaplay/services/remote_control_auth_manager.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';

class RemoteControlAuthDialog {
  static Future<void> show(
    BuildContext context,
    ConnectionRequest request,
    Function(String, bool, bool) onAuthorize,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    bool trustDevice = false;

    return BlurDialog.show(
      context: context,
      title: '远程控制连接请求',
      contentWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '设备尝试连接并控制您的播放器',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoRow('设备名称', request.deviceName, colorScheme),
          _buildInfoRow('设备类型', request.deviceType, colorScheme),
          _buildInfoRow('IP地址', request.ipAddress, colorScheme),
          _buildInfoRow('请求时间', _formatTime(request.timestamp), colorScheme),
          const SizedBox(height: 16),
          Row(
            children: [
              Checkbox(
                value: trustDevice,
                onChanged: (value) {
                  trustDevice = value ?? false;
                },
                checkColor: colorScheme.surface,
                fillColor: MaterialStateProperty.resolveWith(
                  (states) => states.contains(MaterialState.selected)
                      ? colorScheme.primary
                      : null,
                ),
              ),
              Text(
                '信任此设备，下次自动授权',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        HoverScaleTextButton(
          text: '拒绝',
          idleColor: colorScheme.onSurface.withAlpha(180),
          onPressed: () {
            Navigator.of(context).pop();
            onAuthorize(request.id, false, false);
          },
        ),
        HoverScaleTextButton(
          text: '允许',
          idleColor: colorScheme.primary,
          onPressed: () {
            Navigator.of(context).pop();
            onAuthorize(request.id, true, trustDevice);
          },
        ),
      ],
    );
  }

  static Widget _buildInfoRow(String label, String value, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: colorScheme.onSurface.withAlpha(180),
              fontSize: 14,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inSeconds < 60) {
      return '刚刚';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}分钟前';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}小时前';
    } else {
      return '${time.month}月${time.day}日 ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
}
