import 'package:nipa_harness/nipa_harness.dart';

import '../followups/service.dart';
import 'delegation.dart';
import 'delegation_host.dart';
import 'runtime.dart';

/// The sending side of delegation on this device (its task executor). Created
/// before the task engine, which runs it; [attachMeshDelegation] completes it.
MeshDelegations createMeshDelegations(MeshRuntime mesh) => MeshDelegations(
    call: mesh.rpc,
    devices: () => mesh.cachedDevices,
    selfDeviceId: () => mesh.identity?.deviceId);

/// Completes the sending side and creates the receiving side: other devices'
/// Nipa can hand this device's Nipa a task while she runs here.
AgentDelegations attachMeshDelegation(MeshRuntime mesh,
    MeshDelegations sender, TaskEngine engine, Followups followups) {
  sender
    ..engine = engine
    ..followups = followups;
  final receiver = AgentDelegations(
      root: mesh.root,
      chat: () {
        final host = followups.chatHost;
        return host != null && host.available ? host : null;
      },
      unavailableReason: () => followups.unavailableReason,
      deviceName: mesh.deviceName,
      record: (peer, title, facts) => followups.discover({
            'title': title,
            'source': 'mesh/agent',
            'facts': facts,
          }, Invocation(origin: 'mesh:$peer')),
      startedTasks: (threadId, since) async => [
            for (final job in await engine.listRecent(limit: 100))
              if (job.origin?['threadId'] == threadId &&
                  !job.createdAt.isBefore(since.toUtc()))
                {
                  'jobId': job.jobId,
                  'type': job.type,
                  'title': job.title,
                  'state': job.state.wireName,
                }
          ]);
  mesh.agentRequest = receiver.handle;
  followups.chatListeners.add(receiver.attach);
  return receiver;
}
