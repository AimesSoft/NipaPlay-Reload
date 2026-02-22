import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';

class StartupNotificationController {
  static final math.Random _random = math.Random();
  static bool _hasShown = false;
  static bool _isScheduled = false;

  static const String _donateMessage = '如果觉得播放器好用，欢迎试试赞助～';

  static const List<String> _genericMessages = [
    '欢迎回来，祝你观影愉快！',
    '嗨，准备好追番了吗？',
    '今天也要好好放松一下～',
    'NipaPlay 已就绪，开始播放吧。',
    '愿你有个愉快的观影时光。',
    '欢迎使用 NipaPlay！',
    '从一部好番开始今天吧。',
    '追番时间到～',
    '新的播放旅程开始啦！',
  ];

  static const List<String> _timeGreetingTemplates = [
    '{greet}，欢迎回来！',
    '{greet}，准备好追番了吗？',
    '{greet}，祝你观影愉快！',
    '{greet}，NipaPlay 已就绪。',
  ];

  static String _resolveGreeting(DateTime now) {
    final hour = now.hour;
    if (hour >= 5 && hour < 11) {
      return '早上好';
    }
    if (hour >= 11 && hour < 14) {
      return '中午好';
    }
    if (hour >= 14 && hour < 18) {
      return '下午好';
    }
    if (hour >= 18 && hour < 23) {
      return '晚上好';
    }
    return '夜深了';
  }

  static void schedule(
    BuildContext context, {
    Duration delay = const Duration(milliseconds: 500),
    bool Function()? isMounted,
  }) {
    if (_hasShown || _isScheduled) return;
    _isScheduled = true;
    Future.delayed(delay, () async {
      _isScheduled = false;
      if (_hasShown) return;
      if (isMounted != null && !isMounted()) return;
      await _showRandomMessage(context, isMounted: isMounted);
    });
  }

  static Future<void> _showRandomMessage(
    BuildContext context, {
    bool Function()? isMounted,
  }) async {
    if (isMounted != null && !isMounted()) return;
    final now = DateTime.now();
    const donateEligible = true;
    final options = <_MessagePayload>[
      for (final message in _genericMessages) _MessagePayload(message),
      for (final template in _timeGreetingTemplates)
        _MessagePayload(template, usesGreeting: true),
      if (donateEligible) const _MessagePayload(_donateMessage, isDonate: true),
    ];
    final payload = options[_random.nextInt(options.length)];
    final content = payload.usesGreeting
        ? payload.content.replaceFirst('{greet}', _resolveGreeting(now))
        : payload.content;
    if (payload.isDonate) {
      BlurSnackBar.show(
        context,
        content,
        actionText: '点此赞助',
        onAction: () {
          if (isMounted != null && !isMounted()) return;
          _showAppreciationQR(context);
        },
      );
    } else {
      BlurSnackBar.show(context, content);
    }
    _hasShown = true;
  }

  static void _showAppreciationQR(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    BlurDialog.show(
      context: context,
      title: '赞赏码',
      contentWidget: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 300,
          maxHeight: 400,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            'others/赞赏码.jpg',
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.image_outlined,
                      size: 60,
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '赞赏码图片加载失败',
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            '关闭',
            style: TextStyle(color: colorScheme.onSurface),
          ),
        ),
      ],
    );
  }
}

class _MessagePayload {
  final String content;
  final bool isDonate;
  final bool usesGreeting;

  const _MessagePayload(
    this.content, {
    this.isDonate = false,
    this.usesGreeting = false,
  });
}
