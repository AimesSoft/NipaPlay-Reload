import 'dart:typed_data';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/impl/smb1/server_message_block.dart';
import 'package:smb_connect/src/connect/common/smb_negotiation_request.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/strings.dart';

class SmbComNegotiate extends ServerMessageBlock
    implements SmbNegotiationRequest {
  final bool signingEnforced;
  late final List<String> dialects;

  SmbComNegotiate(Configuration config, this.signingEnforced)
      : super(config, command: SmbComConstants.SMB_COM_NEGOTIATE) {
    setFlags2(config.flags2);

    if (config.minimumVersion.isSMB2()) {
      dialects = ["SMB 2.???", "SMB 2.002"];
    } else if (config.maximumVersion.isSMB2()) {
      dialects = ["NT LM 0.12", "SMB 2.???", "SMB 2.002"];
    } else {
      dialects = ["NT LM 0.12"];
    }
  }

  @override
  bool isSigningEnforced() {
    return signingEnforced;
  }

  @override
  @protected
  int writeParameterWordsWireFormat(Uint8List dst, int dstIndex) {
    return 0;
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    List<int> bos = [];

    for (String dialect in dialects) {
      bos.add(0x02);
      bos.addAll(dialect.getASCIIBytes());
      bos.add(0x0);
    }

    byteArrayCopy(
        src: bos.toUint8List(),
        srcOffset: 0,
        dst: dst,
        dstOffset: dstIndex,
        length: bos.length);
    return bos.length;
  }

  @override
  @protected
  int readParameterWordsWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }

  @override
  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }

  @override
  String toString() {
    return "SmbComNegotiate[${super.toString()},wordCount=$wordCount,dialects=NT LM 0.12]";
  }
}
