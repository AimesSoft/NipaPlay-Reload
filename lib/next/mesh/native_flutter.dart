import 'package:nipaplay/src/rust/api/mesh.dart' as ffi;
import 'package:nipaplay/src/rust/rust_init.dart';
import 'message.dart';

final class MeshNative {
  MeshNative({Future<void> Function()? initialize})
      : _initialize = initialize ?? ensureRustInitialized;
  final Future<void> Function() _initialize;
  Future<void> ready() => _initialize();
  Future<String> generateKey() async {
    await ready();
    return ffi.meshGenerateKey();
  }
  Future<String> publicKey(String key) => ffi.meshPublicKey(privateKey: key);
  Future<String> sign(String key, String message) => ffi.meshSign(privateKey: key, message: message);
  Future<String> validate(String ca, String certificate, String key, String account) =>
      ffi.meshValidateCertificate(ca: ca, certificate: certificate, privateKey: key, account: account);
  Future<int> start({required String ca, required String certificate,
    required String key, required String account, required List<String> allowed,
    required String bind}) => ffi.meshStart(ca: ca, certificate: certificate,
      privateKey: key, account: account, allowed: allowed, bind: bind);
  Future<int> port(int id) => ffi.meshPort(id: id);
  Future<void> update(int id, List<String> allowed) => ffi.meshUpdateDevices(id: id, allowed: allowed);
  Future<void> stop(int id) => ffi.meshStop(id: id);
  Future<MeshMessage> next(int id) async {
    final event = await ffi.meshNext(id: id);
    return MeshMessage(event.requestId, event.deviceId, event.body);
  }
  Future<void> respond(int id, BigInt requestId, String body) => ffi.meshRespond(id: id, requestId: requestId, body: body);
  Future<String> send(int id, String host, int port, String peer, String body) =>
      ffi.meshSend(id: id, host: host, port: port, device: peer, body: body);
}
