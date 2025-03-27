// ignore_for_file: unnecessary_null_comparison

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show Uint8List, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:nipaplay/services/settings_service.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:nipaplay/utils/theme_provider.dart';
import 'package:nipaplay/utils/theme_utils.dart';
import 'package:nipaplay/widgets/rounded_button.dart';
import 'package:nipaplay/widgets/rounded_container.dart';
import 'package:nipaplay/widgets/warn_window.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

class BackgroundSettings extends StatefulWidget {
  final SettingsService settingsService;

  const BackgroundSettings({super.key, required this.settingsService});

  @override
  // ignore: library_private_types_in_public_api
  _BackgroundSettingsState createState() => _BackgroundSettingsState();
}

class _BackgroundSettingsState extends State<BackgroundSettings> {
  @override
  void initState() {
    super.initState();
  }

  Future<void> _saveSettings() async {
    await SettingsStorage.saveString('backImage', backImage);
    await SettingsStorage.saveInt('backImageNumber', backImageNumber);
  }

  /// 主入口：根据平台选择图片选择方式
  Future<void> _selectCustomBackgroundImage() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      // 移动端使用 image_picker
      await _selectFromGallery();
    } else {
      // Web 或 桌面使用 file_picker
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;

        if (file.bytes != null || file.path != null) {
          if (kIsWeb) {
            final fileSize = file.bytes?.length ?? 0;
            if (fileSize > 5 * 1024 * 1024) {
              showAlertDialog(
                context,
                '文件大小超过5MB，无法上传，请选择更小的文件。',
              );
              return;
            }
            final bytes = file.bytes;
            if (bytes != null) {
              final base64String = base64Encode(Uint8List.fromList(bytes));
              setState(() {
                backImageNumber = 2;
                backImage = 'data:image/jpeg;base64,$base64String';
                widget.settingsService.setBackgroundImage(backImage);
                _saveSettings();
                context.read<ThemeProvider>().updateDraw();
              });
            }
          } else {
            final filePath = file.path!;
            final appDirectory = await getApplicationDocumentsDirectory();
            final newFilePath = p.join(
                appDirectory.path, 'background.${filePath.split('.').last}');
            final newFile = await File(filePath).copy(newFilePath);
            setState(() {
              backImageNumber = 2;
              backImage = newFile.path;
              widget.settingsService.setBackgroundImage(newFile.path);
              _saveSettings();
              context.read<ThemeProvider>().updateDraw();
            });
          }
        }
      } else {
        if (kDebugMode) print('No file selected');
      }
    }
  }

  /// 移动端专用，从相册选择图片
  Future<void> _selectFromGallery() async {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile =
        await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final File file = File(pickedFile.path);
      final appDirectory = await getApplicationDocumentsDirectory();
      final newFilePath = p.join(
          appDirectory.path, 'background.${pickedFile.path.split('.').last}');
      final newFile = await file.copy(newFilePath);
      setState(() {
        backImageNumber = 2;
        backImage = newFile.path;
        widget.settingsService.setBackgroundImage(newFile.path);
        _saveSettings();
        context.read<ThemeProvider>().updateDraw();
      });
    } else {
      if (kDebugMode) print('No image selected from gallery');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "背景图片设置",
          style: getTitleTextStyle(context),
        ),
        RoundedContainer(
          child: Row(
            children: [
              RoundedButton(
                text: "看板娘",
                isSelected: backImageNumber == 0,
                onPressed: () {
                  setState(() {
                    backImageNumber = 0;
                    backImage = backGirl;
                    themeProvider.updateDraw();
                    _saveSettings();
                  });
                },
              ),
              const SizedBox(width: 10),
              RoundedButton(
                text: "关闭",
                isSelected: backImageNumber == 1,
                onPressed: () {
                  setState(() {
                    backImageNumber = 1;
                    backImage = backEmpty;
                    themeProvider.updateDraw();
                    _saveSettings();
                  });
                },
              ),
              const SizedBox(width: 10),
              RoundedButton(
                text: "自定义",
                isSelected: backImageNumber == 2,
                onPressed: _selectCustomBackgroundImage,
              ),
            ],
          ),
        ),
      ],
    );
  }
}