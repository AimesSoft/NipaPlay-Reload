import 'package:flutter/widgets.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/models/danmaku_auto_load_strategy.dart';
import 'package:nipaplay/services/danmaku_matching_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Non-modal feedback only when the user wants online Dandanplay danmaku.
class DandanplayLoginNotice {
  static Future<void> showIfNeeded(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final settings = resolveDanmakuAutoLoadSettings(
      persistedStrategy: prefs.getString(SettingsKeys.danmakuAutoLoadStrategy),
      persistedSkipMatching: prefs.getBool(SettingsKeys.skipDanmakuMatching),
      legacyAutoMatchOnPlay: prefs.getBool(SettingsKeys.autoMatchDanmakuOnPlay),
    );
    if (settings.skipMatching ||
        settings.strategy == DanmakuAutoLoadStrategy.local ||
        await DanmakuMatchingService.instance.canAccess()) {
      return;
    }
    if (!context.mounted) return;
    BlurSnackBar.show(
      context,
      '弹弹play在线弹幕需要登录账号，已跳过，不影响视频播放。',
      duration: const Duration(seconds: 4),
    );
  }
}
