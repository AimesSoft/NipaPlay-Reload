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
  followups.remoteDeviceFact = mesh.deviceDeliveryFact;
  mesh.rosterChanges.listen((_) => followups.remoteRosterChanged());
  mesh.hasDelivery = followups.hasRemoteDelivery;
  mesh.deliveryRequest = (peer, method, params) async {
    if (method == 'mesh/delivery/pull') {
      return {'rows': await followups.pullRemoteDeliveries(peer)};
    }
    final id = params['id'];
    final receipt = params['receipt'];
    final own = mesh.identity?.deviceId;
    if (id is! String ||
        receipt is! JsonMap ||
        receipt['accepted'] != true ||
        receipt['id'] is! String ||
        (own != null && receipt['id'] != 'followup-mesh-$own-$id')) {
      throw const FormatException('Invalid delivery ACK.');
    }
    await followups.acknowledgeRemoteDelivery(
        peer, id, {'id': receipt['id'], 'accepted': true});
    return {'accepted': true};
  };
  mesh.pullDelivery = (peer) async {
    while (true) {
      final result = await mesh.rpc(peer, 'mesh/delivery/pull', const {},
          ungated: true);
      final rows = (result['rows'] as List).cast<JsonMap>();
      if (rows.isEmpty) return;
      for (final row in rows) {
        final JsonMap receipt;
        try {
          receipt = await mesh.receiveDelivery!(peer, {'row': row});
        } on FormatException {
          continue;
        }
        if (receipt['accepted'] == true) {
          await mesh.rpc(peer, 'mesh/delivery/ack',
              {'id': row['id'], 'receipt': receipt}, ungated: true);
        }
      }
    }
  };
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
    final inboxReturn =
        const {'inboxAnswer', 'folderRequest'}.contains(row['automatic']);
    final ticketed = inboxReturn && row['returnTicket'] != null;
    if (ticketed ||
        const {'download', 'program', 'userTask', 'subscription'}
            .contains(row['automatic'])) {
      final batched =
          const {'download', 'program', 'userTask'}.contains(row['automatic']);
      if (inboxReturn && (row['trigger'] as Map)['facts'] is! Map) {
        throw const FormatException('Invalid inbox delivery.');
      }
      if (batched &&
          (row['deliverAfter'] is! String ||
              (row['trigger'] as Map)['facts'] is! List)) {
        throw const FormatException('Invalid download delivery.');
      }
      if (batched) DateTime.parse(row['deliverAfter'] as String);
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
    final folderWake = row['automatic'] == 'folderRequest' &&
        row['threadId'] == null &&
        row['returnTicket'] == null &&
        (row['condition'] as Map)['kind'] == 'folderRequest' &&
        (row['trigger'] as Map)['facts'] is Map;
    if (!folderWake &&
        (row['automatic'] != null ||
            (row['condition'] as Map)['kind'] != 'wake')) {
      throw const FormatException('Invalid wake.');
    }
    // Wake is addressed to this host's Nipa; headless receivers reject it.
    if (!(mesh.hostConfiguration['roles'] as List? ?? []).contains('agent')) {
      throw const FormatException('This device does not host Nipa.');
    }
    return followups.acceptMeshDelivery(peer, payload);
  };
}
