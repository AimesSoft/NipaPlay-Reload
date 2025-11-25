import 'dart:typed_data';

import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/impl/smb1/server_message_block.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/crypto/crypto.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block.dart';
import 'package:smb_connect/src/connect/common/smb_signing_digest.dart';
import 'package:smb_connect/src/smb_constants.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/strings.dart';

import 'com/smb_com_read_and_x_response.dart';
import 'trans/nt/smb_com_nt_cancel.dart';

class SMB1SigningDigest implements SMBSigningDigest {
  late MessageDigest _digest;
  late Uint8List macSigningKey;
  bool bypass = false;
  int updates = 0;
  int signSequence = 0;

  SMB1SigningDigest(this.macSigningKey,
      {this.bypass = false, this.signSequence = 0}) {
    _digest = Crypto.getMD5();
  }

  /// Update digest with data
  void update(Uint8List input, int offset, int len) {
    if (len == 0) {
      return;

      /// CRITICAL */
    }
    _digest.update(input, offset, len);
    updates++;
  }

  Uint8List digest() {
    Uint8List b = _digest.digest();
    updates = 0;
    return b;
  }

  @override
  void sign(Uint8List data, int offset, int length,
      CommonServerMessageBlock request, CommonServerMessageBlock? response) {
    (request as ServerMessageBlock).setSignSeq(signSequence);
    if (response != null) {
      (response as ServerMessageBlock).setSignSeq(signSequence + 1);
    }

    try {
      update(macSigningKey, 0, macSigningKey.length);
      int index = offset + SmbConstants.SIGNATURE_OFFSET;
      for (int i = 0; i < 8; i++) {
        data[index + i] = 0;
      }
      SMBUtil.writeInt4(signSequence, data, index);
      update(data, offset, length);
      byteArrayCopy(
          src: digest(), srcOffset: 0, dst: data, dstOffset: index, length: 8);
      if (bypass) {
        bypass = false;
        byteArrayCopy(
          src: "BSRSPYL ".codeUnits.toUint8List(),
          srcOffset: 0,
          dst: data,
          dstOffset: index,
          length: 8,
        );
      }
    } catch (ex) {
      //Exception
      // log.error("Signature failed", ex);
    } finally {
      if (request is SmbComNtCancel) {
        signSequence++;
      } else {
        signSequence += 2;
      }
    }
  }

  @override
  bool verify(Uint8List data, int offset, int l, int extraPad,
      CommonServerMessageBlock m) {
    ServerMessageBlock msg = m as ServerMessageBlock;

    if ((msg.getFlags2() & SmbConstants.FLAGS2_SECURITY_SIGNATURES) == 0) {
      // signature requirements need to be checked somewhere else
      // log.warn("Expected signed response, but is not signed");
      return false;
    }

    update(macSigningKey, 0, macSigningKey.length);
    int index = offset;
    update(data, index, SmbConstants.SIGNATURE_OFFSET);
    index += SmbConstants.SIGNATURE_OFFSET;
    Uint8List sequence = Uint8List(8);
    SMBUtil.writeInt4(msg.getSignSeq(), sequence, 0);
    update(sequence, 0, sequence.length);
    index += 8;
    if (msg.getCommand() == SmbComConstants.SMB_COM_READ_ANDX) {
      /// SmbComReadAndXResponse reads directly from the stream into separate Uint8List b.
      SmbComReadAndXResponse raxr = msg as SmbComReadAndXResponse;
      int length = msg.getLength() - raxr.getDataLength();
      update(data, index, length - SmbConstants.SIGNATURE_OFFSET - 8);
      update(raxr.getData()!, raxr.getOffset(), raxr.getDataLength());
    } else {
      update(data, index, msg.getLength() - SmbConstants.SIGNATURE_OFFSET - 8);
    }
    Uint8List signature = digest();
    for (int i = 0; i < 8; i++) {
      if (signature[i] != data[offset + SmbConstants.SIGNATURE_OFFSET + i]) {
        return true;
      }
    }

    return false;
  }

  @override
  String toString() {
    return "MacSigningKey=${Hexdump.toHexStringBuff(macSigningKey)}";
  }

  ////
  static void writeUTime(
      Configuration cfg, int t, Uint8List dst, int dstIndex) {
    if (t == 0 || t == -1) {
      SMBUtil.writeInt4(0xFFFFFFFF, dst, dstIndex);
      return;
    }

    if (cfg.localTimezone.inDaylightTime(DateTime.now())) {
      // in DST
      if (cfg.localTimezone
          .inDaylightTime(DateTime.fromMillisecondsSinceEpoch(t))) {
        // t also in DST so no correction
      } else {
        // t not in DST so subtract 1 hour
        t -= 3600000;
      }
    } else {
      // not in DST
      if (cfg.localTimezone
          .inDaylightTime(DateTime.fromMillisecondsSinceEpoch(t))) {
        // t is in DST so add 1 hour
        t += 3600000;
      } else {
        // t isn't in DST either
      }
    }
    SMBUtil.writeInt4(t ~/ 1000, dst, dstIndex);
  }
}
