import 'dart:convert';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/services/remote_control_access_guard_service.dart';
import 'package:nipaplay/services/remote_control_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/chat_host.dart';
import '../chat/dsh_runtime.dart';
import '../harness_redaction.dart';
import '../mesh/runtime.dart';
import '../platform/lab_profile.dart';
import '../programs/runtime.dart';
import '../runtime/codex_manifest.dart';
import '../settings/consent.dart' show settingWords;
import '../settings/host_settings_service.dart';

/// Non-secret facts of how this device is set up: remote access, the mesh,
/// the model and the runtime Nipa thinks with. These are the settings only
/// the person at the device may change; here they can be read, never changed.
/// Keys, tokens, trusted-device identities and credentials in addresses are
/// never part of it.
final class AppRuntimeFacts {
  AppRuntimeFacts(
      {required this.root,
      required this.mesh,
      required this.programs,
      required this.vault,
      required this.chat,
      required this.codexHome,
      this.remoteAccess,
      Map<String, String>? environment,
      this.managedModelByDefault = true})
      : environment = environment ?? Platform.environment;

  /// Next's data root: model.json, mesh.json and codex-runtime/ live here.
  final Directory root;
  final MeshRuntime mesh;
  final ProgramRuntime programs;
  final CredentialVault vault;

  /// The running conversation host, when there is one.
  final ChatHost? Function() chat;
  final Directory codexHome;
  final Map<String, String> environment;

  /// Whether a model nobody has chosen yet is the one set up in NipaPlay
  /// (desktop) rather than the Codex configuration on the computer.
  final bool managedModelByDefault;

  /// Replaces the Classic remote access service reader (tests).
  final Future<JsonMap> Function()? remoteAccess;

  Future<JsonMap> _file(String name) async {
    final file = File('${root.path}/$name');
    try {
      return await file.exists()
          ? Map<String, Object?>.from(jsonDecode(await file.readAsString()) as Map)
          : {};
    } on FormatException {
      return {};
    }
  }

  Future<JsonMap> _remoteAccess() async {
    if (remoteAccess != null) return remoteAccess!();
    final web = ServiceProvider.webServer;
    final guard = RemoteControlAccessGuardService.instance;
    await guard.loadTrustedDevices();
    return {
      'serviceRunning': web.isRunning,
      'port': web.port,
      'autoStart': web.autoStart,
      'ipv6': web.ipv6Enabled,
      'receiverEnabled': await RemoteControlSettings.isReceiverEnabled(),
      'trustedDeviceCount': (await guard.getTrustedDevices()).length,
      'lastStartFailed': web.lastStartErrorMessage != null,
    };
  }

  Future<JsonMap> _mesh() async {
    final file = await _file('mesh.json');
    String? address(Object? entry) {
      if (entry is! Map || entry['host'] is! String) return null;
      final host = entry['host'] as String;
      return '${host.contains(':') ? '[$host]' : host}:${entry['port']}';
    }

    final coordinator = file['coordinator'];
    return {
      'joined': mesh.status == 'online',
      'enabled': file['enabled'] == true,
      'status': mesh.status,
      'issuerAvailable': mesh.issuerAvailable,
      'deviceName': file['name'],
      'coordinator': coordinator is String && coordinator.isNotEmpty
          ? settingWords(coordinator)
          : null,
      'port': file['port'],
      'loopbackOnly': file['loopbackOnly'] == true,
      'broadcastDiscovery': file['broadcastDiscovery'] as bool? ?? true,
      'manualAddresses': [
        for (final entry in file['addresses'] as List? ?? const [])
          if (address(entry) case final text?) text
      ],
      'fileProxyPort': file['fileProxyPort'],
      'remoteProgramsAllowed': programs.enabled,
    };
  }

  Future<JsonMap> _selected() async {
    final lab = LabProfile.active ? Directory(LabProfile.root) : null;
    try {
      final dsh = DshRuntime.select(environment, labRoot: lab);
      return dsh == null
          ? {'kind': 'codex'}
          : {'kind': 'dsh', 'dshVersion': dsh.version};
    } on StateError catch (error) {
      return {'kind': null, 'problem': redactHarnessText(error.message)};
    }
  }

  Future<JsonMap> _codex() async {
    final directory = Directory('${root.path}/codex-runtime');
    final settings = File('${directory.path}/settings.json');
    final choice = await settings.exists()
        ? Map<String, Object?>.from(jsonDecode(await settings.readAsString()) as Map)
        : <String, Object?>{};
    final source = choice['source'] as String? ?? 'managed';
    final mirror = choice['mirror'] as String?;
    return {
      'source': source,
      if (source == 'managed') ...{
        'version': codexVersion,
        'installed': await File(
                '${directory.path}/$codexVersion/installed.json')
            .exists(),
      },
      'mirror': mirror == null || mirror.isEmpty ? null : settingWords(mirror),
    };
  }

  Future<JsonMap> _model() async {
    final value = await _file('model.json');
    final managed = value['source'] == 'nipaplay' ||
        (value['source'] == null && managedModelByDefault);
    final config = File('${codexHome.path}/config.toml');
    final codexConfig = await config.exists();
    Object? codexModel, codexProvider;
    if (codexConfig) {
      try {
        final toml = readCodexToml(await config.readAsString());
        codexModel = toml['model'];
        codexProvider = toml['model_provider'];
      } catch (_) {
        // An unreadable Codex file is reported as present without a model.
      }
    }
    bool? keyConfigured;
    String? keyUnknown;
    if (managed) {
      if (LabProfile.active) {
        keyUnknown = 'A lab profile keeps the key in memory, which is not readable here.';
      } else if (value['provider'] != null && value['baseUrl'] != null) {
        try {
          keyConfigured =
              (await vault.read(HostSettingsService.modelKey(root, value)))
                      ?.isNotEmpty ==
                  true;
        } on StateError {
          keyUnknown = 'The host vault is unavailable.';
        }
      } else {
        keyConfigured = false;
      }
    }
    return {
      'source': managed ? 'nipaplay' : 'codex',
      if (managed) ...{
        'provider': value['provider'],
        'baseUrl': value['baseUrl'] == null ? null : settingWords(value['baseUrl']),
        'model': value['model'],
        'keyConfigured': keyConfigured,
        if (keyUnknown != null) 'keyConfiguredReason': keyUnknown,
      } else ...{
        'codexConfigPresent': codexConfig,
        'model': codexModel,
        'provider': codexProvider,
      },
    };
  }

  JsonMap? _live() {
    final host = chat();
    if (host == null) return null;
    final error = host.liveness.latestError;
    return {
      'available': host.available,
      'runtime': host.dsh == null ? 'codex' : 'dsh',
      'model': host.model,
      'provider': host.provider,
      'busy': host.busy,
      'problem': error == null ? null : modelFailureMessage(error),
    };
  }

  Future<JsonMap> read() async {
    final prefs = await SharedPreferences.getInstance();
    final facts = <String, Object?>{
      'observedAt': DateTime.now().toUtc().toIso8601String(),
      'remoteAccess': await _remoteAccess(),
      'mesh': await _mesh(),
      'agent': {
        'endpointEnabled':
            prefs.getBool(SettingsKeys.labsEnableAgentEndpoint) ?? false,
        'programExecutionAllowed': programs.enabled,
      },
      'runtime': {
        'selected': await _selected(),
        'running': _live(),
        'codex': await _codex(),
      },
      'model': await _model(),
    };
    return redactHarnessJson(facts) as JsonMap;
  }
}
