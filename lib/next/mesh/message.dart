final class MeshMessage {
  const MeshMessage(this.requestId, this.deviceId, this.body);
  final BigInt requestId;
  final String deviceId, body;
}
