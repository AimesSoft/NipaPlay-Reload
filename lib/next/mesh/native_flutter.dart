import 'package:nipaplay/src/rust/api/mesh.dart' as ffi;
import 'package:nipaplay/src/rust/rust_init.dart';
import 'message.dart';
import 'dart:io';
import 'native_io.dart' as television;

final class MeshNative {
  MeshNative({Future<void> Function()? initialize})
      : _initialize = initialize ?? ensureRustInitialized,
        _television = Platform.operatingSystem == 'tvos'
            ? television.MeshNative(initialize: initialize)
            : null;
  final Future<void> Function() _initialize;
  final television.MeshNative? _television;
  Future<void> ready() => _television?.ready() ?? _initialize();
  Future<String> generateKey() async {
    if (_television case final native?) return native.generateKey();
    await ready();
    return ffi.meshGenerateKey();
  }

  Future<String> publicKey(String key) =>
      _television?.publicKey(key) ?? ffi.meshPublicKey(privateKey: key);
  Future<String> sign(String key, String message) =>
      _television?.sign(key, message) ??
      ffi.meshSign(privateKey: key, message: message);
  Future<String> validate(
          String ca, String certificate, String key, String account) =>
      _television?.validate(ca, certificate, key, account) ??
      ffi.meshValidateCertificate(
          ca: ca, certificate: certificate, privateKey: key, account: account);
  Future<int> start(
          {required String ca,
          required String certificate,
          required String key,
          required String account,
          required List<String> allowed,
          required String bind}) =>
      _television?.start(
          ca: ca,
          certificate: certificate,
          key: key,
          account: account,
          allowed: allowed,
          bind: bind) ??
      ffi.meshStart(
          ca: ca,
          certificate: certificate,
          privateKey: key,
          account: account,
          allowed: allowed,
          bind: bind);
  Future<int> port(int id) => _television?.port(id) ?? ffi.meshPort(id: id);
  Future<void> update(int id, List<String> allowed) =>
      _television?.update(id, allowed) ??
      ffi.meshUpdateDevices(id: id, allowed: allowed);
  Future<void> stop(int id) => _television?.stop(id) ?? ffi.meshStop(id: id);
  Future<MeshMessage> next(int id) async {
    if (_television case final native?) return native.next(id);
    final event = await ffi.meshNext(id: id);
    return MeshMessage(event.requestId, event.deviceId, event.body);
  }

  Future<void> respond(int id, BigInt requestId, String body) =>
      _television?.respond(id, requestId, body) ??
      ffi.meshRespond(id: id, requestId: requestId, body: body);
  Future<String> send(
          int id, String host, int port, String peer, String body) =>
      _television?.send(id, host, port, peer, body) ??
      ffi.meshSend(id: id, host: host, port: port, device: peer, body: body);
}
