import 'dart:typed_data';

import 'common_server_message_block.dart';

abstract class SMBSigningDigest {
  ///
  /// Performs MAC signing of the SMB. This is done as follows.
  /// The signature field of the SMB is overwritten with the sequence number;
  /// The MD5 digest of the MAC signing key + the entire SMB is taken;
  /// The first 8 ints of this are placed in the signature field.
  ///
  void sign(Uint8List data, int offset, int length,
      CommonServerMessageBlock request, CommonServerMessageBlock response);

  ///
  /// Performs MAC signature verification. This calculates the signature
  /// of the SMB and compares it to the signature field on the SMB itself.
  ///
  bool verify(Uint8List data, int offset, int length, int extraPad,
      CommonServerMessageBlock msg);
}
