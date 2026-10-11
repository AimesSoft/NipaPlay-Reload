import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class MediaServerDeviceIdService {
  MediaServerDeviceIdService._();

  static final MediaServerDeviceIdService instance = MediaServerDeviceIdService._();

  static const String _keyGeneratedDeviceId = 'media_server_device_id_generated_v1';
  static const String _keyCustomDeviceId = 'media_server_device_id_custom_v1';

  static const int _maxCustomDeviceIdLength = 128;

  final Uuid _uuid = const Uuid();

  String? _cachedGeneratedDeviceId;
  String? _cachedCustomDeviceId;

  static bool isValidCustomDeviceId(String deviceId) {
    if (deviceId.isEmpty) return false;
    if (deviceId.length > _maxCustomDeviceIdLength) return false;
    if (deviceId.contains('"')) return false;
    if (deviceId.contains('\n') || deviceId.contains('\r')) return false;
    return true;
  }

  static String? _normalizeCustomDeviceId(String? deviceId) {
    final normalized = deviceId?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    if (!isValidCustomDeviceId(normalized)) {
      throw const FormatException('Invalid custom DeviceId');
    }
    return normalized;
  }

  Future<String?> getCustomDeviceId() async {
    if (_cachedCustomDeviceId != null) {
      return _cachedCustomDeviceId;
    }

    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyCustomDeviceId)?.trim();
    if (value == null || value.isEmpty) {
      _cachedCustomDeviceId = null;
      return null;
    }

    if (!isValidCustomDeviceId(value)) {
      await prefs.remove(_keyCustomDeviceId);
      _cachedCustomDeviceId = null;
      return null;
    }

    _cachedCustomDeviceId = value;
    return value;
  }

  Future<void> setCustomDeviceId(String? deviceId) async {
    final normalized = _normalizeCustomDeviceId(deviceId);
    final prefs = await SharedPreferences.getInstance();

    if (normalized == null) {
      await prefs.remove(_keyCustomDeviceId);
      _cachedCustomDeviceId = null;
      return;
    }

    await prefs.setString(_keyCustomDeviceId, normalized);
    _cachedCustomDeviceId = normalized;
  }

  Future<String> getOrCreateGeneratedDeviceId() async {
    if (_cachedGeneratedDeviceId != null) {
      return _cachedGeneratedDeviceId!;
    }

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_keyGeneratedDeviceId)?.trim();
    if (existing != null && existing.isNotEmpty) {
      _cachedGeneratedDeviceId = existing;
      return existing;
    }

    final generated = _uuid.v4();
    await prefs.setString(_keyGeneratedDeviceId, generated);
    _cachedGeneratedDeviceId = generated;
    return generated;
  }

  Future<void> resetGeneratedDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyGeneratedDeviceId);
    _cachedGeneratedDeviceId = null;
  }

  Future<String> getEffectiveDeviceId({
    required String appName,
    required String platform,
  }) async {
    final custom = await getCustomDeviceId();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }

    final generated = await getOrCreateGeneratedDeviceId();
    return '$appName-$platform-$generated';
  }
}

