import 'package:nipa_harness/nipa_harness.dart';
import '../media/classic_metadata_port.dart';
import '../mesh/device_source.dart';
import '../repository_location.dart';
import '../danmaku/service.dart';
import '../danmaku/source.dart';
import '../../security/credential_vault.dart';

final class HeadlessRepository implements RepositoryLocation {
  const HeadlessRepository(this.path);
  @override
  final String path;
  @override
  Future<void> get ready => Future.value();
}

final class NoClassic implements ClassicMetadataPort {
  @override
  Future<List<JsonMap>> history() async => [];
  @override
  Future<void> apply(String locator, JsonMap fields) async =>
      throw const Failure(FailureCode.unavailable,
          'Classic history projection is unavailable in the headless host.');
  @override
  Future<bool> verify(String locator, JsonMap fields) async => false;
}

final class NoMesh implements MeshDeviceSource {
  @override
  List<JsonMap> get cachedDevices => [];
}

final class NoPlayer implements DanmakuPlayerPort {
  @override
  DanmakuPlaybackTarget? get target => null;
  @override
  Set<String> get managedTracks => {};
  @override
  JsonMap? loaded(String bindingId) => null;
  @override
  bool install(DanmakuPlaybackTarget target, JsonMap binding,
          List<DanmakuEntry> entries,
          {int startMs = 0, int? endMs}) =>
      false;
  @override
  void remove(String bindingId) {}
}

final class NoVault implements CredentialVault {
  @override
  Future<String?> read(CredentialRef ref) async => null;
  @override
  Future<void> write(CredentialRef ref, String secret) async =>
      throw UnsupportedError(
          'Headless credential enrollment is not implemented.');
  @override
  Future<void> delete(CredentialRef ref) async => throw UnsupportedError(
      'Headless credential enrollment is not implemented.');
}

final class HeadlessCapabilities implements Capability {
  HeadlessCapabilities(Iterable<Capability> capabilities)
      : actions = [
          for (final c in capabilities)
            for (final a in c.actions)
              if (!{
                    'download.delete',
                    'media.library.import_history',
                    'agent.dispatch',
                    'agent.dispatch.report',
                    'chat.turn.process'
                  }.contains(a.spec.id) &&
                  !a.spec.id.startsWith('chat.session.'))
                a
        ];
  @override
  final List<Action> actions;
}
