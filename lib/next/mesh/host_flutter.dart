import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/services/remote_control_settings.dart';
import 'package:nipaplay/services/remote_control_access_guard_service.dart';
import 'package:shelf/shelf.dart';

const meshDevelopmentHost = kDebugMode;
Future<Failure?> authorizeMeshPeer(String deviceId, String name) async {
  if (!await RemoteControlSettings.isReceiverEnabled()) {
    return const Failure(FailureCode.unavailable,
        'Classic remote control receiver is disabled.');
  }
  final guard = RemoteControlAccessGuardService.instance;
  await guard.loadTrustedDevices();
  final result = await guard.evaluate(Request('POST', Uri.parse('http://localhost/mesh'),
      headers: {'x-nipaplay-remote-client-id': deviceId,
        'x-nipaplay-remote-client-name': name}), requestAccess: true);
  return result.isAuthorized ? null : Failure(FailureCode.conflict,
      'Classic remote control access is ${result.status.name}; the user must allow this device in NipaPlay.');
}
