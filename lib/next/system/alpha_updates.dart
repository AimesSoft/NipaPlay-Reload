import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';
import 'package:nipaplay/services/update_service.dart' show UpdateInfo;
import 'package:nipaplay/services/web_remote_access_service.dart';
import 'package:nipaplay/utils/app_build_info.dart';

/// Next follows published 2.x+ releases, including alpha/beta. Classic keeps
/// its existing stable-only update service.
Future<UpdateInfo> checkNextUpdate() async {
  final build = await loadAppBuildInfo();
  final current = build['应用版本']!;
  try {
    final response = await http.get(
      WebRemoteAccessService.proxyUri(Uri.parse(
          'https://api.github.com/repos/AimesSoft/NipaPlay-Reload/releases?per_page=100')),
      headers: {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw const FormatException('Release lookup failed');
    }
    final release = selectNextRelease(jsonDecode(response.body) as List);
    if (release == null) {
      return UpdateInfo(
          currentVersion: current,
          latestVersion: current,
          hasUpdate: false,
          releaseUrl: '',
          releaseName: '',
          releaseNotes: '',
          publishedAt: '',
          error: '还没有公开的 Next 版本');
    }
    final latest =
        (release['tag_name'] as String).replaceFirst(RegExp(r'^v'), '');
    return UpdateInfo(
      currentVersion: current,
      latestVersion: latest,
      hasUpdate:
          releaseVersion(latest)!.compareTo(releaseVersion(current)!) > 0,
      releaseUrl: release['html_url'] as String? ?? '',
      releaseName: release['name'] as String? ?? '',
      releaseNotes: release['body'] as String? ?? '',
      publishedAt: release['published_at'] as String? ?? '',
    );
  } catch (_) {
    return UpdateInfo(
        currentVersion: current,
        latestVersion: current,
        hasUpdate: false,
        releaseUrl: '',
        releaseName: '',
        releaseNotes: '',
        publishedAt: '',
        error: '没能读取 Next 版本列表，请稍后重试');
  }
}

Version? releaseVersion(String value) {
  try {
    return Version.parse(
        value.replaceFirst(RegExp(r'^v'), '').split('+').first);
  } on FormatException {
    return null;
  }
}

Map<String, Object?>? selectNextRelease(List<Object?> releases) {
  Map<String, Object?>? selected;
  Version? highest;
  for (final raw in releases) {
    if (raw is! Map || raw['draft'] == true || raw['tag_name'] is! String) {
      continue;
    }
    final version = releaseVersion(raw['tag_name'] as String);
    if (version == null || version.major < 2) continue;
    if (highest == null || version.compareTo(highest) > 0) {
      highest = version;
      selected = Map<String, Object?>.from(raw);
    }
  }
  return selected;
}
