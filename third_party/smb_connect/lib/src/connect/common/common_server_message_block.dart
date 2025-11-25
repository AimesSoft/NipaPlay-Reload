import 'dart:typed_data';

import 'package:smb_connect/src/connect/common/smb_signing_digest.dart';
import 'package:smb_connect/src/connect/transport/message.dart';

import 'common_server_message_block_response.dart';

abstract class CommonServerMessageBlock extends Message {
  /// Decode message data from the given byte array
  int decode(Uint8List buffer, int bufferIndex);

  int encode(Uint8List dst, int dstIndex);

  void setDigest(SMBSigningDigest? digest);

  SMBSigningDigest? getDigest();

  CommonServerMessageBlockResponse? getResponse();

  void setResponse(CommonServerMessageBlockResponse msg);

  int getMid();

  void setMid(int mid);

  int getCommand();

  void setCommand(int command);

  void setUid(int uid);

  void setExtendedSecurity(bool extendedSecurity);

  void setSessionId(int sessionId);

  void reset();
}
