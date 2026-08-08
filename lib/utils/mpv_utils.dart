
// lib/utils/mpv_utils.dart
// 解析和查找 mpv 相关工具函数

import 'dart:io';

import 'package:flutter/foundation.dart';


/// 查找当前系统中已安装的 mpv.
///
/// macOS 优先使用应用包, 随后检查 Homebrew、Intel Homebrew 和 MacPorts
/// 的常见可执行文件位置；Linux 会检查常见系统路径；Windows 会检查常见安装
/// 路径和 PATH。最后再搜索 PATH。
/// [candidatePaths] 仅用于测试或调用方需要限定搜索范围的场景。
Future<String?> detectInstalledMpv({
  Iterable<String>? candidatePaths,
}) async {
  if (kIsWeb || !(Platform.isMacOS || Platform.isLinux || Platform.isWindows)) return null;

  final candidates = <String>[];
  if (candidatePaths != null) {
    candidates.addAll(candidatePaths);
  } else if (Platform.isMacOS) {
    candidates.add('/Applications/mpv.app');
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      candidates.add('$home/Applications/mpv.app');
    }
    candidates.add('/opt/homebrew/bin/mpv');
    candidates.add('/usr/local/bin/mpv');
    candidates.add('/opt/local/bin/mpv');
  } else if (Platform.isLinux) {
    candidates.add('/usr/bin/mpv');
    candidates.add('/usr/local/bin/mpv');
    candidates.add('/snap/bin/mpv');
  } else if (Platform.isWindows) {
    // Windows 常见 mpv 安装位置
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.isNotEmpty) {
      candidates.add('$localAppData\\mpv\\mpv.exe');
      candidates.add('$localAppData\\mpv.net\\mpvnet.exe');
    }
    final programFiles = Platform.environment['ProgramFiles'];
    if (programFiles != null && programFiles.isNotEmpty) {
      candidates.add('$programFiles\\mpv\\mpv.exe');
      candidates.add('$programFiles\\mpv.net\\mpvnet.exe');
    }
    final programFilesX86 = Platform.environment['ProgramFiles(x86)'];
    if (programFilesX86 != null && programFilesX86.isNotEmpty) {
      candidates.add('$programFilesX86\\mpv\\mpv.exe');
      candidates.add('$programFilesX86\\mpv.net\\mpvnet.exe');
    }
    // scoop 安装路径
    final home = Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      candidates.add('$home\\scoop\\shims\\mpv.exe');
      candidates.add('$home\\scoop\\shims\\mpvnet.exe');
      candidates.add('$home\\scoop\\apps\\mpv\\current\\mpv.exe');
      candidates.add('$home\\scoop\\apps\\mpv.net\\current\\mpvnet.exe');
    }
  }

  if (candidatePaths == null) {
    final environmentPath = Platform.environment['PATH'];
    if (environmentPath != null && environmentPath.isNotEmpty) {
      final separator = Platform.isWindows ? ';' : ':';
      final executables = Platform.isWindows
          ? ['mpv.exe', 'mpvnet.exe']
          : ['mpv'];
      for (final directory in environmentPath.split(separator)) {
        if (directory.isEmpty) continue;
        for (final executable in executables) {
          candidates.add('$directory${Platform.pathSeparator}$executable');
        }
      }
    }
  }

  for (final candidate in candidates) {
    final path = candidate.trim();
    if (path.isEmpty) continue;
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.file ||
        type == FileSystemEntityType.link ||
        (Platform.isMacOS &&
            type == FileSystemEntityType.directory &&
            path.toLowerCase().endsWith('.app'))) {
      return path;
    }
  }
  return null;
}
