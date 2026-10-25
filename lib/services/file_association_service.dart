import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FileAssociationService {
  static const MethodChannel _channel =
      MethodChannel('file_association_channel');
  static final StreamController<String> _openFileController =
      StreamController<String>.broadcast(onListen: _drainPendingIOSFiles);
  static final StreamController<String> _openFileErrorController =
      StreamController<String>.broadcast(onListen: _drainPendingIOSErrors);
  static bool _handlerInitialized = false;
  static Future<void>? _fileDrain;
  static Future<void>? _errorDrain;
  static bool _fileDrainRequested = false;
  static bool _errorDrainRequested = false;

  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Stream<String> get openFileStream {
    _ensureHandlerInitialized();
    return _openFileController.stream;
  }

  static Stream<String> get openFileErrorStream {
    _ensureHandlerInitialized();
    return _openFileErrorController.stream;
  }

  /// 获取系统传入的下一个文件路径。iOS 从原生队列逐个取出。
  static Future<String?> getOpenFileUri() async {
    if (!Platform.isAndroid && !_isIOS) {
      return null;
    }

    _ensureHandlerInitialized();

    try {
      final result = await _channel.invokeMethod('getOpenFileUri');
      return result as String?;
    } on PlatformException catch (e) {
      debugPrint("获取打开文件URI失败: '${e.message}'.");
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static void _ensureHandlerInitialized() {
    if (_handlerInitialized) return;
    _handlerInitialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onOpenFileUri') {
        if (_isIOS) {
          _drainPendingIOSFiles();
        } else {
          final value = call.arguments;
          if (value is String && value.isNotEmpty) {
            _openFileController.add(value);
          }
        }
      } else if (call.method == 'onOpenFileError' && _isIOS) {
        _drainPendingIOSErrors();
      }
    });
  }

  static void _drainPendingIOSFiles() {
    if (!_isIOS || !_openFileController.hasListener) return;
    _fileDrainRequested = true;
    _fileDrain ??= _drainIOSQueue(
      method: 'getOpenFileUri',
      controller: _openFileController,
      isRequested: () => _fileDrainRequested,
      clearRequest: () => _fileDrainRequested = false,
      onComplete: () {
        _fileDrain = null;
        if (_fileDrainRequested) _drainPendingIOSFiles();
      },
    );
  }

  static void _drainPendingIOSErrors() {
    if (!_isIOS || !_openFileErrorController.hasListener) return;
    _errorDrainRequested = true;
    _errorDrain ??= _drainIOSQueue(
      method: 'getOpenFileError',
      controller: _openFileErrorController,
      isRequested: () => _errorDrainRequested,
      clearRequest: () => _errorDrainRequested = false,
      onComplete: () {
        _errorDrain = null;
        if (_errorDrainRequested) _drainPendingIOSErrors();
      },
    );
  }

  static Future<void> _drainIOSQueue({
    required String method,
    required StreamController<String> controller,
    required bool Function() isRequested,
    required void Function() clearRequest,
    required void Function() onComplete,
  }) async {
    try {
      while (controller.hasListener && isRequested()) {
        clearRequest();
        while (controller.hasListener) {
          final String? value;
          try {
            value = await _channel.invokeMethod<String>(method);
          } on PlatformException catch (error) {
            debugPrint('读取 iOS 打开文件事件失败: $error');
            break;
          } on MissingPluginException {
            break;
          }
          if (value == null || value.isEmpty) break;
          controller.add(value);
        }
      }
    } finally {
      onComplete();
    }
  }

  /// 检查文件是否为支持的视频格式
  static bool isSupportedVideoFile(String filePath) {
    final supportedExtensions = [
      '.mp4',
      '.mkv',
      '.avi',
      '.mov',
      '.webm',
      '.wmv',
      '.m4v',
      '.3gp',
      '.flv',
      '.ts',
      '.m2ts'
    ];

    final extension = '.${filePath.toLowerCase().split('.').last}';
    return supportedExtensions.contains(extension);
  }

  /// 验证文件路径是否有效
  static Future<bool> validateFilePath(String filePath) async {
    try {
      final file = File(filePath);
      return await file.exists() && isSupportedVideoFile(filePath);
    } catch (e) {
      debugPrint("验证文件路径失败: $e");
      return false;
    }
  }
}
