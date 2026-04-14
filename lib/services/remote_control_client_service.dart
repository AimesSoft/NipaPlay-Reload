import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/services/nipaplay_lan_discovery.dart';
import 'package:nipaplay/services/remote_control_settings.dart';

class RemoteControlDiscoveredDevice {
  const RemoteControlDiscoveredDevice({
    required this.ip,
    required this.port,
    required this.baseUrl,
    this.hostname,
  });

  final String ip;
  final int port;
  final String baseUrl;
  final String? hostname;
}

class RemoteControlClientService {
  static const Duration _requestTimeout = Duration(milliseconds: 900);

  static String normalizeBaseUrl(String input) {
    var value = input.trim();
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.endsWith('/api')) {
      value = value.substring(0, value.length - 4);
    }
    return value;
  }

  static Future<List<RemoteControlDiscoveredDevice>> discoverDevices() async {
    if (kIsWeb) return const [];
    final found = <String, RemoteControlDiscoveredDevice>{};
    final targets = await _resolveScanTargets();

    await _discoverByUdp(
      prefixes: targets.prefixes,
      onFound: (device) {
        found[device.baseUrl] = device;
      },
    );

    final udpDevices = found.values.toList(growable: false);
    final validUdpDevices = await _filterRemoteControlCompatible(udpDevices);
    if (validUdpDevices.isNotEmpty) {
      return validUdpDevices;
    }

    if (targets.candidates.isEmpty) return const [];

    final fallback = await _fallbackProbeByDefaultPort(targets.candidates);
    return await _filterRemoteControlCompatible(fallback);
  }

  static Future<RemoteControlDiscoveredDevice?> autoMatchDevice() async {
    final savedBaseUrl = await RemoteControlSettings.getMatchedBaseUrl();
    final savedHostname = await RemoteControlSettings.getMatchedHostname();
    if (savedBaseUrl != null) {
      final normalized = normalizeBaseUrl(savedBaseUrl);
      final state = await fetchState(normalized);
      if (state != null) {
        return RemoteControlDiscoveredDevice(
          ip: Uri.parse(normalized).host,
          port: Uri.parse(normalized).port,
          baseUrl: normalized,
          hostname: savedHostname,
        );
      }
    }

    final devices = await discoverDevices();
    if (devices.isEmpty) {
      return null;
    }
    devices.sort((a, b) {
      final hostA = (a.hostname ?? a.ip).toLowerCase();
      final hostB = (b.hostname ?? b.ip).toLowerCase();
      return hostA.compareTo(hostB);
    });
    final matched = devices.first;
    await RemoteControlSettings.saveMatchedTarget(
      baseUrl: matched.baseUrl,
      hostname: matched.hostname,
    );
    return matched;
  }

  static Future<Map<String, dynamic>?> fetchState(
    String baseUrl, {
    String? paneId,
    bool includeParameters = false,
    bool requestAccess = false,
  }) async {
    final normalized = normalizeBaseUrl(baseUrl);
    try {
      final uri = Uri.parse('$normalized/api/remote/control/state').replace(
        queryParameters: <String, String>{
          if (includeParameters) 'includeParameters': '1',
          if (requestAccess) 'requestAccess': '1',
          if (paneId != null && paneId.trim().isNotEmpty)
            'paneId': paneId.trim(),
        },
      );
      final response = await http
          .get(
            uri,
            headers: await _buildClientHeaders(),
          )
          .timeout(_requestTimeout);
      if (response.statusCode != 200) {
        return null;
      }
      final decoded = json.decode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      if (decoded['success'] != true) {
        return null;
      }
      final data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        return null;
      }
      return data;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> sendCommand(
    String baseUrl, {
    required String command,
    Map<String, dynamic>? args,
  }) async {
    final normalized = normalizeBaseUrl(baseUrl);
    final response = await http
        .post(
          Uri.parse('$normalized/api/remote/control/command'),
          headers: await _buildClientHeaders(
            includeJsonContentType: true,
          ),
          body: json.encode(<String, dynamic>{
            'command': command,
            'args': args ?? const <String, dynamic>{},
          }),
        )
        .timeout(const Duration(seconds: 3));

    final decoded = json.decode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw Exception('遥控命令返回无效 JSON');
    }
    return decoded;
  }

  static Future<void> _discoverByUdp({
    required Set<String> prefixes,
    required void Function(RemoteControlDiscoveredDevice device) onFound,
  }) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;

      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = socket?.receive()) != null) {
          final parsed =
              NipaPlayLanDiscoveryProtocol.tryParseResponse(datagram!);
          if (parsed == null) continue;
          onFound(
            RemoteControlDiscoveredDevice(
              ip: parsed.ip,
              port: parsed.port,
              baseUrl: parsed.baseUrl,
              hostname: parsed.hostname,
            ),
          );
        }
      });

      final request = NipaPlayLanDiscoveryProtocol.buildRequestBytes();
      final targets = <InternetAddress>{
        InternetAddress('255.255.255.255'),
        ...prefixes.map((prefix) => InternetAddress('${prefix}255')),
      };

      void sendOnce() {
        for (final address in targets) {
          try {
            socket?.send(request, address, nipaplayLanDiscoveryPort);
          } catch (_) {}
        }
      }

      sendOnce();
      await Future.delayed(const Duration(milliseconds: 220));
      sendOnce();
      await Future.delayed(const Duration(milliseconds: 220));
      sendOnce();
      await Future.delayed(const Duration(milliseconds: 900));
    } catch (e) {
      debugPrint('RemoteControl UDP discover failed: $e');
    } finally {
      try {
        socket?.close();
      } catch (_) {}
    }
  }

  static Future<Map<String, String>> _buildClientHeaders({
    bool includeJsonContentType = false,
  }) async {
    final headers = <String, String>{};
    if (includeJsonContentType) {
      headers['Content-Type'] = 'application/json';
    }
    final clientId = await RemoteControlSettings.getOrCreateClientId();
    headers['X-NipaPlay-Remote-Client-Id'] = clientId;
    final clientName = _safeLocalHostname();
    if (clientName.isNotEmpty) {
      headers['X-NipaPlay-Remote-Client-Name'] = clientName;
    }
    headers['X-NipaPlay-Remote-Client-Platform'] = Platform.operatingSystem;
    return headers;
  }

  static String _safeLocalHostname() {
    try {
      final hostname = Platform.localHostname.trim();
      return hostname;
    } catch (_) {
      return '';
    }
  }

  static Future<List<RemoteControlDiscoveredDevice>>
      _filterRemoteControlCompatible(
    List<RemoteControlDiscoveredDevice> devices,
  ) async {
    if (devices.isEmpty) return const [];
    final valid = <RemoteControlDiscoveredDevice>[];
    for (final device in devices) {
      if (await _probeRemoteControl(device.baseUrl)) {
        valid.add(device);
      }
    }
    return valid;
  }

  static Future<bool> _probeRemoteControl(String baseUrl) async {
    final normalized = normalizeBaseUrl(baseUrl);
    try {
      final info = await http
          .get(Uri.parse('$normalized/api/info'))
          .timeout(_requestTimeout);
      if (info.statusCode != 200) return false;
      final infoJson = json.decode(utf8.decode(info.bodyBytes));
      if (infoJson is! Map<String, dynamic>) return false;
      if (infoJson['app'] != 'NipaPlay' || infoJson['success'] != true) {
        return false;
      }

      final state = await fetchState(normalized);
      if (state == null) return false;
      final receiverEnabled = state['receiverEnabled'] == true;
      return receiverEnabled;
    } catch (_) {
      return false;
    }
  }

  static Future<List<RemoteControlDiscoveredDevice>>
      _fallbackProbeByDefaultPort(
    List<String> candidates,
  ) async {
    final queue = List<String>.from(candidates);
    final result = <RemoteControlDiscoveredDevice>[];
    const concurrency = 32;

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final ip = queue.removeLast();
        final baseUrl = 'http://$ip:1180';
        if (await _probeRemoteControl(baseUrl)) {
          result.add(
            RemoteControlDiscoveredDevice(
              ip: ip,
              port: 1180,
              baseUrl: baseUrl,
            ),
          );
        }
      }
    }

    await Future.wait(
      List.generate(concurrency, (_) => worker()),
    );
    return result;
  }
}

class _ScanTargets {
  const _ScanTargets({
    required this.prefixes,
    required this.candidates,
  });

  final Set<String> prefixes;
  final List<String> candidates;
}

Future<_ScanTargets> _resolveScanTargets() async {
  final prefixes = <String>{};
  final selfIps = <String>{};

  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    includeLinkLocal: false,
    type: InternetAddressType.IPv4,
  );

  for (final interface in interfaces) {
    for (final addr in interface.addresses) {
      final ip = addr.address;
      if (!_isPrivateIpv4(ip)) continue;
      final parts = ip.split('.');
      if (parts.length != 4) continue;
      prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}.');
      selfIps.add(ip);
    }
  }

  final candidates = <String>[];
  final seen = <String>{};
  for (final prefix in prefixes) {
    for (var i = 1; i <= 254; i++) {
      final ip = '$prefix$i';
      if (selfIps.contains(ip)) continue;
      if (!seen.add(ip)) continue;
      candidates.add(ip);
    }
  }

  return _ScanTargets(prefixes: prefixes, candidates: candidates);
}

bool _isPrivateIpv4(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return false;
  final a = int.tryParse(parts[0]);
  final b = int.tryParse(parts[1]);
  if (a == null || b == null) return false;
  if (a == 10) return true;
  if (a == 192 && b == 168) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  return false;
}
