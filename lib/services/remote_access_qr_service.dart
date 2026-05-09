import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:zxing2/qrcode.dart';

class RemoteAccessQrPayload {
  const RemoteAccessQrPayload({
    required this.baseUrl,
    this.displayName,
  });

  final String baseUrl;
  final String? displayName;
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

  static String buildPayload({required String baseUrl}) {
    return normalizeRemoteAccessUrl(baseUrl);
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
        return RemoteAccessQrPayload(
          baseUrl: normalizeRemoteAccessUrl(baseUrl),
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

    uri = uri.replace(path: '', query: '', fragment: '');

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

  static String decodeQrImage(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('无法读取拍摄的图片');
    }

    final oriented = img.bakeOrientation(decoded);
    final candidates = <img.Image>[
      oriented,
      if (oriented.width > 1600 || oriented.height > 1600)
        img.copyResize(
          oriented,
          width: oriented.width >= oriented.height ? 1600 : null,
          height: oriented.height > oriented.width ? 1600 : null,
          interpolation: img.Interpolation.average,
        ),
    ];

    Object? lastError;
    for (final candidate in candidates) {
      try {
        final rgba = candidate
            .convert(numChannels: 4)
            .getBytes(order: img.ChannelOrder.rgba);
        final pixels = rgba.buffer.asInt32List(
          rgba.offsetInBytes,
          rgba.lengthInBytes ~/ 4,
        );
        final source = RGBLuminanceSource(
          candidate.width,
          candidate.height,
          pixels,
        );
        final bitmap = BinaryBitmap(HybridBinarizer(source));
        return QRCodeReader().decode(bitmap).text;
      } catch (e) {
        lastError = e;
      }
    }

    throw FormatException('未识别到二维码', lastError);
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
      return RemoteAccessQrPayload(
        baseUrl: normalizeRemoteAccessUrl(baseUrl),
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
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static Future<RemoteAccessQrPayload?> scan() async {
    if (!isSupported) {
      throw UnsupportedError('当前平台不支持相机扫码');
    }

    final image = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
      maxWidth: 2400,
      maxHeight: 2400,
    );
    if (image == null) return null;

    final bytes = await image.readAsBytes();
    final scannedText = await compute(decodeRemoteAccessQrImage, bytes);
    return RemoteAccessQrService.parseScannedText(scannedText);
  }
}

String decodeRemoteAccessQrImage(Uint8List bytes) {
  return RemoteAccessQrService.decodeQrImage(bytes);
}
