import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';

class UpdateService {
  static const String _repoUrl = 'https://api.github.com/repos/MCDFsteve/NipaPlay-Reload/releases/latest';
  
  static Future<UpdateInfo> checkForUpdates() async {
    try {
      debugPrint('UpdateService: 开始检查更新');
      // 获取当前版本
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      debugPrint('UpdateService: 当前版本 = $currentVersion');
      
      // 获取最新版本
      debugPrint('UpdateService: 正在请求GitHub API...');
      final response = await http.get(
        Uri.parse(_repoUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 10));
      
      debugPrint('UpdateService: API响应状态码 = ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final latestVersion = data['tag_name'] as String?;
        final releaseUrl = data['html_url'] as String?;
        final releaseName = data['name'] as String?;
        final releaseBody = data['body'] as String?;
        final publishedAt = data['published_at'] as String?;
        
        debugPrint('UpdateService: 最新版本标签 = $latestVersion');
        debugPrint('UpdateService: 发布页面链接 = $releaseUrl');
        
        if (latestVersion != null) {
          // 移除版本号前的 'v' 前缀（如果有的话）
          final cleanLatestVersion = latestVersion.startsWith('v') 
              ? latestVersion.substring(1) 
              : latestVersion;
          
          debugPrint('UpdateService: 清理后的最新版本 = $cleanLatestVersion');
          
          final hasUpdate = _compareVersions(currentVersion, cleanLatestVersion) < 0;
          debugPrint('UpdateService: 版本比较结果 = ${hasUpdate ? "有更新" : "无更新"}');
          
          return UpdateInfo(
            currentVersion: currentVersion,
            latestVersion: cleanLatestVersion,
            hasUpdate: hasUpdate,
            releaseUrl: releaseUrl ?? '',
            releaseName: releaseName ?? '',
            releaseNotes: releaseBody ?? '',
            publishedAt: publishedAt ?? '',
          );
        }
      }
      
      debugPrint('UpdateService: 无法获取版本信息，状态码=${response.statusCode}');
      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: currentVersion,
        hasUpdate: false,
        releaseUrl: '',
        releaseName: '',
        releaseNotes: '',
        publishedAt: '',
        error: '无法获取版本信息',
      );
    } catch (e) {
      debugPrint('UpdateService: 检查更新时发生异常: $e');
      final packageInfo = await PackageInfo.fromPlatform();
      return UpdateInfo(
        currentVersion: packageInfo.version,
        latestVersion: packageInfo.version,
        hasUpdate: false,
        releaseUrl: '',
        releaseName: '',
        releaseNotes: '',
        publishedAt: '',
        error: '检查更新失败: $e',
      );
    }
  }
  
  /// 比较版本号，返回 -1 表示 version1 < version2，0 表示相等，1 表示 version1 > version2
  static int _compareVersions(String version1, String version2) {
    debugPrint('UpdateService: 比较版本 $version1 vs $version2');
    final v1Parts = version1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final v2Parts = version2.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    
    debugPrint('UpdateService: 版本1解析结果: $v1Parts');
    debugPrint('UpdateService: 版本2解析结果: $v2Parts');
    
    // 补齐较短的版本号
    while (v1Parts.length < v2Parts.length) {
      v1Parts.add(0);
    }
    while (v2Parts.length < v1Parts.length) {
      v2Parts.add(0);
    }
    
    for (int i = 0; i < v1Parts.length; i++) {
      debugPrint('UpdateService: 比较第${i+1}位: ${v1Parts[i]} vs ${v2Parts[i]}');
      if (v1Parts[i] < v2Parts[i]) {
        debugPrint('UpdateService: version1 < version2');
        return -1;
      }
      if (v1Parts[i] > v2Parts[i]) {
        debugPrint('UpdateService: version1 > version2');
        return 1;
      }
    }
    
    debugPrint('UpdateService: 版本相等');
    return 0;
  }
}

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final bool hasUpdate;
  final String releaseUrl;
  final String releaseName;
  final String releaseNotes;
  final String publishedAt;
  final String? error;
  
  UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.hasUpdate,
    required this.releaseUrl,
    required this.releaseName,
    required this.releaseNotes,
    required this.publishedAt,
    this.error,
  });
}
