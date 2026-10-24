import 'package:nipa_harness/nipa_harness.dart';

import '../system/app_restart.dart';
import '../system/app_runtime.dart';
import 'classic_action.dart';

const _output = ObjectSchema({}, additionalProperties: true);

/// `app.runtime` and `app.restart`.
final class AppRuntimeCapability implements Capability {
  AppRuntimeCapability(this.facts, this.restart);
  final AppRuntimeFacts facts;
  final AppRestart restart;

  @override
  List<Action> get actions => [
        ClassicAction(
            const ActionSpec(
                id: 'app.runtime',
                title: 'Read how this device is set up',
                description:
                    'Read the non-secret facts of the settings only the user can change here. '
                    'remoteAccess: serviceRunning, port, autoStart, ipv6, receiverEnabled, trustedDeviceCount (a count, no identities or tokens), lastStartFailed. '
                    'mesh: joined, enabled, status, issuerAvailable, deviceName, coordinator (address without credentials), port, loopbackOnly, broadcastDiscovery, manualAddresses, fileProxyPort, remoteProgramsAllowed. '
                    'agent: endpointEnabled, programExecutionAllowed. '
                    'runtime: selected (kind dsh or codex: the environment or lab profile, else the choice in settings, else dsh; dshVersion; problem when the selection named by the environment is invalid), running (null when no conversation host is running; otherwise available, runtime, model, provider, busy, problem as a short sentence), codex (source managed/path/specified, managed version and installed, mirror), dsh (whether NipaPlay has fetched DeepSeek Harness, and its version). '
                    'model: source nipaplay (provider, baseUrl without credentials, model, api responses or chat, keyConfigured) or codex (codexConfigPresent, and the model and provider its config names). '
                    'Keys, tokens, trusted-device identities and credentials in addresses are never returned; none of these can be changed through Actions. '
                    'keyConfigured is null with keyConfiguredReason when the host cannot read it (a lab profile keeps the key in memory).',
                effect: Effect.read,
                input: ObjectSchema({}),
                output: _output),
            (_, __) => facts.read()),
        ClassicAction(
            const ActionSpec(
                id: 'app.restart',
                title: 'Restart the connected application',
                description:
                    'macOS only. Starts a detached helper, then schedules Classic application shutdown one second after returning a receipt (as app.quit does). '
                    'The helper waits up to 60 seconds for this process to exit, then starts the same executable with the arguments this process was started with and its environment (a lab profile NIPAPLAY_PROFILE comes back as itself); if this process has not exited by then nothing is started. '
                    'This ends the exact instance serving this Agent connection, including its endpoint; subsequent calls fail until the new process is up. The new process has a new processId and starts its own endpoint; reconnect and read app.instance. '
                    'Playback progress and Classic exit cleanup run normally. The receipt (scheduled, processId, delayMs, executablePath, arguments) is journaled before shutdown and is not proof that the new process started. '
                    'Settings whose apply is restart_app take effect in the new process. '
                    'Other platforms fail with unavailable: no relaunch is known to start this installation. A failure to read the arguments of this process or to start the helper also fails with unavailable and restarts nothing. No user confirmation is needed.',
                effect: Effect.write,
                input: ObjectSchema({}),
                output: _output),
            (_, __) => restart.restart()),
      ];
}
