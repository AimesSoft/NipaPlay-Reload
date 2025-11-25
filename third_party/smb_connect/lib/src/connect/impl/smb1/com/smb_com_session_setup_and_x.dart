import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/impl/smb1/and_x_server_message_block.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/server_data.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_negotiate_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/server_message_block.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/smb/ntlm_password_authenticator.dart';
import 'package:smb_connect/src/smb_constants.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/extensions.dart';

class SmbComSessionSetupAndX extends AndXServerMessageBlock {
  Uint8List? _lmHash, _ntHash, _blob;
  String? _accountName, _primaryDomain;
  SmbComNegotiateResponse negotiated;
  int _capabilities = 0;

  SmbComSessionSetupAndX(Configuration config, this.negotiated,
      ServerMessageBlock? andx, Object cred)
      : super(config,
            command: SmbComConstants.SMB_COM_SESSION_SETUP_ANDX, andx: andx) {
    _capabilities = negotiated.capabilities;
    ServerData server = negotiated.getServerData();
    if (server.security == SmbConstants.SECURITY_USER) {
      if (cred is NtlmPasswordAuthenticator) {
        NtlmPasswordAuthenticator a = cred;
        if (a.isAnonymous()) {
          _lmHash = Uint8List(0);
          _ntHash = Uint8List(0);
          _capabilities &= ~SmbConstants.CAP_EXTENDED_SECURITY;
          if (a.isGuest()) {
            _accountName = a.getUsername();
            if (isUseUnicode()) {
              _accountName = _accountName?.toUpperCase();
            }
            _primaryDomain = a.getUserDomain().toUpperCase(); // ?? "?";
          } else {
            _accountName = "";
            _primaryDomain = "";
          }
        } else {
          _accountName = a.getUsername();
          if (isUseUnicode()) {
            _accountName = _accountName?.toUpperCase();
          }
          _primaryDomain = a.getUserDomain().toUpperCase(); // ?? "?";
          if (server.encryptedPasswords) {
            _lmHash = a.getAnsiHash(config, server.encryptionKey!);
            _ntHash = a.getUnicodeHash(config, server.encryptionKey!);
            // prohibit HTTP auth attempts for the null session
            if ((_lmHash == null || _lmHash!.isEmpty) &&
                (_ntHash == null || _ntHash!.isEmpty)) {
              throw SmbRuntimeException("Null setup prohibited.");
            }
          } else {
            // plain text
            String password = a.getPassword();
            _lmHash = Uint8List((password.length + 1) * 2);
            _ntHash = Uint8List(0);
            writeString(password, _lmHash!, 0);
          }
        }
      } else if (cred is Uint8List) {
        _blob = cred;
      } else {
        throw SmbException(
            "Unsupported credential type ${cred.runtimeType.toString()}"); // ?? "NULL"
      }
    } else if (server.security == SmbConstants.SECURITY_SHARE) {
      if (cred is NtlmPasswordAuthenticator) {
        NtlmPasswordAuthenticator a = cred;
        _lmHash = Uint8List(0);
        _ntHash = Uint8List(0);
        if (!a.isAnonymous()) {
          _accountName = a.getUsername();
          if (isUseUnicode()) {
            _accountName = _accountName?.toUpperCase();
          }
          _primaryDomain = a.getUserDomain().toUpperCase(); // ?? "?";
        } else {
          _accountName = "";
          _primaryDomain = "";
        }
      } else {
        throw SmbException("Unsupported credential type");
      }
    } else {
      throw SmbException("Unsupported");
    }
  }

  @override
  @protected
  int getBatchLimit(Configuration cfg, int cmd) {
    return cmd == SmbComConstants.SMB_COM_TREE_CONNECT_ANDX
        ? cfg.getBatchLimit(cmd) //"SessionSetupAndX.TreeConnectAndX")
        : 0;
  }

  @override
  @protected
  int writeParameterWordsWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;

    SMBUtil.writeInt2(negotiated.getNegotiatedSendBufferSize(), dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt2(negotiated.getNegotiatedMpxCount(), dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt2(Configuration.vcNumber, dst, dstIndex);
    dstIndex += 2;
    SMBUtil.writeInt4(negotiated.getNegotiatedSessionKey(), dst, dstIndex);
    dstIndex += 4;
    if (_blob != null) {
      SMBUtil.writeInt2(_blob!.length, dst, dstIndex);
      dstIndex += 2;
    } else {
      SMBUtil.writeInt2(_lmHash!.length, dst, dstIndex);
      dstIndex += 2;
      SMBUtil.writeInt2(_ntHash!.length, dst, dstIndex);
      dstIndex += 2;
    }
    dst[dstIndex++] = 0x00;
    dst[dstIndex++] = 0x00;
    dst[dstIndex++] = 0x00;
    dst[dstIndex++] = 0x00;
    SMBUtil.writeInt4(_capabilities, dst, dstIndex);
    dstIndex += 4;

    return dstIndex - start;
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;

    if (_blob != null) {
      byteArrayCopy(
          src: _blob!,
          srcOffset: 0,
          dst: dst,
          dstOffset: dstIndex,
          length: _blob!.length);
      dstIndex += _blob!.length;
    } else {
      byteArrayCopy(
          src: _lmHash!,
          srcOffset: 0,
          dst: dst,
          dstOffset: dstIndex,
          length: _lmHash!.length);
      dstIndex += _lmHash!.length;
      byteArrayCopy(
          src: _ntHash!,
          srcOffset: 0,
          dst: dst,
          dstOffset: dstIndex,
          length: _ntHash!.length);
      dstIndex += _ntHash!.length;

      dstIndex += writeString(_accountName!, dst, dstIndex);
      dstIndex += writeString(_primaryDomain!, dst, dstIndex);
    }
    dstIndex += writeString(config.nativeOs, dst, dstIndex);
    dstIndex += writeString(config.nativeLanman, dst, dstIndex);

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
    return "SmbComSessionSetupAndX[${super.toString()},snd_buf_size=${negotiated.getNegotiatedSendBufferSize()},maxMpxCount=${negotiated.getNegotiatedMpxCount()},sessionKey=${negotiated.getNegotiatedSessionKey()},lmHash.length=${_lmHash?.length ?? 0},ntHash.length=${(_ntHash?.length ?? 0)},capabilities=$_capabilities,accountName=$_accountName,primaryDomain=$_primaryDomain,NATIVE_OS=${config.nativeOs},NATIVE_LANMAN=${config.nativeLanman}]";
  }
}
