import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import 'package:nipaplay/plugins/models/plugin_external_script.dart';
import 'package:nipaplay/plugins/models/plugin_danmaku_renderer.dart';
import 'package:nipaplay/utils/storage_service.dart';

class PluginExternalScriptCache {
  PluginExternalScriptCache._();

  static const int _rendererPageTemplateVersion = 2;
  static const int _maxScriptBytes = 32 * 1024 * 1024;
  static const Duration _downloadTimeout = Duration(seconds: 30);
  static final Map<String, Future<String>> _inFlight =
      <String, Future<String>>{};

  static Future<List<String>> resolveAll(
    List<PluginExternalScript> scripts,
  ) async {
    final paths = <String>[];
    for (final script in scripts) {
      paths.add(await _resolve(script));
    }
    return paths;
  }

  static Future<String> prepareRendererPage(
    PluginDanmakuRenderer renderer,
  ) async {
    final scriptPaths = await resolveAll(renderer.externalScripts);
    final appDir = await StorageService.getAppStorageDirectory();
    final pageDir = Directory(
      path.join(appDir.path, 'plugins', '.renderer-host'),
    );
    await pageDir.create(recursive: true);
    final pageKey = sha256
        .convert(
          'v$_rendererPageTemplateVersion\n${renderer.selectionId}\n'
                  '${renderer.bootstrap}\n${scriptPaths.join('\n')}'
              .codeUnits,
        )
        .toString();
    final page = File(path.join(pageDir.path, '$pageKey.html'));
    if (await page.exists()) return page.path;

    final scriptTags = scriptPaths
        .map((scriptPath) =>
            '<script src="${Uri.file(scriptPath).toString()}"></script>')
        .join('\n');
    final safeBootstrap =
        renderer.bootstrap.replaceAll('</script', '<\\/script');
    final html = '''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta http-equiv="Content-Language" content="zh-CN">
<meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
<style>
:root{-webkit-locale:"zh-CN"}
html,body,#nipa-danmaku-root{margin:0;width:100%;height:100%;overflow:hidden;background:transparent!important;pointer-events:none;font-family:-apple-system,"PingFang SC","Hiragino Sans GB","Microsoft YaHei","Noto Sans CJK SC","Source Han Sans SC",sans-serif}
</style>
</head><body><div id="nipa-danmaku-root"></div>
$scriptTags
<script>
void (async function () {
  try {
    await (async function () { $safeBootstrap }).call(window);
    if (!window.NipaDanmakuRenderer || typeof window.NipaDanmakuRenderer.handle !== 'function') {
      throw new Error('bootstrap did not install NipaDanmakuRenderer.handle');
    }
    NipaDanmakuHost.postMessage(JSON.stringify({type:'ready'}));
  } catch (error) {
    NipaDanmakuHost.postMessage(JSON.stringify({type:'error', message:String(error && error.stack || error)}));
  }
})();
</script></body></html>''';
    await page.writeAsString(html, flush: true);
    return page.path;
  }

  static Future<String> _resolve(PluginExternalScript script) async {
    final key = '${script.url}#${script.sha256 ?? ''}';
    final existing = _inFlight[key];
    if (existing != null) return existing;
    final future = _resolveUncached(script);
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  static Future<String> _resolveUncached(PluginExternalScript script) async {
    final appDir = await StorageService.getAppStorageDirectory();
    final cacheDir = Directory(
      path.join(appDir.path, 'plugins', '.renderer-host', 'scripts'),
    );
    await cacheDir.create(recursive: true);
    final cacheKey = sha256.convert(script.url.toString().codeUnits).toString();
    final target = File(path.join(cacheDir.path, '$cacheKey.js'));

    if (await target.exists()) {
      final bytes = await target.readAsBytes();
      if (_isValid(bytes, script.sha256)) return target.path;
      await target.delete();
    }

    final response = await http.get(script.url).timeout(_downloadTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        '外部脚本下载失败 (${response.statusCode})',
        uri: script.url,
      );
    }
    final bytes = response.bodyBytes;
    if (bytes.isEmpty || bytes.length > _maxScriptBytes) {
      throw StateError('外部脚本文件大小无效: ${bytes.length} bytes');
    }
    if (!_isValid(bytes, script.sha256)) {
      throw StateError('外部脚本 SHA-256 校验失败: ${script.id}');
    }

    final temporary = File('${target.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(target.path);
    return target.path;
  }

  static bool _isValid(List<int> bytes, String? expectedSha256) {
    if (bytes.isEmpty || bytes.length > _maxScriptBytes) return false;
    if (expectedSha256 == null) return true;
    return sha256.convert(bytes).toString() == expectedSha256;
  }
}
