import 'package:flutter/material.dart' as material;
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/pages/anime_detail_page.dart';
import 'package:nipaplay/pages/fluent_anime_detail_page.dart';
import 'package:nipaplay/models/watch_history_model.dart';

/// 番剧详情页面的主题适配器
/// 根据当前UI主题自动选择Material或Fluent版本
class ThemedAnimeDetail {
  /// 显示番剧详情页面，自动适配当前UI主题
  static Future<WatchHistoryItem?> show(material.BuildContext context, int animeId) {
    final uiThemeProvider = Provider.of<UIThemeProvider>(context, listen: false);
    
    // 添加调试日志
    debugPrint('[ThemedAnimeDetail] 当前UI主题: ${uiThemeProvider.currentTheme}');
    debugPrint('[ThemedAnimeDetail] 是否为FluentUI: ${uiThemeProvider.isFluentUITheme}');
    
    if (uiThemeProvider.isFluentUITheme) {
      // 使用 Fluent UI 版本
      debugPrint('[ThemedAnimeDetail] 使用 Fluent UI 版本显示番剧详情页面');
      return _showFluentDialog(context, animeId);
    } else {
      // 使用 Material 版本（保持原有逻辑）
      debugPrint('[ThemedAnimeDetail] 使用 Material 版本显示番剧详情页面');
      return AnimeDetailPage.show(context, animeId);
    }
  }
  
  /// 显示 Fluent UI 版本的番剧详情对话框
  static Future<WatchHistoryItem?> _showFluentDialog(material.BuildContext context, int animeId) {
    return fluent.showDialog<WatchHistoryItem>(
      context: context,
      barrierDismissible: true,
      builder: (context) => FluentAnimeDetailPage(animeId: animeId),
    );
  }
}