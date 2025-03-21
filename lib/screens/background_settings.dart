// ignore_for_file: unnecessary_null_comparison

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/services/settings_service.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:nipaplay/utils/theme_provider.dart';
import 'package:nipaplay/utils/theme_utils.dart';
import 'package:nipaplay/widgets/rounded_button.dart';
import 'package:nipaplay/widgets/rounded_container.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:uuid/uuid.dart';
// 条件导入：仅在 Web 平台上导入 dart:html
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html show File, FileReader;

// 在其他平台上，使用空实现
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
    _loadSettings(); // 加载保存的设置
  }

  // 从存储中加载设置
  Future<void> _loadSettings() async {
    // 加载 backImage 并检查是否为空或 null
    String? loadedBackImage = await SettingsStorage.loadString('backImage');
    if (loadedBackImage != null && loadedBackImage.isNotEmpty) {
      backImage = loadedBackImage;
    }

    // 加载 backImageNumber 并检查是否为空或 null
    int? loadedBackImageNumber = await SettingsStorage.loadInt('backImageNumber');
    if (loadedBackImageNumber != null) {
      backImageNumber = loadedBackImageNumber;
    }
    if (mounted) {
      // 添加 mounted 检查
      setState(() {}); // 确保 UI 更新
    }
  }

  // 保存设置
  Future<void> _saveSettings() async {
    await SettingsStorage.saveString('backImage', backImage);
    await SettingsStorage.saveInt('backImageNumber', backImageNumber);
  }

  Future<void> _selectCustomBackgroundImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'png', 'webp'],
    );

    if (result != null && result.files.isNotEmpty) {
      final filePath = result.files.single.path;
      if (filePath != null) {
        try {
          if (kIsWeb) {
            print(
                'BackgroundSettings _selectCustomBackgroundImage Web platform detected');
            // Web 平台：使用 FileReader 读取文件内容
            final file = html.File(result.files.single.bytes as List<Object>, result.files.single.name);
            final reader = html.FileReader();

            reader.readAsArrayBuffer(file);

            reader.onLoad.listen((event) {
              final Uint8List fileBytes = reader.result as Uint8List;
              final base64Image = base64Encode(fileBytes);
              final uuid = const Uuid().v4(); // 生成 UUID

              print(
                  'BackgroundSettings _selectCustomBackgroundImage base64Image generated, uuid: $uuid');
              // 将 Base64 数据和 UUID 发送到服务器
              http.post(
                Uri.parse('http://nipaplay.aimes-soft.com/upload_image.php'), // 使用您的服务器 URL
                body: {'image': base64Image, 'uuid': uuid},
              ).then((response) {
                print(
                    'BackgroundSettings _selectCustomBackgroundImage server response: ${response.statusCode}');
                if (response.statusCode == 200) {
                  setState(() {
                    backImageNumber = 2;
                    backImage = 'http://nipaplay.aimes-soft.com/images/$uuid'; // 设置为服务器图像 URL
                    widget.settingsService.setBackgroundImage(backImage); // 设置背景图路径
                    _saveSettings(); // 保存设置
                    context.read<ThemeProvider>().updateDraw(); // 更新主题或重新绘制UI
                    print(
                        'BackgroundSettings _selectCustomBackgroundImage setState called, backImage: $backImage');
                  });
                } else {
                  // 处理上传错误
                  if (kDebugMode) {
                    print(
                        'BackgroundSettings _selectCustomBackgroundImage Error uploading image: ${response.statusCode}');
                  }
                }
              }).catchError((error, stackTrace) {
                if(kDebugMode){
                  print("BackgroundSettings _selectCustomBackgroundImage http error: $error");
                  print("BackgroundSettings _selectCustomBackgroundImage StackTrace: $stackTrace");
                }
              });
            });

            reader.onError.listen((event) {
              if (kDebugMode) {
                print('BackgroundSettings _selectCustomBackgroundImage FileReader error: $event');
              }
            });
          }  else {
            // 原生平台：复制文件到应用目录
            final appDirectory = await getApplicationDocumentsDirectory();
            final newFilePath =
                p.join(appDirectory.path, 'background.${filePath.split('.').last}'); // 构造新文件路径

            // 将用户选择的文件复制到应用自己的目录
            final file = File(filePath);
            final newFile = await file.copy(newFilePath);

            // 执行剩下的操作
            setState(() {
              backImageNumber = 2;
              backImage = newFile.path; // 设置为复制后的文件路径
              widget.settingsService.setBackgroundImage(newFile.path); // 设置背景图路径
              _saveSettings(); // 保存设置
              context.read<ThemeProvider>().updateDraw(); // 更新主题或重新绘制UI
            });
          }
        } catch (e) {
          // 处理文件复制过程中可能出现的错误
          if (kDebugMode) {
            print('Error processing file: $e');
          }
        }
      }
    } else {
      // 用户没有选择文件或取消选择
      if (kDebugMode) {
        print('No file selected');
      }
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
          // 使用 RoundedContainer 包裹按钮行
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
                onPressed: () {
                  _selectCustomBackgroundImage();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}