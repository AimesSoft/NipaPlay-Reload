import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

class RemoteAccessQrPayload {
  const RemoteAccessQrPayload({
    required this.baseUrl,
    this.candidateBaseUrls = const <String>[],
    this.displayName,
  });

  final String baseUrl;
  final List<String> candidateBaseUrls;
  final String? displayName;

  List<String> get allCandidateBaseUrls {
    final normalized = <String>[];
    final seen = <String>{};

    void add(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      try {
        final normalizedUrl = RemoteAccessQrService.normalizeRemoteAccessUrl(
          trimmed,
        );
        if (seen.add(normalizedUrl)) {
          normalized.add(normalizedUrl);
        }
      } catch (_) {
        // ignore invalid candidate
      }
    }

    add(baseUrl);
    for (final url in candidateBaseUrls) {
      add(url);
    }
    return normalized;
  }
}

class RemoteAccessServerInfo {
  const RemoteAccessServerInfo({
    required this.baseUrl,
    this.hostname,
    this.remoteControlReceiverEnabled = false,
  });

  final String baseUrl;
  final String? hostname;
  final bool remoteControlReceiverEnabled;

  String get displayName {
    final name = hostname?.trim() ?? '';
    return name.isEmpty ? baseUrl : name;
  }
}

class RemoteAccessQrService {
  RemoteAccessQrService._();

  static const String payloadType = 'nipaplay_remote_access';
  static const int defaultPort = 1180;

  static String buildPayload({
    required String baseUrl,
    List<String> candidateBaseUrls = const <String>[],
    String? displayName,
  }) {
    final normalizedBaseUrl = normalizeRemoteAccessUrl(baseUrl);
    final normalizedCandidates = <String>[];
    final seen = <String>{normalizedBaseUrl};

    for (final candidate in candidateBaseUrls) {
      try {
        final normalized = normalizeRemoteAccessUrl(candidate);
        if (seen.add(normalized)) {
          normalizedCandidates.add(normalized);
        }
      } catch (_) {
        // ignore invalid candidate
      }
    }

    if (normalizedCandidates.isEmpty && (displayName?.trim().isEmpty ?? true)) {
      return normalizedBaseUrl;
    }

    final payload = <String, dynamic>{
      'type': payloadType,
      'baseUrl': normalizedBaseUrl,
      if (normalizedCandidates.isNotEmpty) 'urls': normalizedCandidates,
      if (displayName?.trim().isNotEmpty == true)
        'displayName': displayName!.trim(),
    };
    return json.encode(payload);
  }

  static RemoteAccessQrPayload parseScannedText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('二维码内容为空');
    }

    final jsonPayload = _tryParseJsonPayload(trimmed);
    if (jsonPayload != null) {
      return jsonPayload;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.scheme == 'nipaplay') {
      final baseUrl =
          uri.queryParameters['baseUrl'] ?? uri.queryParameters['url'] ?? '';
      if (baseUrl.trim().isNotEmpty) {
        final multiUrlsRaw = uri.queryParametersAll['url'];
        final candidates = <String>[];
        if (multiUrlsRaw != null && multiUrlsRaw.isNotEmpty) {
          candidates
              .addAll(multiUrlsRaw.where((item) => item.trim().isNotEmpty));
        }
        return RemoteAccessQrPayload(
          baseUrl: normalizeRemoteAccessUrl(baseUrl),
          candidateBaseUrls: candidates,
          displayName: uri.queryParameters['name'],
        );
      }
    }

    return RemoteAccessQrPayload(
      baseUrl: normalizeRemoteAccessUrl(trimmed),
    );
  }

  static String normalizeRemoteAccessUrl(String input) {
    var value = input.trim();
    if (value.isEmpty) {
      throw const FormatException('访问地址为空');
    }

    if (!value.contains('://')) {
      value = 'http://$value';
    }

    var uri = Uri.tryParse(value);
    if (uri == null || uri.host.trim().isEmpty) {
      throw const FormatException('不是有效的访问地址');
    }

    uri = uri.replace(path: '', query: null, fragment: null);

    if (!uri.hasPort && uri.scheme == 'http') {
      uri = uri.replace(port: defaultPort);
    }

    var normalized = uri.toString();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static Future<RemoteAccessServerInfo?> fetchServerInfo(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final normalized = normalizeRemoteAccessUrl(baseUrl);
    try {
      final response =
          await http.get(Uri.parse('$normalized/api/info')).timeout(timeout);
      if (response.statusCode != 200) return null;

      final decoded = json.decode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['success'] != true || decoded['app'] != 'NipaPlay') {
        return null;
      }

      final hostname = decoded['hostname'] is String
          ? (decoded['hostname'] as String).trim()
          : null;
      return RemoteAccessServerInfo(
        baseUrl: normalized,
        hostname: hostname?.isEmpty == true ? null : hostname,
        remoteControlReceiverEnabled:
            decoded['remoteControlReceiverEnabled'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  static RemoteAccessQrPayload? _tryParseJsonPayload(String text) {
    try {
      final decoded = json.decode(text);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['type'] != payloadType) return null;
      final baseUrl = decoded['baseUrl']?.toString().trim() ?? '';
      if (baseUrl.isEmpty) return null;
      final displayName =
          decoded['name']?.toString() ?? decoded['displayName']?.toString();
      final candidateUrls = <String>[];
      final rawUrls = decoded['urls'];
      if (rawUrls is List) {
        for (final value in rawUrls) {
          final text = value?.toString().trim();
          if (text != null && text.isNotEmpty) {
            candidateUrls.add(text);
          }
        }
      } else if (rawUrls is String && rawUrls.trim().isNotEmpty) {
        candidateUrls.add(rawUrls.trim());
      }
      return RemoteAccessQrPayload(
        baseUrl: normalizeRemoteAccessUrl(baseUrl),
        candidateBaseUrls: candidateUrls,
        displayName: displayName,
      );
    } catch (_) {
      return null;
    }
  }
}

class RemoteAccessQrCameraScanner {
  RemoteAccessQrCameraScanner._();

  static bool get isSupported {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  static Future<RemoteAccessQrPayload?> scan(BuildContext context) async {
    if (!isSupported) {
      throw UnsupportedError('当前平台不支持相机扫码');
    }

    final scannedText =
        await Navigator.of(context, rootNavigator: true).push<String>(
      CupertinoPageRoute(builder: (_) => const _RemoteAccessQrScannerPage()),
    );
    if (scannedText == null || scannedText.trim().isEmpty) return null;
    return RemoteAccessQrService.parseScannedText(scannedText);
  }
}

class _RemoteAccessQrScannerPage extends StatefulWidget {
  const _RemoteAccessQrScannerPage();

  @override
  State<_RemoteAccessQrScannerPage> createState() =>
      _RemoteAccessQrScannerPageState();
}

class _RemoteAccessQrScannerPageState
    extends State<_RemoteAccessQrScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
  );
  bool _hasResult = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasResult) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue?.trim();
      if (code == null || code.isEmpty) continue;
      if (!mounted) return;
      _hasResult = true;
      unawaited(_controller.stop());
      Navigator.of(context).pop(code);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('扫码连接'),
      ),
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 28,
              child: Text(
                '将二维码放入取景框内自动识别',
                textAlign: TextAlign.center,
                style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                      color: CupertinoColors.white,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
