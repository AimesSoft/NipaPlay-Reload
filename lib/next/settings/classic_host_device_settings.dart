import 'package:nipa_harness/nipa_harness.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/security/secret_redactor.dart';
import 'package:nipaplay/services/remote_control_access_guard_service.dart';
import 'package:nipaplay/services/remote_control_settings.dart';
import 'package:nipaplay/services/web_server_service.dart';
import '../ui_data/host_settings.dart';

/// Host UI only: delegates to the same receiver and credential stores as Classic.
final class ClassicHostDeviceSettings implements NextHostDeviceSettings {
  ClassicHostDeviceSettings(
      {required this.vault,
      required this.webServer,
      required this.spoilerChanged});
  final CredentialVault vault;
  final WebServerService webServer;
  final Future<void> Function(String) spoilerChanged;
  static const _tmdb = CredentialRef('metadata', 'tmdb');

  @override
  Future<UiHostKeys> keys() async => UiHostKeys(
      spoilerAi: (await CredentialStore.instance.read(
                  await SharedPreferences.getInstance(),
                  SettingsKeys.spoilerAiApiKey))
              ?.isNotEmpty ==
          true,
      tmdb: (await vault.read(_tmdb))?.isNotEmpty == true);

  @override
  Future<void> setKeys({String? spoilerAi, String? tmdb}) async {
    if (spoilerAi != null) {
      final key = spoilerAi.trim();
      await spoilerChanged(key);
      final saved = await CredentialStore.instance.read(
          await SharedPreferences.getInstance(), SettingsKeys.spoilerAiApiKey);
      if (saved != key) throw StateError('vault_readback_mismatch');
    }
    if (tmdb != null) {
      final key = tmdb.trim();
      if (key.isEmpty) {
        await vault.delete(_tmdb);
      } else {
        SecretRedactor.remember(_tmdb, key);
        await vault.write(_tmdb, key);
        if (await vault.read(_tmdb) != key)
          throw StateError('vault_readback_mismatch');
      }
    }
  }

  @override
  Future<UiRemoteAccess> remoteAccess() async {
    final guard = RemoteControlAccessGuardService.instance;
    await guard.loadTrustedDevices();
    return UiRemoteAccess(
        running: webServer.isRunning,
        autoStart: webServer.autoStart,
        port: webServer.port,
        ipv6: webServer.ipv6Enabled,
        receiverEnabled: await RemoteControlSettings.isReceiverEnabled(),
        devices: [
          for (final d in await guard.getTrustedDevices())
            UiRemoteDevice(
                clientKey: d['clientKey'] as String,
                name: d['clientName'] as String? ?? '远程设备')
        ],
        problem: webServer.lastStartErrorMessage == null ? null : '远程访问服务未能启动');
  }

  @override
  Future<void> setRemoteAccess(UiRemoteAccessChoice choice) async {
    if (choice.port < 1 || choice.port > 65535) {
      throw const Failure(FailureCode.invalidInput, 'Port must be 1–65535.');
    }
    // Quiesce before changing listeners so one host choice causes one restart.
    if (webServer.isRunning &&
        (!choice.running ||
            webServer.port != choice.port ||
            webServer.ipv6Enabled != choice.ipv6)) await webServer.stopServer();
    await webServer.setPort(choice.port);
    await webServer.setAutoStart(choice.autoStart);
    await webServer.setIpv6Enabled(choice.ipv6);
    await RemoteControlSettings.setReceiverEnabled(choice.receiverEnabled);
    if (choice.running &&
        !webServer.isRunning &&
        !await webServer.startServer()) {
      throw const Failure(FailureCode.unavailable, '远程访问服务未能启动');
    }
  }

  @override
  Future<void> forgetRemoteDevice(String clientKey) =>
      RemoteControlAccessGuardService.instance.removeTrustedDevice(clientKey);
}
