import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

class WindowsFileAssociationService {

  /// 检查NipaPlay是否已注册为视频文件的打开方式
  static Future<bool> isRegistered() async {
    if (!Platform.isWindows) return false;

    try {
      // 检查注册表中是否存在NipaPlay的注册信息
      final result = await Process.run('reg', [
        'query',
        'HKLM\\SOFTWARE\\RegisteredApplications',
        '/v',
        'NipaPlay'
      ]);
      
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('检查文件关联注册状态失败: $e');
      return false;
    }
  }

  /// 检查是否具有管理员权限
  static Future<bool> hasAdminPrivileges() async {
    if (!Platform.isWindows) return false;

    try {
      final result = await Process.run('net', ['session'], runInShell: true);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  /// 运行文件关联安装脚本
  static Future<bool> installFileAssociation() async {
    if (!Platform.isWindows) return false;

    try {
      // 获取当前执行文件的目录
      final exeDir = path.dirname(Platform.resolvedExecutable);
      final scriptPath = path.join(exeDir, 'install_file_association.bat');
      
      // 检查脚本是否存在
      if (!await File(scriptPath).exists()) {
        debugPrint('找不到安装脚本: $scriptPath');
        return false;
      }

      // 以管理员身份运行脚本
      final result = await Process.run('powershell', [
        '-Command',
        'Start-Process',
        '-FilePath',
        '"$scriptPath"',
        '-Verb',
        'RunAs',
        '-Wait'
      ], runInShell: true);

      return result.exitCode == 0;
    } catch (e) {
      debugPrint('运行文件关联安装脚本失败: $e');
      return false;
    }
  }

  /// 运行文件关联卸载脚本
  static Future<bool> uninstallFileAssociation() async {
    if (!Platform.isWindows) return false;

    try {
      // 获取当前执行文件的目录
      final exeDir = path.dirname(Platform.resolvedExecutable);
      final scriptPath = path.join(exeDir, 'uninstall_file_association.bat');
      
      // 检查脚本是否存在
      if (!await File(scriptPath).exists()) {
        debugPrint('找不到卸载脚本: $scriptPath');
        return false;
      }

      // 以管理员身份运行脚本
      final result = await Process.run('powershell', [
        '-Command',
        'Start-Process',
        '-FilePath',
        '"$scriptPath"',
        '-Verb',
        'RunAs',
        '-Wait'
      ], runInShell: true);

      return result.exitCode == 0;
    } catch (e) {
      debugPrint('运行文件关联卸载脚本失败: $e');
      return false;
    }
  }

  /// 打开Windows默认应用设置页面
  static Future<void> openDefaultAppsSettings() async {
    if (!Platform.isWindows) return;

    try {
      await Process.run('cmd', ['/c', 'start', 'ms-settings:defaultapps'], runInShell: true);
    } catch (e) {
      debugPrint('打开默认应用设置失败: $e');
    }
  }

  /// 检查是否需要提示用户配置文件关联
  static Future<bool> shouldPromptForFileAssociation() async {
    if (!Platform.isWindows) return false;

    // 检查是否已经注册
    if (await isRegistered()) {
      return false;
    }

    // 检查是否已经提示过用户（可以在SharedPreferences中存储）
    // 这里暂时总是返回true，后续可以根据需要优化
    return true;
  }

  /// 获取支持的视频文件扩展名列表
  static List<String> getSupportedExtensions() {
    return [
      '.mp4', '.mkv', '.avi', '.mov', '.webm', '.wmv', 
      '.m4v', '.3gp', '.flv', '.ts', '.m2ts'
    ];
  }

  /// 检查特定文件扩展名是否已关联到NipaPlay
  static Future<bool> isExtensionAssociated(String extension) async {
    if (!Platform.isWindows) return false;

    try {
      final result = await Process.run('reg', [
        'query',
        'HKLM\\SOFTWARE\\NipaPlay\\Capabilities\\FileAssociations',
        '/v',
        extension
      ]);
      
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }
} 