import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RemoteControlAuthManager {
  RemoteControlAuthManager._();

  static final RemoteControlAuthManager instance = RemoteControlAuthManager._();

  static const String trustedDevicesKey = 'remote_control_trusted_devices';
  static const String pendingRequestsKey = 'remote_control_pending_requests';

  final List<RemoteControlDevice> _trustedDevices = [];
  final List<ConnectionRequest> _pendingRequests = [];

  ValueNotifier<List<ConnectionRequest>> pendingRequestsNotifier = ValueNotifier([]);
  ValueNotifier<List<RemoteControlDevice>> trustedDevicesNotifier = ValueNotifier([]);

  Future<void> initialize() async {
    await _loadTrustedDevices();
    await _loadPendingRequests();
  }

  Future<void> _loadTrustedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(trustedDevicesKey);
    if (data != null) {
      try {
        final List<dynamic> list = json.decode(data);
        _trustedDevices.clear();
        for (final item in list) {
          _trustedDevices.add(RemoteControlDevice.fromJson(item));
        }
        trustedDevicesNotifier.value = List.from(_trustedDevices);
      } catch (e) {
        debugPrint('Failed to load trusted devices: $e');
      }
    }
  }

  Future<void> _saveTrustedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final data = json.encode(_trustedDevices.map((device) => device.toJson()).toList());
    await prefs.setString(trustedDevicesKey, data);
    trustedDevicesNotifier.value = List.from(_trustedDevices);
  }

  Future<void> _loadPendingRequests() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(pendingRequestsKey);
    if (data != null) {
      try {
        final List<dynamic> list = json.decode(data);
        _pendingRequests.clear();
        for (final item in list) {
          _pendingRequests.add(ConnectionRequest.fromJson(item));
        }
        pendingRequestsNotifier.value = List.from(_pendingRequests);
      } catch (e) {
        debugPrint('Failed to load pending requests: $e');
      }
    }
  }

  Future<void> _savePendingRequests() async {
    final prefs = await SharedPreferences.getInstance();
    final data = json.encode(_pendingRequests.map((request) => request.toJson()).toList());
    await prefs.setString(pendingRequestsKey, data);
    pendingRequestsNotifier.value = List.from(_pendingRequests);
  }

  Future<ConnectionRequest> createConnectionRequest({
    required String deviceName,
    required String deviceType,
    required String ipAddress,
  }) async {
    final request = ConnectionRequest(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      deviceName: deviceName,
      deviceType: deviceType,
      ipAddress: ipAddress,
      timestamp: DateTime.now(),
    );

    _pendingRequests.add(request);
    await _savePendingRequests();
    return request;
  }

  Future<void> authorizeRequest(String requestId, bool allow, bool trustDevice) async {
    final requestIndex = _pendingRequests.indexWhere((r) => r.id == requestId);
    if (requestIndex == -1) return;

    final request = _pendingRequests[requestIndex];
    _pendingRequests.removeAt(requestIndex);
    await _savePendingRequests();

    if (allow && trustDevice) {
      final device = RemoteControlDevice(
        id: '${request.deviceName}_${request.ipAddress}',
        deviceName: request.deviceName,
        deviceType: request.deviceType,
        ipAddress: request.ipAddress,
        trustedAt: DateTime.now(),
      );

      if (!_trustedDevices.any((d) => d.id == device.id)) {
        _trustedDevices.add(device);
        await _saveTrustedDevices();
      }
    }
  }

  bool isTrustedDevice(String ipAddress) {
    return _trustedDevices.any((device) => device.ipAddress == ipAddress);
  }

  Future<void> removeTrustedDevice(String deviceId) async {
    _trustedDevices.removeWhere((device) => device.id == deviceId);
    await _saveTrustedDevices();
  }

  List<RemoteControlDevice> getTrustedDevices() {
    return List.from(_trustedDevices);
  }

  List<ConnectionRequest> getPendingRequests() {
    return List.from(_pendingRequests);
  }
}

class RemoteControlDevice {
  final String id;
  final String deviceName;
  final String deviceType;
  final String ipAddress;
  final DateTime trustedAt;

  RemoteControlDevice({
    required this.id,
    required this.deviceName,
    required this.deviceType,
    required this.ipAddress,
    required this.trustedAt,
  });

  factory RemoteControlDevice.fromJson(Map<String, dynamic> json) {
    return RemoteControlDevice(
      id: json['id'] ?? '',
      deviceName: json['deviceName'] ?? '',
      deviceType: json['deviceType'] ?? '',
      ipAddress: json['ipAddress'] ?? '',
      trustedAt: DateTime.parse(json['trustedAt'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deviceName': deviceName,
      'deviceType': deviceType,
      'ipAddress': ipAddress,
      'trustedAt': trustedAt.toIso8601String(),
    };
  }
}

class ConnectionRequest {
  final String id;
  final String deviceName;
  final String deviceType;
  final String ipAddress;
  final DateTime timestamp;

  ConnectionRequest({
    required this.id,
    required this.deviceName,
    required this.deviceType,
    required this.ipAddress,
    required this.timestamp,
  });

  factory ConnectionRequest.fromJson(Map<String, dynamic> json) {
    return ConnectionRequest(
      id: json['id'] ?? '',
      deviceName: json['deviceName'] ?? '',
      deviceType: json['deviceType'] ?? '',
      ipAddress: json['ipAddress'] ?? '',
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deviceName': deviceName,
      'deviceType': deviceType,
      'ipAddress': ipAddress,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
