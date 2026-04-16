import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:path/path.dart' as p;
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/services/smb_proxy_service.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';

class CustomMediaInfoDialog {
  static const Color _accentColor = Color(0xFFFF2E55);
  static const double _rowIndexWidth = 32;

  static Future<Map<String, dynamic>?> show(
      BuildContext context, String folderPath,
      {String? initialVideoPath}) {
    return _showStep1(context, folderPath, initialVideoPath: initialVideoPath);
  }

  static Future<Map<String, dynamic>?> _showStep1(
      BuildContext context, String folderPath,
      {String? initialVideoPath, Map<String, dynamic>? step1Data}) async {
    final enableAnimation = Provider.of<AppearanceSettingsProvider>(
      context,
      listen: false,
    ).enablePageAnimation;

    final TextEditingController nameController =
        TextEditingController(text: step1Data?['name'] ?? '');
    final TextEditingController nameCnController =
        TextEditingController(text: step1Data?['nameCn'] ?? '');
    final TextEditingController summaryController =
        TextEditingController(text: step1Data?['summary'] ?? '');
    final TextEditingController airDateController =
        TextEditingController(text: step1Data?['airDate'] ?? '');
    final TextEditingController airWeekdayController =
        TextEditingController(text: step1Data?['airWeekday']?.toString() ?? '');
    final TextEditingController ratingController =
        TextEditingController(text: step1Data?['rating']?.toString() ?? '');
    final TextEditingController tagsController = TextEditingController(
        text: step1Data?['tags'] is List
            ? (step1Data?['tags'] as List).join(', ')
            : '');
    final TextEditingController metadataController = TextEditingController(
        text: step1Data?['metadata'] is List
            ? (step1Data?['metadata'] as List).join(', ')
            : '');
    final TextEditingController platformController =
        TextEditingController(text: step1Data?['platform'] ?? '');
    final TextEditingController totalEpisodesController = TextEditingController(
        text: step1Data?['totalEpisodes']?.toString() ?? '');
    final TextEditingController typeDescriptionController =
        TextEditingController(text: step1Data?['typeDescription'] ?? '');
    final TextEditingController bangumiUrlController =
        TextEditingController(text: step1Data?['bangumiUrl'] ?? '');
    final TextEditingController coverUrlController =
        TextEditingController(text: step1Data?['coverUrl'] ?? '');

    return NipaplayWindow.show<Map<String, dynamic>>(
      context: context,
      enableAnimation: enableAnimation,
      barrierDismissible: true,
      child: Builder(builder: (context) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final textColor = Theme.of(context).colorScheme.onSurface;
        final subTextColor = textColor.withOpacity(0.7);
        final mutedTextColor = textColor.withOpacity(0.5);
        final borderColor = textColor.withOpacity(isDarkMode ? 0.12 : 0.2);
        final surfaceColor =
            isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F2);
        final panelColor =
            isDarkMode ? const Color(0xFF262626) : const Color(0xFFE8E8E8);
        final panelAltColor =
            isDarkMode ? const Color(0xFF2B2B2B) : const Color(0xFFF7F7F7);

        final selectionTheme = TextSelectionThemeData(
          cursorColor: _accentColor,
          selectionColor: _accentColor.withOpacity(0.3),
          selectionHandleColor: _accentColor,
        );

        return TextSelectionTheme(
          data: selectionTheme,
          child: NipaplayWindowScaffold(
            maxWidth: MediaQuery.of(context).size.width >= 1200
                ? 980
                : globals.DialogSizes.getDialogWidth(
                    MediaQuery.of(context).size.width,
                  ),
            maxHeightFactor: (globals.isPhone &&
                    MediaQuery.of(context).size.shortestSide < 600)
                ? 0.9
                : 0.85,
            onClose: () => Navigator.of(context).maybePop(),
            backgroundColor: surfaceColor,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _accentColor.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.edit_note,
                          color: _accentColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '自定义媒体信息',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '填写媒体基本信息，包括名称、简介等',
                              style:
                                  TextStyle(color: subTextColor, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // 步骤指示器
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          color: _accentColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Text(
                            '1',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '基本信息',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 24),
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: mutedTextColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Text(
                            '2',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '剧集信息',
                        style: TextStyle(
                          color: mutedTextColor,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // 表单内容
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 名称（必填）
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '名称 *',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: nameController,
                              style: TextStyle(color: textColor),
                              decoration: InputDecoration(
                                hintText: '请输入媒体名称',
                                hintStyle: TextStyle(color: mutedTextColor),
                                filled: true,
                                fillColor: panelAltColor,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      const BorderSide(color: _accentColor),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 中文名称
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '中文名称',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: nameCnController,
                              style: TextStyle(color: textColor),
                              decoration: InputDecoration(
                                hintText: '请输入中文名称',
                                hintStyle: TextStyle(color: mutedTextColor),
                                filled: true,
                                fillColor: panelAltColor,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      const BorderSide(color: _accentColor),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 封面URL
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '封面URL',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: coverUrlController,
                              style: TextStyle(color: textColor),
                              decoration: InputDecoration(
                                hintText: '推荐使用bangumi、IMDb等来源',
                                hintStyle: TextStyle(color: mutedTextColor),
                                filled: true,
                                fillColor: panelAltColor,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      const BorderSide(color: _accentColor),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 简介
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '简介',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: summaryController,
                              style: TextStyle(color: textColor),
                              decoration: InputDecoration(
                                hintText: '请输入媒体简介',
                                hintStyle: TextStyle(color: mutedTextColor),
                                filled: true,
                                fillColor: panelAltColor,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      const BorderSide(color: _accentColor),
                                ),
                              ),
                              maxLines: 3,
                            ),
                          ],
                        ),
                      ),
                      // 首播日期
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '首播日期',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: airDateController,
                              style: TextStyle(color: textColor),
                              decoration: InputDecoration(
                                hintText: 'YYYY-MM-DD',
                                hintStyle: TextStyle(color: mutedTextColor),
                                filled: true,
                                fillColor: panelAltColor,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      const BorderSide(color: _accentColor),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 播出星期
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '播出星期',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: airWeekdayController,
                              style: TextStyle(color: textColor),
                              decoration: InputDecoration(
                                hintText: '0-6 (0=周日)',
                                hintStyle: TextStyle(color: mutedTextColor),
                                filled: true,
                                fillColor: panelAltColor,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      const BorderSide(color: _accentColor),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 评分
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '评分',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: ratingController,
                              style: TextStyle(color: textColor),
                              decoration: InputDecoration(
                                hintText: '0-10',
                                hintStyle: TextStyle(color: mutedTextColor),
                                filled: true,
                                fillColor: panelAltColor,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      const BorderSide(color: _accentColor),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 标签
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '标签',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: tagsController,
                              style: TextStyle(color: textColor),
                              decoration: InputDecoration(
                                hintText: '用逗号分隔',
                                hintStyle: TextStyle(color: mutedTextColor),
                                filled: true,
                                fillColor: panelAltColor,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      const BorderSide(color: _accentColor),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 元数据
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '元数据',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: metadataController,
                              style: TextStyle(color: textColor),
                              decoration: InputDecoration(
                                hintText: '用逗号分隔',
                                hintStyle: TextStyle(color: mutedTextColor),
                                filled: true,
                                fillColor: panelAltColor,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      const BorderSide(color: _accentColor),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 平台
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '平台',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: platformController,
                              style: TextStyle(color: textColor),
                              decoration: InputDecoration(
                                hintText: '如：B站,爱奇艺',
                                hintStyle: TextStyle(color: mutedTextColor),
                                filled: true,
                                fillColor: panelAltColor,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      const BorderSide(color: _accentColor),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 总集数
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '总集数',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: totalEpisodesController,
                              style: TextStyle(color: textColor),
                              decoration: InputDecoration(
                                hintText: '请输入总集数',
                                hintStyle: TextStyle(color: mutedTextColor),
                                filled: true,
                                fillColor: panelAltColor,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      const BorderSide(color: _accentColor),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 类型描述
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '类型描述',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: typeDescriptionController,
                              style: TextStyle(color: textColor),
                              decoration: InputDecoration(
                                hintText: '如：TV动画,剧场版',
                                hintStyle: TextStyle(color: mutedTextColor),
                                filled: true,
                                fillColor: panelAltColor,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      const BorderSide(color: _accentColor),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Bangumi URL
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bangumi URL',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: bangumiUrlController,
                              style: TextStyle(color: textColor),
                              decoration: InputDecoration(
                                hintText: '请输入番剧链接',
                                hintStyle: TextStyle(color: mutedTextColor),
                                filled: true,
                                fillColor: panelAltColor,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      const BorderSide(color: _accentColor),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // 按钮
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '填写完成后点击“下一步”进入剧集信息设置',
                          style: TextStyle(color: subTextColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ButtonStyle(
                          backgroundColor:
                              MaterialStateProperty.all(Colors.transparent),
                          foregroundColor: MaterialStateProperty.all(
                              Theme.of(context).colorScheme.onSurface),
                          overlayColor:
                              MaterialStateProperty.all(Colors.transparent),
                          splashFactory: NoSplash.splashFactory,
                          padding: MaterialStateProperty.all(
                            const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                          ),
                          minimumSize:
                              MaterialStateProperty.all(const Size(96, 44)),
                          elevation: MaterialStateProperty.all(0),
                          shadowColor:
                              MaterialStateProperty.all(Colors.transparent),
                          shape: MaterialStateProperty.all(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(
                                          Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? 0.12
                                              : 0.2)),
                            ),
                          ),
                        ),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () {
                          // 验证必填字段
                          if (nameController.text.isEmpty) {
                            BlurSnackBar.show(context, '名称为必填项');
                            return;
                          }

                          // 构建返回数据
                          final Map<String, dynamic> step1Data = {
                            'name': nameController.text,
                            'nameCn': nameCnController.text,
                            'summary': summaryController.text,
                            'airDate': airDateController.text,
                            'airWeekday': airWeekdayController.text.isNotEmpty
                                ? int.tryParse(airWeekdayController.text)
                                : null,
                            'rating': ratingController.text.isNotEmpty
                                ? double.tryParse(ratingController.text)
                                : null,
                            'tags': tagsController.text.isNotEmpty
                                ? tagsController.text
                                    .split(',')
                                    .map((e) => e.trim())
                                    .toList()
                                : null,
                            'metadata': metadataController.text.isNotEmpty
                                ? metadataController.text
                                    .split(',')
                                    .map((e) => e.trim())
                                    .toList()
                                : null,
                            'platform': platformController.text,
                            'totalEpisodes':
                                totalEpisodesController.text.isNotEmpty
                                    ? int.tryParse(totalEpisodesController.text)
                                    : null,
                            'typeDescription': typeDescriptionController.text,
                            'bangumiUrl': bangumiUrlController.text,
                            'coverUrl': coverUrlController.text,
                            'folderPath': folderPath,
                          };

                          // 关闭当前对话框并打开第二步
                          Navigator.of(context).pop();
                          _Step2Dialog.show(context, step1Data,
                              initialVideoPath: initialVideoPath);
                        },
                        style: ButtonStyle(
                          backgroundColor:
                              MaterialStateProperty.resolveWith((states) {
                            if (states.contains(MaterialState.disabled)) {
                              return _accentColor.withOpacity(0.5);
                            }
                            return _accentColor;
                          }),
                          foregroundColor:
                              MaterialStateProperty.all(Colors.white),
                          overlayColor:
                              MaterialStateProperty.all(Colors.transparent),
                          splashFactory: NoSplash.splashFactory,
                          padding: MaterialStateProperty.all(
                            const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                          ),
                          minimumSize:
                              MaterialStateProperty.all(const Size(96, 44)),
                          elevation: MaterialStateProperty.all(0),
                          shadowColor:
                              MaterialStateProperty.all(Colors.transparent),
                          shape: MaterialStateProperty.all(
                            RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        child: const Text('下一步'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  // 从文件名提取剧集号
  static String? _extractEpisodeNumber(String fileName) {
    // 匹配常见的剧集格式：[01], 01, E01, EP01, 第01话, 第1话, SP/SP1, OVA/OVA01, OAD/OAD01, Special, Lite等
    final patterns = [
      // 特殊格式：[SP01], SP01, OVA/OVA01, OAD/OAD01, Special, Lite
      RegExp(r'\[(SP\d*|OVA\d*|OAD\d*|Special|Lite)\]', caseSensitive: false),
      RegExp(r'[\s_\-\.](SP\d*|OVA\d*|OAD\d*|Special|Lite)[\s_\-\.\]]',
          caseSensitive: false),
      // 标准数字格式：[01], 01, 1
      RegExp(r'\[(\d{1,3})\]'),
      RegExp(r'[\s_\-\.](\d{1,3})[\s_\-\.\]]'),
      // 带前缀格式：E01, EP01, e01, ep01
      RegExp(r'[\s_\-\.]([Ee][Pp]?)(\d{1,3})[\s_\-\.\]]'),
      // 中文格式：第01话, 第1话
      RegExp(r'第(\d{1,3})话'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(fileName);
      if (match != null) {
        // 对于带前缀的格式，只返回数字部分
        if (match.groupCount > 1 && match.group(2) != null) {
          return match.group(2);
        }
        return match.group(1);
      }
    }
    return null;
  }

  // 生成排序键
  static int? _generateSortKey(String? episodeNumber) {
    if (episodeNumber == null) return null;

    // 处理特殊剧集号
    if (episodeNumber.toLowerCase().startsWith('sp')) {
      final numPart = episodeNumber.substring(2);
      final num = int.tryParse(numPart) ?? 0;
      return 1000 + num; // SP剧集排在普通剧集之后
    }
    if (episodeNumber.toLowerCase().startsWith('ova')) {
      final numPart = episodeNumber.substring(3);
      final num = int.tryParse(numPart) ?? 0;
      return 2000 + num; // OVA排在SP之后
    }
    if (episodeNumber.toLowerCase().startsWith('oad')) {
      final numPart = episodeNumber.substring(3);
      final num = int.tryParse(numPart) ?? 0;
      return 3000 + num; // OAD排在OVA之后
    }
    if (episodeNumber.toLowerCase() == 'lite') {
      return 4000; // Lite排在OAD之后
    }
    if (episodeNumber.toLowerCase() == 'special') {
      return 5000; // Special排在Lite之后
    }
    // 处理普通数字剧集号
    final num = int.tryParse(episodeNumber);
    return num;
  }

  // 保存自定义媒体信息到数据库
  static Future<void> _saveCustomMediaInfo(
      BuildContext context, Map<String, dynamic> data) async {
    try {
      // 生成唯一的animeId（使用时间戳的负数，确保与现有ID不冲突）
      final animeId = -DateTime.now().millisecondsSinceEpoch;

      // 获取WatchHistoryProvider
      final watchHistoryProvider =
          Provider.of<WatchHistoryProvider>(context, listen: false);

      // 创建EpisodeData列表
      final episodeList = <EpisodeData>[];

      // 遍历所有剧集
      final episodes = data['episodes'] as List<dynamic>;
      for (var i = 0; i < episodes.length; i++) {
        final episode = episodes[i] as Map<String, dynamic>;

        // 解析剧集号
        int? episodeId;
        if (episode['episodeNumber'] != null) {
          episodeId = int.tryParse(episode['episodeNumber'] as String);
        }
        if (episodeId == null) {
          // 如果无法解析剧集号，使用索引
          episodeId = i + 1;
        }

        // 创建WatchHistoryItem
        final historyItem = WatchHistoryItem(
          filePath: episode['path'] as String,
          animeName: data['name'] as String,
          episodeTitle: episode['title'] as String,
          episodeId: episodeId,
          animeId: animeId,
          watchProgress: 0.0,
          lastPosition: 0,
          duration: 0,
          lastWatchTime: DateTime.now(),
          thumbnailPath: data['coverUrl'] as String?,
          isFromScan: false,
        );

        // 保存到数据库
        await watchHistoryProvider.addOrUpdateHistory(historyItem);

        // 添加到EpisodeData列表
        episodeList.add(EpisodeData(
          id: episodeId,
          title: episode['title'] as String,
          airDate: DateTime.now().toIso8601String(),
        ));
      }

      // 创建BangumiAnime对象
      final bangumiAnime = BangumiAnime(
        id: animeId,
        name: data['name'] as String,
        nameCn: data['nameCn'] as String? ?? '',
        imageUrl: data['coverUrl'] as String? ?? '',
        summary: data['summary'] as String? ?? '',
        bangumiUrl: data['bangumiUrl'] as String? ?? '',
        airDate: data['airDate'] as String? ?? DateTime.now().toIso8601String(),
        airWeekday: data['airWeekday'] as int?,
        isOnAir: data['isOnAir'] as bool? ?? false,
        totalEpisodes: data['totalEpisodes'] as int?,
        rating: data['rating'] as double?,
        ratingDetails: {},
        tags: (data['tags'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        metadata: (data['metadata'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        typeDescription: data['typeDescription'] as String? ?? '自定义',
        isNSFW: data['isNSFW'] as bool? ?? false,
        platform: data['platform'] as String? ?? '',
        isFavorited: false,
        titles: [],
        searchKeyword: '',
        language: 'zh',
        episodeList: episodeList,
      );

      // 保存到BangumiService缓存
      final bangumiService = BangumiService.instance;
      await bangumiService.saveCustomAnimeDetail(animeId, bangumiAnime);

      // 显示成功消息
      BlurSnackBar.show(context, '自定义媒体信息已保存');
    } catch (e) {
      // 显示错误消息
      BlurSnackBar.show(context, '保存失败: ${e.toString()}');
      print('保存自定义媒体信息失败: $e');
    }
  }
}

class _Step2Dialog extends StatefulWidget {
  final Map<String, dynamic> step1Data;
  final String? initialVideoPath;
  final ValueNotifier<List<_VideoFileItem>> videoFilesNotifier =
      ValueNotifier([]);

  _Step2Dialog({required this.step1Data, this.initialVideoPath});

  static Future<Map<String, dynamic>?> show(
      BuildContext context, Map<String, dynamic> step1Data,
      {String? initialVideoPath}) async {
    final _Step2Dialog dialog =
        _Step2Dialog(step1Data: step1Data, initialVideoPath: initialVideoPath);
    final enableAnimation = Provider.of<AppearanceSettingsProvider>(
      context,
      listen: false,
    ).enablePageAnimation;

    final result = await NipaplayWindow.show<dynamic>(
      context: context,
      enableAnimation: enableAnimation,
      barrierDismissible: true,
      child: Builder(builder: (context) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final textColor = Theme.of(context).colorScheme.onSurface;
        final subTextColor = textColor.withOpacity(0.7);
        final surfaceColor =
            isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F2);

        return NipaplayWindowScaffold(
          maxWidth: MediaQuery.of(context).size.width >= 1200
              ? 980
              : globals.DialogSizes.getDialogWidth(
                  MediaQuery.of(context).size.width,
                ),
          maxHeightFactor: (globals.isPhone &&
                  MediaQuery.of(context).size.shortestSide < 600)
              ? 0.9
              : 0.85,
          onClose: () => Navigator.of(context).maybePop(),
          backgroundColor: surfaceColor,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: CustomMediaInfoDialog._accentColor
                            .withOpacity(0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.playlist_add_check,
                        color: CustomMediaInfoDialog._accentColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '自定义媒体信息',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '设置剧集信息，包括文件名和剧集名称',
                            style: TextStyle(color: subTextColor, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // 内容
                SizedBox(
                  height: 400,
                  child: dialog,
                ),
                const SizedBox(height: 24),
                // 按钮
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '确认剧集信息后点击“确定”保存',
                        style: TextStyle(color: subTextColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop('back'),
                      style: ButtonStyle(
                        backgroundColor:
                            MaterialStateProperty.all(Colors.transparent),
                        foregroundColor: MaterialStateProperty.all(
                            Theme.of(context).colorScheme.onSurface),
                        overlayColor:
                            MaterialStateProperty.all(Colors.transparent),
                        splashFactory: NoSplash.splashFactory,
                        padding: MaterialStateProperty.all(
                          const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ),
                        minimumSize:
                            MaterialStateProperty.all(const Size(96, 44)),
                        elevation: MaterialStateProperty.all(0),
                        shadowColor:
                            MaterialStateProperty.all(Colors.transparent),
                        shape: MaterialStateProperty.all(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? 0.12
                                        : 0.2)),
                          ),
                        ),
                      ),
                      child: const Text('上一步'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        // 构建完整的返回数据
                        final Map<String, dynamic> result = {
                          ...step1Data,
                          'episodes': dialog.videoFilesNotifier.value
                              .map((file) => {
                                    'path': file.path,
                                    'fileName': file.displayName,
                                    'episodeNumber': file.episodeNumber,
                                    'title':
                                        file.titleController.text.isNotEmpty
                                            ? file.titleController.text
                                            : (file.episodeNumber != null
                                                ? '第${file.episodeNumber}集'
                                                : file.displayName),
                                  })
                              .toList(),
                        };

                        // 保存到数据库
                        await CustomMediaInfoDialog._saveCustomMediaInfo(
                            context, result);

                        Navigator.of(context).pop(result);
                      },
                      style: ButtonStyle(
                        backgroundColor:
                            MaterialStateProperty.resolveWith((states) {
                          if (states.contains(MaterialState.disabled)) {
                            return CustomMediaInfoDialog._accentColor
                                .withOpacity(0.5);
                          }
                          return CustomMediaInfoDialog._accentColor;
                        }),
                        foregroundColor:
                            MaterialStateProperty.all(Colors.white),
                        overlayColor:
                            MaterialStateProperty.all(Colors.transparent),
                        splashFactory: NoSplash.splashFactory,
                        padding: MaterialStateProperty.all(
                          const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ),
                        minimumSize:
                            MaterialStateProperty.all(const Size(96, 44)),
                        elevation: MaterialStateProperty.all(0),
                        shadowColor:
                            MaterialStateProperty.all(Colors.transparent),
                        shape: MaterialStateProperty.all(
                          RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      child: const Text('确定'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
    );

    // 处理上一步逻辑
    if (result == 'back') {
      // 关闭当前对话框并重新打开第一步，传递回 step1Data
      return CustomMediaInfoDialog._showStep1(
          context, step1Data['folderPath'] as String,
          initialVideoPath: initialVideoPath, step1Data: step1Data);
    }

    return result as Map<String, dynamic>?;
  }

  @override
  State<_Step2Dialog> createState() => _Step2DialogState();
}

class _Step2DialogState extends State<_Step2Dialog> {
  List<_VideoFileItem> videoFiles = [];
  bool scanSubfolders = false;
  bool isScanning = false;

  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;
  Color get _textColor => Theme.of(context).colorScheme.onSurface;
  Color get _subTextColor => _textColor.withOpacity(0.7);
  Color get _mutedTextColor => _textColor.withOpacity(0.5);
  Color get _borderColor => _textColor.withOpacity(_isDarkMode ? 0.12 : 0.2);
  Color get _surfaceColor =>
      _isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F2);
  Color get _panelColor =>
      _isDarkMode ? const Color(0xFF262626) : const Color(0xFFE8E8E8);
  Color get _panelAltColor =>
      _isDarkMode ? const Color(0xFF2B2B2B) : const Color(0xFFF7F7F7);

  TextSelectionThemeData get _selectionTheme => TextSelectionThemeData(
        cursorColor: CustomMediaInfoDialog._accentColor,
        selectionColor: CustomMediaInfoDialog._accentColor.withOpacity(0.3),
        selectionHandleColor: CustomMediaInfoDialog._accentColor,
      );

  BoxDecoration _panelDecoration() {
    return BoxDecoration(
      color: _panelColor,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _borderColor),
    );
  }

  Widget _buildRowIndexText(int index) {
    final textColor = _mutedTextColor;
    return SizedBox(
      width: CustomMediaInfoDialog._rowIndexWidth,
      child: Text(
        '${index + 1}',
        textAlign: TextAlign.right,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildVideoFileListItem(_VideoFileItem item, int index,
      {required bool showBottomDivider}) {
    final textColor = _textColor;
    final backgroundColor = _panelAltColor;
    final borderColor = _borderColor;

    return Container(
      key: ValueKey(item.path),
      margin: EdgeInsets.only(bottom: showBottomDivider ? 8 : 0),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.displayName,
                    style: TextStyle(color: textColor, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildRowIndexText(index),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: item.titleController,
              style: TextStyle(color: textColor),
              decoration: InputDecoration(
                hintText: item.episodeNumber != null
                    ? '第${item.episodeNumber}集'
                    : '请输入剧集名称',
                hintStyle: TextStyle(color: _mutedTextColor),
                filled: true,
                fillColor: _panelColor,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: _borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: _borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                      color: CustomMediaInfoDialog._accentColor),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: _textColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBanner(String message, {bool isError = false}) {
    final backgroundColor = isError
        ? Colors.red.withOpacity(_isDarkMode ? 0.2 : 0.12)
        : CustomMediaInfoDialog._accentColor
            .withOpacity(_isDarkMode ? 0.18 : 0.12);
    final borderColor = isError
        ? Colors.redAccent.withOpacity(0.4)
        : CustomMediaInfoDialog._accentColor.withOpacity(0.35);
    final iconColor =
        isError ? Colors.redAccent : CustomMediaInfoDialog._accentColor;
    final textColor = isError ? Colors.redAccent : _textColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            size: 16,
            color: iconColor,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: textColor, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String title, {String? subtitle}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, color: _mutedTextColor, size: 32),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(color: _subTextColor, fontSize: 13)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: _mutedTextColor, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _initScan();
  }

  Future<void> _initScan() async {
    await scanVideoFiles();
  }

  // 递归扫描WebDAV文件夹
  Future<void> _scanWebDAVFolder(WebDAVConnection connection, String path,
      Set<String> videoExtensions) async {
    try {
      // 列出文件夹内容
      final files =
          await WebDAVService.instance.listDirectory(connection, path);

      // 处理文件列表
      for (final file in files) {
        if (file.isDirectory) {
          // 如果是文件夹且需要扫描子文件夹，则递归扫描
          if (scanSubfolders) {
            await _scanWebDAVFolder(connection, file.path, videoExtensions);
          }
        } else {
          // 如果是文件，检查是否是视频文件
          final extension = p.extension(file.name).toLowerCase();
          if (videoExtensions.contains(extension)) {
            final fileName = file.name;
            final episodeNumber =
                CustomMediaInfoDialog._extractEpisodeNumber(fileName);
            final sortKey =
                CustomMediaInfoDialog._generateSortKey(episodeNumber);
            final fileUrl =
                WebDAVService.instance.getFileUrl(connection, file.path);
            videoFiles.add(_VideoFileItem(
              path: fileUrl,
              displayName: fileName,
              episodeNumber: episodeNumber,
              sortKey: sortKey,
            ));
          }
        }
      }
    } catch (e) {
      print('扫描WebDAV文件夹出错: $e');
    }
  }

  // 递归扫描SMB文件夹
  Future<void> _scanSMBFolder(SMBConnection connection, String path,
      Set<String> videoExtensions) async {
    try {
      // 列出文件夹内容
      final files = await SMBService.instance.listDirectory(connection, path);

      // 处理文件列表
      for (final file in files) {
        if (file.isDirectory) {
          // 如果是文件夹且需要扫描子文件夹，则递归扫描
          if (scanSubfolders) {
            await _scanSMBFolder(connection, file.path, videoExtensions);
          }
        } else {
          // 如果是文件，检查是否是视频文件
          final extension = p.extension(file.name).toLowerCase();
          if (videoExtensions.contains(extension)) {
            final fileName = file.name;
            final episodeNumber =
                CustomMediaInfoDialog._extractEpisodeNumber(fileName);
            final sortKey =
                CustomMediaInfoDialog._generateSortKey(episodeNumber);
            final fileUrl =
                SMBProxyService.instance.buildStreamUrl(connection, file.path);
            videoFiles.add(_VideoFileItem(
              path: fileUrl,
              displayName: fileName,
              episodeNumber: episodeNumber,
              sortKey: sortKey,
            ));
          }
        }
      }
    } catch (e) {
      print('扫描SMB文件夹出错: $e');
    }
  }

  // 扫描视频文件的方法
  Future<void> scanVideoFiles() async {
    setState(() {
      isScanning = true;
      videoFiles.clear();
    });

    // 定义视频文件扩展名
    const videoExtensions = {
      '.mp4',
      '.mkv',
      '.avi',
      '.wmv',
      '.mov',
      '.flv',
      '.webm',
      '.m4v',
      '.ts',
      '.m3u8'
    };

    final folderPath = widget.step1Data['folderPath'] as String;

    try {
      // 如果提供了initialVideoPath，只处理这个视频文件
      if (widget.initialVideoPath != null) {
        final filePath = widget.initialVideoPath!;
        String fileName;

        // 对于WebDAV和SMB路径，从URL中提取文件名
        if (filePath.startsWith('webdav://') || filePath.startsWith('smb://')) {
          // 尝试从URL路径部分提取文件名
          final uri = Uri.parse(filePath);
          final path = uri.path;
          fileName = p.basename(path);

          // 如果文件名是空的，尝试解码整个URL的最后一部分
          if (fileName.isEmpty) {
            final parts = filePath.split('/');
            if (parts.isNotEmpty) {
              fileName = parts.last;
            }
          }
        } else {
          // 本地路径使用p.basename
          fileName = p.basename(filePath);
        }

        final extension = p.extension(filePath).toLowerCase();
        if (videoExtensions.contains(extension)) {
          final episodeNumber =
              CustomMediaInfoDialog._extractEpisodeNumber(fileName);
          final sortKey = CustomMediaInfoDialog._generateSortKey(episodeNumber);
          videoFiles.add(_VideoFileItem(
            path: filePath,
            displayName: fileName,
            episodeNumber: episodeNumber,
            sortKey: sortKey,
          ));
        }
      }
      // 否则扫描整个文件夹
      else {
        // 检查是否是WebDAV路径
        if (folderPath.startsWith('webdav://')) {
          // 解析WebDAV路径：webdav://connectionName/path
          final pathWithoutScheme = folderPath.substring(9);
          final firstSlashIndex = pathWithoutScheme.indexOf('/');
          if (firstSlashIndex != -1) {
            final connectionName =
                pathWithoutScheme.substring(0, firstSlashIndex);
            final path = pathWithoutScheme.substring(firstSlashIndex);

            // 获取WebDAV连接
            final connection = WebDAVService.instance.connections.firstWhere(
              (c) => c.name == connectionName,
            );

            // 递归扫描文件夹
            await _scanWebDAVFolder(connection, path, videoExtensions);
          }
        }
        // 检查是否是SMB路径
        else if (folderPath.startsWith('smb://')) {
          // 解析SMB路径：smb://connectionName/path
          final pathWithoutScheme = folderPath.substring(6);
          final firstSlashIndex = pathWithoutScheme.indexOf('/');
          if (firstSlashIndex != -1) {
            final connectionName =
                pathWithoutScheme.substring(0, firstSlashIndex);
            final path = pathWithoutScheme.substring(firstSlashIndex);

            // 获取SMB连接
            final connection = SMBService.instance.connections.firstWhere(
              (c) => c.name == connectionName,
            );

            // 递归扫描文件夹
            await _scanSMBFolder(connection, path, videoExtensions);
          }
        }
        // 本地路径
        else {
          // 扫描文件夹
          void _scanDirectory(io.Directory directory) {
            try {
              final entities = directory.listSync(recursive: scanSubfolders);
              for (final entity in entities) {
                if (entity is io.File) {
                  final extension = p.extension(entity.path).toLowerCase();
                  if (videoExtensions.contains(extension)) {
                    final fileName = p.basename(entity.path);
                    final episodeNumber =
                        CustomMediaInfoDialog._extractEpisodeNumber(fileName);
                    final sortKey =
                        CustomMediaInfoDialog._generateSortKey(episodeNumber);
                    videoFiles.add(_VideoFileItem(
                      path: entity.path,
                      displayName: fileName,
                      episodeNumber: episodeNumber,
                      sortKey: sortKey,
                    ));
                  }
                }
              }
            } catch (e) {
              print('扫描文件夹出错: $e');
            }
          }

          _scanDirectory(io.Directory(folderPath));
        }

        // 按剧集号排序
        videoFiles.sort((a, b) {
          if (a.sortKey != null && b.sortKey != null) {
            return a.sortKey!.compareTo(b.sortKey!);
          }
          if (a.sortKey != null) return -1;
          if (b.sortKey != null) return 1;
          return a.displayName.compareTo(b.displayName);
        });
      }
    } catch (e) {
      print('扫描文件夹出错: $e');
    } finally {
      // 更新 notifier
      widget.videoFilesNotifier.value = List.from(videoFiles);

      setState(() {
        isScanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextSelectionTheme(
      data: _selectionTheme,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 步骤指示器
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: _mutedTextColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text(
                      '1',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '基本信息',
                  style: TextStyle(
                    color: _mutedTextColor,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 24),
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: CustomMediaInfoDialog._accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text(
                      '2',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '剧集信息',
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // 扫描选项
            Row(
              children: [
                Checkbox(
                  value: scanSubfolders,
                  onChanged: (value) async {
                    setState(() {
                      scanSubfolders = value ?? false;
                    });
                    await scanVideoFiles();
                  },
                  checkColor: Colors.white,
                  activeColor: CustomMediaInfoDialog._accentColor,
                  side: BorderSide(color: _borderColor, width: 1),
                ),
                Text(
                  '扫描子文件夹',
                  style: TextStyle(color: _textColor),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 视频文件列表
            _buildSectionTitle('视频文件列表'),
            const SizedBox(height: 8),
            if (isScanning)
              Container(
                decoration: _panelDecoration(),
                child: const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40.0),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          CustomMediaInfoDialog._accentColor),
                    ),
                  ),
                ),
              )
            else if (videoFiles.isEmpty)
              Container(
                decoration: _panelDecoration(),
                child: _buildEmptyState('未找到视频文件'),
              )
            else
              Container(
                decoration: _panelDecoration(),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    primary: false,
                    shrinkWrap: true,
                    itemCount: videoFiles.length,
                    itemBuilder: (context, index) {
                      final item = videoFiles[index];
                      final showBottomDivider = index != videoFiles.length - 1;
                      return _buildVideoFileListItem(
                        item,
                        index,
                        showBottomDivider: showBottomDivider,
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VideoFileItem {
  final String path;
  final String displayName;
  final String? episodeNumber;
  final int? sortKey;
  final TextEditingController titleController;

  _VideoFileItem({
    required this.path,
    required this.displayName,
    required this.episodeNumber,
    required this.sortKey,
  }) : titleController = TextEditingController();
}
