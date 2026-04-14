import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:shelf/shelf.dart';

enum RemoteControlAccessStatus {
  authorized,
  pending,
  denied,
  required,
}

class RemoteControlAccessResult {
  const RemoteControlAccessResult({
    required this.status,
    required this.identity,
  });

  final RemoteControlAccessStatus status;
  final RemoteControlClientIdentity identity;

  bool get isAuthorized => status == RemoteControlAccessStatus.authorized;
}

class RemoteControlClientIdentity {
  const RemoteControlClientIdentity({
    required this.clientKey,
    required this.remoteIp,
    required this.clientId,
    required this.clientName,
    required this.platform,
  });

  final String clientKey;
  final String remoteIp;
  final String? clientId;
  final String? clientName;
  final String? platform;

  String get displayName {
    final trimmedName = clientName?.trim() ?? '';
    if (trimmedName.isNotEmpty) {
      if (remoteIp == 'unknown') return trimmedName;
      return '$trimmedName ($remoteIp)';
    }
    if (remoteIp != 'unknown') {
      return remoteIp;
    }
    return '未知设备';
  }
}

class RemoteControlAccessGuardService {
  RemoteControlAccessGuardService._();

  static final RemoteControlAccessGuardService instance =
      RemoteControlAccessGuardService._();

  static const String _clientIdHeader = 'x-nipaplay-remote-client-id';
  static const String _clientNameHeader = 'x-nipaplay-remote-client-name';
  static const String _clientPlatformHeader =
      'x-nipaplay-remote-client-platform';
  static const Duration _denyCooldown = Duration(seconds: 8);

  final Map<String, DateTime> _approvedClients = {};
  final Map<String, DateTime> _deniedClients = {};
  final Map<String, Future<bool>> _pendingPrompts = {};

  Future<RemoteControlAccessResult> evaluate(
    Request request, {
    required bool requestAccess,
  }) async {
    final identity = _resolveIdentity(request);
    final now = DateTime.now();

    final approved = _approvedClients[identity.clientKey];
    if (approved != null) {
      _approvedClients[identity.clientKey] = now;
      return RemoteControlAccessResult(
        status: RemoteControlAccessStatus.authorized,
        identity: identity,
      );
    }

    if (!requestAccess) {
      return RemoteControlAccessResult(
        status: RemoteControlAccessStatus.required,
        identity: identity,
      );
    }

    if (_pendingPrompts.containsKey(identity.clientKey)) {
      return RemoteControlAccessResult(
        status: RemoteControlAccessStatus.pending,
        identity: identity,
      );
    }

    final deniedAt = _deniedClients[identity.clientKey];
    if (deniedAt != null) {
      final cooledDown = now.difference(deniedAt) >= _denyCooldown;
      if (!cooledDown) {
        return RemoteControlAccessResult(
          status: RemoteControlAccessStatus.denied,
          identity: identity,
        );
      }
      _deniedClients.remove(identity.clientKey);
    }

    _schedulePrompt(identity);
    return RemoteControlAccessResult(
      status: RemoteControlAccessStatus.pending,
      identity: identity,
    );
  }

  void _schedulePrompt(RemoteControlClientIdentity identity) {
    debugPrint(
      '[RemoteControlAuth] 请求授权: ${identity.displayName}, '
      'id=${identity.clientId ?? '-'}, platform=${identity.platform ?? '-'}',
    );
    final promptFuture = _showApprovalDialog(identity).then((approved) {
      if (approved) {
        final now = DateTime.now();
        _approvedClients[identity.clientKey] = now;
        _deniedClients.remove(identity.clientKey);
        debugPrint('[RemoteControlAuth] 用户已允许: ${identity.displayName}');
        return true;
      }

      _approvedClients.remove(identity.clientKey);
      _deniedClients[identity.clientKey] = DateTime.now();
      debugPrint('[RemoteControlAuth] 用户已拒绝: ${identity.displayName}');
      return false;
    });

    _pendingPrompts[identity.clientKey] = promptFuture;
    unawaited(
      promptFuture.whenComplete(() {
        _pendingPrompts.remove(identity.clientKey);
      }),
    );
  }

  Future<bool> _showApprovalDialog(RemoteControlClientIdentity identity) async {
    final navigator = globals.navigatorKey.currentState;
    final context = navigator?.overlay?.context ?? navigator?.context;
    if (context == null) {
      debugPrint('[RemoteControlAuth] 无法弹窗：navigator context 为空');
      return false;
    }

    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog.adaptive(
            title: const Text('遥控连接请求'),
            content: Text(
              '${identity.displayName} 正在请求连接并遥控此设备，是否允许？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('拒绝'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('允许'),
              ),
            ],
          );
        },
      );
      return result == true;
    } catch (e) {
      debugPrint('[RemoteControlAuth] 弹窗失败: $e');
      return false;
    }
  }

  RemoteControlClientIdentity _resolveIdentity(Request request) {
    final clientId = _readHeader(request, _clientIdHeader);
    final clientName = _readHeader(request, _clientNameHeader);
    final platform = _readHeader(request, _clientPlatformHeader);
    final remoteIp = _resolveRemoteIp(request);
    final normalizedClientId = clientId?.trim();
    final hasClientId =
        normalizedClientId != null && normalizedClientId.isNotEmpty;
    final clientKey = hasClientId ? 'id:$normalizedClientId' : 'ip:$remoteIp';

    return RemoteControlClientIdentity(
      clientKey: clientKey,
      remoteIp: remoteIp,
      clientId: hasClientId ? normalizedClientId : null,
      clientName:
          clientName?.trim().isNotEmpty == true ? clientName!.trim() : null,
      platform: platform?.trim().isNotEmpty == true ? platform!.trim() : null,
    );
  }

  String? _readHeader(Request request, String key) {
    final direct = request.headers[key];
    if (direct != null) return direct;
    final lower = key.toLowerCase();
    final lowerValue = request.headers[lower];
    if (lowerValue != null) return lowerValue;
    for (final entry in request.headers.entries) {
      if (entry.key.toLowerCase() == lower) {
        return entry.value;
      }
    }
    return null;
  }

  String _resolveRemoteIp(Request request) {
    final forwardedFor = _readHeader(request, 'x-forwarded-for');
    if (forwardedFor != null && forwardedFor.trim().isNotEmpty) {
      final first = forwardedFor.split(',').first.trim();
      if (first.isNotEmpty) {
        return first;
      }
    }

    final connectionInfo = request.context['shelf.io.connection_info'];
    if (connectionInfo is HttpConnectionInfo) {
      return connectionInfo.remoteAddress.address;
    }
    if (connectionInfo != null) {
      try {
        final remoteAddress = (connectionInfo as dynamic).remoteAddress;
        if (remoteAddress is InternetAddress) {
          return remoteAddress.address;
        }
        final asText = remoteAddress?.toString().trim();
        if (asText != null && asText.isNotEmpty) {
          return asText;
        }
      } catch (_) {
        // no-op
      }
    }

    final realIp = _readHeader(request, 'x-real-ip');
    if (realIp != null && realIp.trim().isNotEmpty) {
      return realIp.trim();
    }
    return 'unknown';
  }
}
