import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:nipa_harness/nipa_harness.dart';
import '../followups/service.dart';
import 'runtime.dart';

/// Conversation targets are issued by the conversation host, bound to a peer,
/// and persisted before submission. Neither remote facts nor scripts select a
/// different conversation for an automatic download return.
void attachMeshDelivery(MeshRuntime mesh, Followups followups) {
  final file = File('${mesh.root.path}/mesh-return-targets.json');
  Future<void> pending = Future.value();
  mesh.returnTarget = (peer, invocation) async {
    final target = await followups.downloadReturnTarget(invocation);
    if (target == null) return null;
    final ticket = base64Url
        .encode(List.generate(24, (_) => Random.secure().nextInt(256)))
        .replaceAll('=', '');
    pending = pending.then((_) async {
      final saved = await file.exists()
          ? jsonDecode(await file.readAsString()) as JsonMap
          : <String, Object?>{};
      saved[ticket] = {'peer': peer, ...target};
      final staging = File('${file.path}.pending');
      await staging.writeAsString(jsonEncode(saved), flush: true);
      await staging.rename(file.path);
    });
    await pending;
    return {...target, 'returnTicket': ticket};
  };
  followups.agentDevice = () {
    final peer = mesh.hostConfiguration['agentDeviceId'] as String?;
    return peer == mesh.identity?.deviceId ? null : peer;
  };
  followups.deliverRemote =
      (peer, row) => mesh.rpc(peer, 'mesh/delivery', {'row': row});
  mesh.receiveDelivery = (peer, payload) async {
    if (payload['row'] is! JsonMap) {
      throw const FormatException('Invalid delivery.');
    }
    final row = payload['row'] as JsonMap;
    if (row['id'] is! String ||
        row['invocationId'] is! String ||
        row['trigger'] is! JsonMap ||
        row['instruction'] is! String ||
        row['title'] is! String ||
        row['condition'] is! JsonMap) {
      throw const FormatException('Invalid delivery facts.');
    }
    if (const {'download', 'program', 'subscription'}.contains(row['automatic'])) {
      if (row['automatic'] != 'subscription' && (row['deliverAfter'] is! String ||
          (row['trigger'] as Map)['facts'] is! List)) {
        throw const FormatException('Invalid download delivery.');
      }
      if (row['automatic'] != 'subscription') DateTime.parse(row['deliverAfter'] as String);
      await pending;
      final saved = await file.exists()
          ? jsonDecode(await file.readAsString()) as JsonMap
          : <String, Object?>{};
      final target = saved[row['returnTicket']];
      if (target is! JsonMap ||
          target['peer'] != peer ||
          target['threadId'] != row['threadId'] ||
          target['repository'] != row['repository']) {
        throw const FormatException('Unissued download return target.');
      }
      return followups.acceptMeshDelivery(peer, payload, target: target);
    }
    if (row['automatic'] != null ||
        (row['condition'] as Map)['kind'] != 'wake') {
      throw const FormatException('Invalid wake.');
    }
    // Wake is addressed to this host's Nipa; headless receivers reject it.
    if (!(mesh.hostConfiguration['roles'] as List? ?? []).contains('agent')) {
      throw const FormatException('This device does not host Nipa.');
    }
    return followups.acceptMeshDelivery(peer, payload);
  };
}
