import 'dart:typed_data';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/impl/smb1/and_x_server_message_block.dart';
import 'package:smb_connect/src/connect/impl/smb1/server_message_block.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/smb_constants.dart';
import 'package:smb_connect/src/utils/strings.dart';

class SmbComOpenAndX extends AndXServerMessageBlock {
  // flags (not the same as flags constructor argument)
  static const int FLAGS_RETURN_ADDITIONAL_INFO = 0x01;
  static const int FLAGS_REQUEST_OPLOCK = 0x02;
  static const int FLAGS_REQUEST_BATCH_OPLOCK = 0x04;

  // Access Mode Encoding for desiredAccess
  static const int SHARING_COMPATIBILITY = 0x00;
  static const int SHARING_DENY_READ_WRITE_EXECUTE = 0x10;
  static const int SHARING_DENY_WRITE = 0x20;
  static const int SHARING_DENY_READ_EXECUTE = 0x30;
  static const int SHARING_DENY_NONE = 0x40;

  static const int DO_NOT_CACHE = 0x1000; // bit 12
  static const int WRITE_THROUGH = 0x4000; // bit 14

  static const int OPEN_FN_CREATE = 0x10;
  static const int OPEN_FN_FAIL_IF_EXISTS = 0x00;
  static const int OPEN_FN_OPEN = 0x01;
  static const int OPEN_FN_TRUNC = 0x02;

  int tflags = 0,
      desiredAccess = 0,
      searchAttributes = 0,
      fileAttributes = 0,
      creationTime = 0,
      openFunction = 0,
      allocationSize = 0;

  // flags is NOT the same as flags member

  SmbComOpenAndX(super.config, String fileName, int access, int shareAccess,
      int flags, this.fileAttributes, ServerMessageBlock? andx)
      : super(
            command: SmbComConstants.SMB_COM_OPEN_ANDX,
            name: fileName,
            andx: andx) {
    desiredAccess = access & 0x3;
    if (desiredAccess == 0x3) {
      desiredAccess = 0x2; /* Mmm, I thought 0x03 was RDWR */
    }

    // map shareAccess as far as we can
    if ((shareAccess & SmbConstants.FILE_SHARE_READ) != 0 &&
        (shareAccess & SmbConstants.FILE_SHARE_WRITE) != 0) {
      desiredAccess |= SHARING_DENY_NONE;
    } else if (shareAccess == SmbConstants.FILE_NO_SHARE) {
      desiredAccess |= SHARING_DENY_READ_WRITE_EXECUTE;
    } else if ((shareAccess & SmbConstants.FILE_SHARE_WRITE) == 0) {
      desiredAccess |= SHARING_DENY_WRITE;
    } else if ((shareAccess & SmbConstants.FILE_SHARE_READ) == 0) {
      desiredAccess |= SHARING_DENY_READ_EXECUTE;
    } else {
      // neither SHARE_READ nor SHARE_WRITE are set
      desiredAccess |= SHARING_DENY_READ_WRITE_EXECUTE;
    }

    desiredAccess &=
        ~0x1; // Win98 doesn't like GENERIC_READ ?! -- get Access Denied.

    // searchAttributes
    searchAttributes = SmbConstants.ATTR_DIRECTORY |
        SmbConstants.ATTR_HIDDEN |
        SmbConstants.ATTR_SYSTEM;

    // openFunction
    if ((flags & SmbConstants.O_TRUNC) == SmbConstants.O_TRUNC) {
      // truncate the file
      if ((flags & SmbConstants.O_CREAT) == SmbConstants.O_CREAT) {
        // create it if necessary
        openFunction = OPEN_FN_TRUNC | OPEN_FN_CREATE;
      } else {
        openFunction = OPEN_FN_TRUNC;
      }
    } else {
      // don't truncate the file
      if ((flags & SmbConstants.O_CREAT) == SmbConstants.O_CREAT) {
        // create it if necessary
        if ((flags & SmbConstants.O_EXCL) == SmbConstants.O_EXCL) {
          // fail if already exists
          openFunction = OPEN_FN_CREATE | OPEN_FN_FAIL_IF_EXISTS;
        } else {
          openFunction = OPEN_FN_CREATE | OPEN_FN_OPEN;
        }
      } else {
        openFunction = OPEN_FN_OPEN;
      }
    }
  }

  @override
  @protected
  int getBatchLimit(Configuration cfg, int cmd) {
    return cmd == SmbComConstants.SMB_COM_READ_ANDX
        ? cfg.getBatchLimit(cmd) //"OpenAndX.ReadAndX")
        : 0;
  }

  @override
  @protected
  int writeParameterWordsWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;

    SMBUtil.writeInt2(tflags, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt2(desiredAccess, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt2(searchAttributes, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt2(fileAttributes, dst, dstIndex);
    dstIndex += 2;
    creationTime = 0;
    SMBUtil.writeInt4(creationTime, dst, dstIndex);
    dstIndex += 4;
    SMBUtil.writeInt2(openFunction, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt4(allocationSize, dst, dstIndex);
    dstIndex += 4;
    for (int i = 0; i < 8; i++) {
      dst[dstIndex++] = 0x00;
    }

    return dstIndex - start;
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;

    if (isUseUnicode()) {
      dst[dstIndex++] = 0; //'\0';
    }
    dstIndex += writeString(path!, dst, dstIndex);

    return dstIndex - start;
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
    return "SmbComOpenAndX[${super.toString()},flags=0x${Hexdump.toHexString(tflags, 2)},desiredAccess=0x${Hexdump.toHexString(desiredAccess, 4)},searchAttributes=0x${Hexdump.toHexString(searchAttributes, 4)},fileAttributes=0x${Hexdump.toHexString(fileAttributes, 4)},creationTime=$DateTime.fromMillisecondsSinceEpoch(creationTime),openFunction=0x${Hexdump.toHexString(openFunction, 2)},allocationSize=$allocationSize,fileName=$path]";
  }
}
