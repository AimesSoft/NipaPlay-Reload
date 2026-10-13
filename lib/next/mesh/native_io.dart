import '../headless/native.dart';
import 'message.dart';

final class MeshNative {
  MeshNative({Future<void> Function()? initialize, HeadlessNative? bridge})
      : _initialize = initialize, bridge = bridge ?? HeadlessNative(HeadlessNative.defaultLibrary());
  final Future<void> Function()? _initialize;
  final HeadlessNative bridge;
  Future<void> ready() async { await _initialize?.call(); }
  Future<String> generateKey() async { await ready(); return (await bridge.call('mesh_generate_key')) as String; }
  Future<String> publicKey(String key) async => await bridge.call('mesh_public_key', {'private_key': key}) as String;
  Future<String> sign(String key, String message) async => await bridge.call('mesh_sign', {'private_key': key, 'message': message}) as String;
  Future<String> validate(String ca, String certificate, String key, String account) async =>
      await bridge.call('mesh_validate_certificate', {'ca': ca, 'certificate': certificate, 'private_key': key, 'account': account}) as String;
  Future<int> start({required String ca, required String certificate, required String key,
    required String account, required List<String> allowed, required String bind}) async =>
      await bridge.call('mesh_start', {'ca': ca, 'certificate': certificate, 'private_key': key,
        'account': account, 'allowed': allowed, 'bind': bind}) as int;
  Future<int> port(int id) async => await bridge.call('mesh_port', {'id': id}) as int;
  Future<void> update(int id, List<String> allowed) async { await bridge.call('mesh_update_devices', {'id': id, 'allowed': allowed}); }
  Future<void> stop(int id) async { await bridge.call('mesh_stop', {'id': id}); }
  Future<MeshMessage> next(int id) async {
    final event = await bridge.call('mesh_next', {'id': id}) as Map;
    return MeshMessage(BigInt.from(event['request_id'] as int), event['device_id'] as String, event['body'] as String);
  }
  Future<void> respond(int id, BigInt requestId, String body) async { await bridge.call('mesh_respond', {'id': id, 'request_id': requestId.toInt(), 'body': body}); }
  Future<String> send(int id, String host, int port, String peer, String body) async =>
      await bridge.call('mesh_send', {'id': id, 'host': host, 'port': port, 'device': peer, 'body': body}) as String;
}
