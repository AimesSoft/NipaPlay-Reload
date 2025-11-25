import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/credentials.dart';
import 'package:smb_connect/src/connect/impl/smb1/and_x_server_message_block.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/server_data.dart';
import 'package:smb_connect/src/connect/impl/smb1/server_message_block.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/smb/ntlm_password_authenticator.dart';
import 'package:smb_connect/src/smb_constants.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/strings.dart';

class SmbComTreeConnectAndX extends AndXServerMessageBlock {
  final Credentials _credentials;
  final bool _disconnectTid;
  String? service;
  ServerData server;
  Uint8List? _password;
  int _passwordLength = 0;

  SmbComTreeConnectAndX(this._credentials, super.config, this.server,
      String path, this.service, ServerMessageBlock? andx,
      [this._disconnectTid = false])
      : super(command: SmbComConstants.SMB_COM_TREE_CONNECT_ANDX, andx: andx) {
    this.path = path;
  }

  @override
  @protected
  int getBatchLimit(Configuration cfg, int cmd) {
    int c = cmd & 0xFF;
    switch (c) {
      case SmbComConstants.SMB_COM_CHECK_DIRECTORY:
        return cfg.getBatchLimit(c); //"TreeConnectAndX.CheckDirectory");
      case SmbComConstants.SMB_COM_CREATE_DIRECTORY:
        return cfg.getBatchLimit(c); //"TreeConnectAndX.CreateDirectory");
      case SmbComConstants.SMB_COM_DELETE:
        return cfg.getBatchLimit(c); //"TreeConnectAndX.Delete");
      case SmbComConstants.SMB_COM_DELETE_DIRECTORY:
        return cfg.getBatchLimit(c); //"TreeConnectAndX.DeleteDirectory");
      case SmbComConstants.SMB_COM_OPEN_ANDX:
        return cfg.getBatchLimit(c); //"TreeConnectAndX.OpenAndX");
      case SmbComConstants.SMB_COM_RENAME:
        return cfg.getBatchLimit(c); //"TreeConnectAndX.Rename");
      case SmbComConstants.SMB_COM_TRANSACTION:
        return cfg.getBatchLimit(c); //"TreeConnectAndX.Transaction");
      case SmbComConstants.SMB_COM_QUERY_INFORMATION:
        return cfg.getBatchLimit(c); //"TreeConnectAndX.QueryInformation");
    }
    return 0;
  }

  @override
  @protected
  int writeParameterWordsWireFormat(Uint8List dst, int dstIndex) {
    final credentials = _credentials; //ctx.getCredentials();
    if (server.security == SmbConstants.SECURITY_SHARE &&
        credentials is NtlmPasswordAuthenticator) {
      // NtlmPasswordAuthenticator pwAuth =
      //     ctx.getCredentials() as NtlmPasswordAuthenticator;
      // if (isExternalAuth(pwAuth)) {
      //   _passwordLength = 1;
      // } else
      if (server.encryptedPasswords) {
        // encrypted
        try {
          _password = credentials.getAnsiHash(config, server.encryptionKey!);
        } catch (e) {
          //GeneralSecurityException
          throw SmbRuntimeException("Failed to encrypt password"); //, e);
        }
        _passwordLength = _password?.length ?? 0;
      } else {
        // plain text
        _password = Uint8List((credentials.getPassword().length + 1) * 2);
        _passwordLength = writeString(credentials.getPassword(), _password!, 0);
      }
    } else {
      // no password in tree connect
      _passwordLength = 1;
    }

    dst[dstIndex++] = _disconnectTid ? 0x01 : 0x00;
    dst[dstIndex++] = 0x00;
    SMBUtil.writeInt2(_passwordLength, dst, dstIndex);
    return 4;
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;
    var credentials = _credentials;
    if (server.security == SmbConstants.SECURITY_SHARE &&
        credentials is NtlmPasswordAuthenticator) {
      // NtlmPasswordAuthenticator pwAuth =
      //     ctx.getCredentials() as NtlmPasswordAuthenticator;
      // if (isExternalAuth(pwAuth)) {
      //   dst[dstIndex++] = 0x00;
      // } else {
      byteArrayCopy(
          src: _password!,
          srcOffset: 0,
          dst: dst,
          dstOffset: dstIndex,
          length: _passwordLength);
      dstIndex += _passwordLength;
      // }
    } else {
      // no password in tree connect
      dst[dstIndex++] = 0x00;
    }
    dstIndex += writeString(path!, dst, dstIndex);
    try {
      byteArrayCopy(
          src: service.getASCIIBytes(),
          srcOffset: 0,
          dst: dst,
          dstOffset: dstIndex,
          length: service!.length);
    } catch (uee) {
      //UnsupportedEncodingException
      return 0;
    }
    dstIndex += service!.length;
    dst[dstIndex++] = 0; //'\0';

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
    return "SmbComTreeConnectAndX[${super.toString()},disconnectTid=$_disconnectTid,passwordLength=$_passwordLength,password=${Hexdump.toHexStringBuff(_password)},path=$path,service=$service]";
  }
}
