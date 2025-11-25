import 'dart:math';
import 'dart:typed_data';

import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/dialect_version.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block.dart';
import 'package:smb_connect/src/connect/impl/smb1/server_message_block.dart';
import 'package:smb_connect/src/connect/impl/smb1/trans/smb_com_transaction.dart';
import 'package:smb_connect/src/connect/common/smb_negotiation_request.dart';
import 'package:smb_connect/src/connect/common/smb_negotiation_response.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/connect/transport/response.dart';
import 'package:smb_connect/src/smb_constants.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/strings.dart';

import 'server_data.dart';

class SmbComNegotiateResponse extends ServerMessageBlock
    implements SmbNegotiationResponse {
  int dialectIndex = 0;

  /* Negotiated values */
  final ServerData _server = ServerData();
  int _negotiatedFlags2 = 0;
  int _maxMpxCount = 0;
  int _sndBufSize = 0;
  int _recvBufSize = 0;
  int _txBufSize = 0;

  int capabilities = 0;
  // ignore: prefer_final_fields
  int _sessionKey = 0x00000000;
  bool _useUnicode = false;

  SmbComNegotiateResponse(super.config) {
    capabilities = config.capabilities;
    _negotiatedFlags2 = config.flags2;
    _maxMpxCount = Configuration.maxMpxCount;
    _sndBufSize = config.sendBufferSize;
    _recvBufSize = config.receiveBufferSize;
    _txBufSize = config.transactionBufferSize;
    _useUnicode = config.isUseUnicode;
  }

  @override
  DialectVersion getSelectedDialect() {
    return DialectVersion.SMB1;
  }

  @override
  int getTransactionBufferSize() {
    return _txBufSize;
  }

  @override
  int getInitialCredits() {
    return getNegotiatedMpxCount();
  }

  int getNegotiatedSendBufferSize() {
    return _sndBufSize;
  }

  int getNegotiatedMpxCount() {
    return _maxMpxCount;
  }

  int getNegotiatedSessionKey() {
    return _sessionKey;
  }

  @override
  int getReceiveBufferSize() {
    return _recvBufSize;
  }

  @override
  int getSendBufferSize() {
    return _sndBufSize;
  }

  int getNegotiatedFlags2() {
    return _negotiatedFlags2;
  }

  @override
  bool haveCapabilitiy(int cap) {
    return (capabilities & cap) == cap;
  }

  // @override
  // bool isDFSSupported() {
  //   return !config.isDfsDisabled() && haveCapabilitiy(SmbConstants.CAP_DFS);
  // }

  @override
  bool isSigningNegotiated() {
    return (_negotiatedFlags2 & SmbConstants.FLAGS2_SECURITY_SIGNATURES) ==
        SmbConstants.FLAGS2_SECURITY_SIGNATURES;
  }

  @override
  bool isValid(SmbNegotiationRequest req) {
    if (dialectIndex > 10) {
      return false;
    }

    if ((_server.scapabilities & SmbConstants.CAP_EXTENDED_SECURITY) !=
            SmbConstants.CAP_EXTENDED_SECURITY &&
        _server.encryptionKeyLength != 8 &&
        Configuration.lanManCompatibility == 0) {
      // log.warn("Unexpected encryption key length: " + _server.encryptionKeyLength);
      return false;
    }

    if (req.isSigningEnforced() ||
        _server.signaturesRequired ||
        (_server.signaturesEnabled && Configuration.isSigningEnabled)) {
      _negotiatedFlags2 |= SmbConstants.FLAGS2_SECURITY_SIGNATURES;
      if (req.isSigningEnforced() || isSigningRequired()) {
        _negotiatedFlags2 |= SmbConstants.FLAGS2_SECURITY_REQUIRE_SIGNATURES;
      }
    } else {
      _negotiatedFlags2 &= 0xFFFF ^ SmbConstants.FLAGS2_SECURITY_SIGNATURES;
      _negotiatedFlags2 &=
          0xFFFF ^ SmbConstants.FLAGS2_SECURITY_REQUIRE_SIGNATURES;
    }

    _maxMpxCount = min(_maxMpxCount, _server.smaxMpxCount);
    if (_maxMpxCount < 1) _maxMpxCount = 1;
    _sndBufSize = min(_sndBufSize, _server.maxBufferSize);
    _recvBufSize = min(_recvBufSize, _server.maxBufferSize);
    _txBufSize = min(_txBufSize, _server.maxBufferSize);

    capabilities &= _server.scapabilities;
    if ((_server.scapabilities & SmbConstants.CAP_EXTENDED_SECURITY) ==
        SmbConstants.CAP_EXTENDED_SECURITY) {
      // & doesn't copy high bit
      capabilities |= SmbConstants.CAP_EXTENDED_SECURITY;
    }

    if (config.isUseUnicode) {
      // || config.isForceUnicode()
      capabilities |= SmbConstants.CAP_UNICODE;
    }

    if ((capabilities & SmbConstants.CAP_UNICODE) == 0) {
      // server doesn't want unicode
      // if (config.isForceUnicode()) {
      //   capabilities |= SmbConstants.CAP_UNICODE;
      //   _useUnicode = true;
      // } else {
      _useUnicode = false;
      _negotiatedFlags2 &= 0xFFFF ^ SmbConstants.FLAGS2_UNICODE;
      // }
    } else {
      _useUnicode = config.isUseUnicode;
    }
    return true;
  }

  @override
  void setupRequest(CommonServerMessageBlock request) {
    if (request is! ServerMessageBlock) {
      return;
    }

    ServerMessageBlock req = request;

    req.addFlags2(_negotiatedFlags2);
    req.setUseUnicode(req.isForceUnicode() || _useUnicode);
    if (req.isUseUnicode()) {
      req.addFlags2(SmbConstants.FLAGS2_UNICODE);
    }

    if (req is SmbComTransaction) {
      req.setMaxBufferSize(_sndBufSize);
    }
  }

  @override
  void setupResponse(Response resp) {
    if (resp is! ServerMessageBlock) {
      return;
    }
    resp.setUseUnicode(_useUnicode);
  }

  @override
  bool isSigningEnabled() {
    return _server.signaturesEnabled || _server.signaturesRequired;
  }

  @override
  bool isSigningRequired() {
    return _server.signaturesRequired;
  }

  ServerData getServerData() {
    return _server;
  }

  @override
  @protected
  int writeParameterWordsWireFormat(Uint8List dst, int dstIndex) {
    return 0;
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    return 0;
  }

  @override
  @protected
  int readParameterWordsWireFormat(Uint8List buffer, int bufferIndex) {
    int start = bufferIndex;

    dialectIndex = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;
    if (dialectIndex > 10) {
      return bufferIndex - start;
    }
    _server.securityMode = buffer[bufferIndex++] & 0xFF;
    _server.security = _server.securityMode & 0x01;
    _server.encryptedPasswords = (_server.securityMode & 0x02) == 0x02;
    _server.signaturesEnabled = (_server.securityMode & 0x04) == 0x04;
    _server.signaturesRequired = (_server.securityMode & 0x08) == 0x08;
    _server.smaxMpxCount = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;
    _server.maxNumberVcs = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;
    _server.maxBufferSize = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    _server.maxRawSize = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    _server.sessKey = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    _server.scapabilities = SMBUtil.readInt4(buffer, bufferIndex);
    bufferIndex += 4;
    _server.serverTime = SMBUtil.readTime(buffer, bufferIndex);
    bufferIndex += 8;
    int tzOffset = SMBUtil.readInt2(buffer, bufferIndex);
    // tzOffset is signed!
    if (tzOffset > 32767) {
      //Short.MAX_VALUE) {
      tzOffset = -1 * (65536 - tzOffset);
    }
    _server.serverTimeZone = tzOffset;
    bufferIndex += 2;
    _server.encryptionKeyLength = buffer[bufferIndex++] & 0xFF;

    return bufferIndex - start;
  }

  @override
  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    int start = bufferIndex;

    if ((_server.scapabilities & SmbConstants.CAP_EXTENDED_SECURITY) == 0) {
      _server.encryptionKey = Uint8List(_server.encryptionKeyLength);
      byteArrayCopy(
          src: buffer,
          srcOffset: bufferIndex,
          dst: _server.encryptionKey!,
          dstOffset: 0,
          length: _server.encryptionKeyLength);
      bufferIndex += _server.encryptionKeyLength;
      if (byteCount > _server.encryptionKeyLength) {
        int len = 0;
        if ((_negotiatedFlags2 & SmbConstants.FLAGS2_UNICODE) ==
            SmbConstants.FLAGS2_UNICODE) {
          len = findUNITermination(buffer, bufferIndex, 256);
          _server.oemDomainName = fromUNIBytes(buffer, bufferIndex, len);
        } else {
          len = findTermination(buffer, bufferIndex, 256);
          _server.oemDomainName =
              fromOEMBytes(buffer, bufferIndex, len, config);
        }
        bufferIndex += len;
      } else {
        _server.oemDomainName = "";
      }
    } else {
      _server.guid = Uint8List(16);
      byteArrayCopy(
          src: buffer,
          srcOffset: bufferIndex,
          dst: _server.guid!,
          dstOffset: 0,
          length: 16);
      bufferIndex += _server.guid!.length;
      _server.oemDomainName = "";

      if (byteCount > 16) {
        // have initial spnego token
        _server.encryptionKeyLength = byteCount - 16;
        _server.encryptionKey = Uint8List(_server.encryptionKeyLength);
        byteArrayCopy(
          src: buffer,
          srcOffset: bufferIndex,
          dst: _server.encryptionKey!,
          dstOffset: 0,
          length: _server.encryptionKeyLength,
        );
      }
    }

    return bufferIndex - start;
  }

  @override
  String toString() {
    return "SmbComNegotiateResponse[${super.toString()},wordCount=$wordCount,dialectIndex=$dialectIndex,securityMode=0x${Hexdump.toHexString(_server.securityMode, 1)},security=${_server.security == SmbConstants.SECURITY_SHARE ? "share" : "user"},encryptedPasswords=${_server.encryptedPasswords},maxMpxCount=${_server.smaxMpxCount},maxNumberVcs=${_server.maxNumberVcs},maxBufferSize=${_server.maxBufferSize},maxRawSize=${_server.maxRawSize},sessionKey=0x${Hexdump.toHexString(_server.sessKey, 8)},capabilities=0x${Hexdump.toHexString(_server.scapabilities, 8)},serverTime=${DateTime.fromMillisecondsSinceEpoch(_server.serverTime)},serverTimeZone=${_server.serverTimeZone},encryptionKeyLength=${_server.encryptionKeyLength},byteCount=$byteCount,oemDomainName=${_server.oemDomainName}]";
  }
}
