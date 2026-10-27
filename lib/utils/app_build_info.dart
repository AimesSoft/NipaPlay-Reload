import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'app_runtime_info_stub.dart'
    if (dart.library.io) 'app_runtime_info_io.dart';

/// Public build/runtime facts only: no paths, accounts, endpoints or logs.
Future<Map<String, String>> loadAppBuildInfo() async {
  final package = await PackageInfo.fromPlatform();
  Map<String, Object?> source = const {};
  try {
    source = Map<String, Object?>.from(
        jsonDecode(await rootBundle.loadString('assets/build_info.json'))
            as Map);
  } catch (_) {
    // Older/development packages may not have generated build metadata.
  }
  final runtime = runtimeBuildInfo();
  return appBuildInfoFacts(source,
      nativeVersion: package.version,
      buildNumber: package.buildNumber,
      os: runtime['os']!,
      osVersion: runtime['osVersion']!,
      abi: runtime['abi']!,
      dartVersion: runtime['dart']!,
      mode: kReleaseMode ? 'Release' : (kProfileMode ? 'Profile' : 'Debug'));
}

@visibleForTesting
Map<String, String> appBuildInfoFacts(Map<String, Object?> source,
    {required String nativeVersion,
    required String buildNumber,
    required String os,
    required String osVersion,
    required String abi,
    required String dartVersion,
    required String mode}) {
  String? value(String key) => switch (source[key]) {
        final String text when text.trim().isNotEmpty => text.trim(),
        _ => null,
      };
  return {
    // Apple/Windows native version fields can turn alpha.1 into a numeric
    // suffix. Retain the source's SemVer separately from that native value.
    '应用版本': value('app_version') ?? nativeVersion,
    '构建号': buildNumber.isEmpty ? '未提供' : buildNumber,
    '安装包版本': nativeVersion,
    '构建模式': mode,
    '系统': '$os · $osVersion',
    '运行架构': abi,
    'Dart': dartVersion,
    'Flutter': value('flutter_version') ?? '未提供',
    '源码提交': value('git_commit') ?? '未提供',
    '源码状态': switch (source['git_dirty']) {
      true => '包含本地修改',
      false => '已提交',
      _ => '未提供',
    },
    '构建时间': value('build_time') ?? '未提供',
  };
}
