import 'dart:typed_data';

import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block_request.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/connect/common/smb_signing_digest.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/smb_constants.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/strings.dart';

import '../../common/request_with_path.dart';
import 'smb1_signing_digest.dart';

abstract class ServerMessageBlock
    implements
        CommonServerMessageBlockRequest,
        CommonServerMessageBlockResponse,
        RequestWithPath {
  int _command = 0, _flags = 0;

  @protected
  int headerStart = 0,
      length = 0,
      batchLevel = 0,
      errorCode = 0,
      flags2 = 0,
      pid = 0,
      uid = 0,
      mid = 0,
      wordCount = 0,
      byteCount = 0;
  @protected
  int tid = 0xFFFF;
  bool _useUnicode = false;
  final bool _forceUnicode = false;
  bool _extendedSecurity = false;
  bool _received = false;
  int _signSeq = 0;
  bool _verifyFailed = false;
  String? path;
  SMB1SigningDigest? digest;
  ServerMessageBlock? _response;

  final Configuration config;

  int? _expiration;

  Exception? _exception;

  bool _isError = false;

  Uint8List? _rawPayload;

  bool _retainPayload = false;

  String? _fullPath;
  String? _server;
  String? _domain;

  int? _overrideTimeout;

  @protected
  ServerMessageBlock(this.config, {int command = 0, this.path}) {
    _command = command;
    _flags = (SmbConstants.FLAGS_PATH_NAMES_CASELESS |
        SmbConstants.FLAGS_PATH_NAMES_CANONICALIZED);
    pid = config.pid;
    batchLevel = 0;
  }

  @override
  int size() {
    return 0;
  }

  @override
  int? getOverrideTimeout() {
    return _overrideTimeout;
  }

  void setOverrideTimeout(int? overrideTimeout) {
    _overrideTimeout = overrideTimeout;
  }

  @override
  ServerMessageBlock? getNext() {
    return null;
  }

  @override
  CommonServerMessageBlockResponse? getNextResponse() {
    return null;
  }

  @override
  void prepare(CommonServerMessageBlockRequest next) {}

  @override
  int getCreditCost() {
    return 1;
  }

  @override
  int getGrantedCredits() {
    return 1;
  }

  @override
  void setRequestCredits(int credits) {}

  @override
  int getCommand() {
    return _command;
  }

  @override
  void setCommand(int command) {
    _command = command;
  }

  int getByteCount() {
    return byteCount;
  }

  int getLength() {
    return length;
  }

  bool isForceUnicode() {
    return _forceUnicode;
  }

  int getFlags() {
    return _flags;
  }

  void setFlags(int flags) {
    _flags = flags;
  }

  int getFlags2() {
    return flags2;
  }

  void setFlags2(int fl) {
    flags2 = fl;
  }

  void addFlags2(int fl) {
    flags2 |= fl;
  }

  void remFlags2(int fl) {
    flags2 &= ~fl;
  }

  @override
  void setResolveInDfs(bool resolve) {
    if (resolve) {
      addFlags2(SmbConstants.FLAGS2_RESOLVE_PATHS_IN_DFS);
    } else {
      remFlags2(SmbConstants.FLAGS2_RESOLVE_PATHS_IN_DFS);
    }
  }

  @override
  bool isResolveInDfs() {
    return (getFlags() & SmbConstants.FLAGS2_RESOLVE_PATHS_IN_DFS) ==
        SmbConstants.FLAGS2_RESOLVE_PATHS_IN_DFS;
  }

  @override
  int getErrorCode() {
    return errorCode;
  }

  void setErrorCode(int errorCode) {
    errorCode = errorCode;
  }

  @override
  String? getPath() {
    return path;
  }

  @override
  String? getFullUNCPath() {
    return _fullPath;
  }

  @override
  String? getDomain() {
    return _domain;
  }

  @override
  String? getServer() {
    return _server;
  }

  @override
  void setFullUNCPath(String? domain, String? server, String? fullPath) {
    _domain = domain;
    _server = server;
    _fullPath = fullPath;
  }

  @override
  void setPath(String nextPath) {
    path = nextPath;
  }

  @override
  SMB1SigningDigest? getDigest() {
    return digest;
  }

  @override
  void setDigest(SMBSigningDigest? next) {
    digest = next != null ? next as SMB1SigningDigest : null;
  }

  bool isExtendedSecurity() {
    return _extendedSecurity;
  }

  @override
  void setSessionId(int sessionId) {
    // ignore
  }

  @override
  void setExtendedSecurity(bool extendedSecurity) {
    _extendedSecurity = extendedSecurity;
  }

  bool isUseUnicode() {
    return _useUnicode;
  }

  void setUseUnicode(bool useUnicode) {
    _useUnicode = useUnicode;
  }

  @override
  bool isReceived() {
    return _received;
  }

  @override
  void clearReceived() {
    _received = false;
  }

  @override
  void setReceived() {
    _received = true;
  }

  @override
  void setException(Exception? e) {
    _exception = e;
  }

  @override
  void error() {
    _isError = true;
  }

  @override
  ServerMessageBlock? getResponse() {
    return _response;
  }

  CommonServerMessageBlock ignoreDisconnect() {
    return this;
  }

  @override
  void setResponse(CommonServerMessageBlockResponse response) {
    if (response is! ServerMessageBlock) {
      throw "IllegalArgumentException";
    }
    _response = response;
  }

  @override
  int getMid() {
    return mid;
  }

  @override
  void setMid(int mid) {
    this.mid = mid;
  }

  int getTid() {
    return tid;
  }

  @override
  void setTid(int tid) {
    this.tid = tid;
  }

  int getPid() {
    return pid;
  }

  void setPid(int pid) {
    this.pid = pid;
  }

  int getUid() {
    return uid;
  }

  @override
  void setUid(int uid) {
    this.uid = uid;
  }

  int getSignSeq() {
    return _signSeq;
  }

  void setSignSeq(int signSeq) {
    _signSeq = signSeq;
  }

  @override
  bool isVerifyFailed() {
    return _verifyFailed;
  }

  @override
  Exception? getException() {
    return _exception;
  }

  @override
  bool isError() {
    return _isError;
  }

  @override
  Uint8List? getRawPayload() {
    return _rawPayload;
  }

  @override
  void setRawPayload(Uint8List rawPayload) {
    _rawPayload = rawPayload;
  }

  @override
  bool isRetainPayload() {
    return _retainPayload;
  }

  @override
  void setRetainPayload() {
    _retainPayload = true;
  }

  @override
  int? getExpiration() {
    return _expiration;
  }

  @override
  void setExpiration(int? exp) {
    _expiration = exp;
  }

  // @protected
  // Configuration getConfig() {
  //   return config;
  // }

  @override
  void reset() {
    _flags = (SmbConstants.FLAGS_PATH_NAMES_CASELESS |
        SmbConstants.FLAGS_PATH_NAMES_CANONICALIZED);
    flags2 = 0;
    errorCode = 0;
    _received = false;
    digest = null;
    uid = 0;
    tid = 0xFFFF;
  }

  @override
  bool verifySignature(Uint8List buffer, int i, int size) {
    ///
    /// Verification fails (w/ W2K3 server at least) if status is not 0. This
    /// suggests MS doesn't compute the signature (correctly) for error responses
    /// (perhaps for DOS reasons).
    ///
    /// Looks like the failure case also is just reflecting back the signature we sent

    ///
    /// Maybe this is related:
    ///
    /// If signing is not active, the SecuritySignature field of the SMB Header for all messages sent, except
    /// the SMB_COM_SESSION_SETUP_ANDX Response (section 2.2.4.53.2), MUST be set to
    /// 0x0000000000000000. For the SMB_COM_SESSION_SETUP_ANDX Response, the SecuritySignature
    /// field of the SMB Header SHOULD<226> be set to the SecuritySignature received in the
    /// SMB_COM_SESSION_SETUP_ANDX Request (section 2.2.4.53.1).
    if (getErrorCode() == 0) {
      bool verify = digest?.verify(buffer, i, size, 0, this) == true;
      _verifyFailed = verify;
      return !verify;
    }
    return true;
  }

  @protected
  int writeString(String str, Uint8List dst, int dstIndex, {bool? unicode}) {
    int start = dstIndex;
    if (unicode ?? _useUnicode) {
      // Unicode requires word alignment
      if (((dstIndex - headerStart) % 2) != 0) {
        dst[dstIndex++] = 0; //'\0';
      }
      byteArrayCopy(
          src: str.getUNIBytes(),
          srcOffset: 0,
          dst: dst,
          dstOffset: dstIndex,
          length: str.length * 2);
      dstIndex += str.length * 2;
      dst[dstIndex++] = 0;
      dst[dstIndex++] = 0;
    } else {
      Uint8List b = str.getOEMBytes(config);
      byteArrayCopy(
          src: b,
          srcOffset: 0,
          dst: dst,
          dstOffset: dstIndex,
          length: b.length);
      dstIndex += b.length;
      dst[dstIndex++] = 0;
    }
    return dstIndex - start;
  }

  String readString(Uint8List src, int srcIndex) {
    return readString4(src, srcIndex, 255, _useUnicode);
  }

  String readString4(Uint8List src, int srcIndex, int maxLen, bool unicode) {
    if (unicode) {
      // Unicode requires word alignment
      if (((srcIndex - headerStart) % 2) != 0) {
        srcIndex++;
      }
      return fromUNIBytes(
          src, srcIndex, findUNITermination(src, srcIndex, maxLen));
    }

    return fromOEMBytes(
        src, srcIndex, findTermination(src, srcIndex, maxLen), config);
  }

  String readString5(
      Uint8List src, int srcIndex, int srcEnd, int maxLen, bool unicode) {
    if (unicode) {
      // Unicode requires word alignment
      if (((srcIndex - headerStart) % 2) != 0) {
        srcIndex++;
      }
      return fromUNIBytes(
          src, srcIndex, findUNITermination(src, srcIndex, maxLen));
    }

    return fromOEMBytes(
        src, srcIndex, findTermination(src, srcIndex, maxLen), config);
  }

  int stringWireLength(String str, int offset) {
    int len = str.length + 1;
    if (_useUnicode) {
      len = str.length * 2 + 2;
      len = (offset % 2) != 0 ? len + 1 : len;
    }
    return len;
  }

  @protected
  int readStringLength(Uint8List src, int srcIndex, int max) {
    int len = 0;
    while (src[srcIndex + len] != 0x00) {
      if (len++ > max) {
        throw "zero termination not found: $this"; //RuntimeCIFSException();
      }
    }
    return len;
  }

  @override
  int encode(Uint8List dst, int dstIndex) {
    int start = headerStart = dstIndex;

    dstIndex += writeHeaderWireFormat(dst, dstIndex);
    wordCount = writeParameterWordsWireFormat(dst, dstIndex + 1);
    dst[dstIndex++] = ((wordCount ~/ 2) & 0xFF);
    dstIndex += wordCount;
    wordCount ~/= 2;
    byteCount = writeBytesWireFormat(dst, dstIndex + 2);
    dst[dstIndex++] = (byteCount & 0xFF);
    dst[dstIndex++] = ((byteCount >> 8) & 0xFF);
    dstIndex += byteCount;

    length = dstIndex - start;

    digest?.sign(dst, headerStart, length, this, _response);

    return length;
  }

  @override
  int decode(Uint8List buffer, int bufferIndex) {
    int start = headerStart = bufferIndex;

    bufferIndex += readHeaderWireFormat(buffer, bufferIndex);

    wordCount = buffer[bufferIndex++];
    if (wordCount != 0) {
      readParameterWordsWireFormat(buffer, bufferIndex);
      bufferIndex += wordCount * 2;
    }

    byteCount = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;

    if (byteCount != 0) {
      readBytesWireFormat(buffer, bufferIndex);
      // if ( ( n = readBytesWireFormat(buffer, bufferIndex) ) != byteCount ) {
      // Don't think we can rely on n being correct here. Must use byteCount.
      // Last paragraph of section 3.13.3 eludes to this.

      bufferIndex += byteCount;
    }

    int len = bufferIndex - start;
    length = len;

    if (isRetainPayload()) {
      Uint8List payload = Uint8List(len);
      byteArrayCopy(
          src: buffer, srcOffset: 4, dst: payload, dstOffset: 0, length: len);
      setRawPayload(payload);
    }

    if (!verifySignature(buffer, 4, len)) {
      throw //SMBProtocolDecodingException(
          "Signature verification failed for $runtimeType"; //); //this.getClass().getName()
    }

    return len;
  }

  @protected
  int writeHeaderWireFormat(Uint8List dst, int dstIndex) {
    byteArrayCopy(
        src: SMBUtil.SMB_HEADER,
        srcOffset: 0,
        dst: dst,
        dstOffset: dstIndex,
        length: SMBUtil.SMB_HEADER.length);
    dst[dstIndex + SmbConstants.CMD_OFFSET] = _command;
    dst[dstIndex + SmbConstants.FLAGS_OFFSET] = _flags;
    SMBUtil.writeInt2(flags2, dst, dstIndex + SmbConstants.FLAGS_OFFSET + 1);
    dstIndex += SmbConstants.TID_OFFSET;
    SMBUtil.writeInt2(tid, dst, dstIndex);
    SMBUtil.writeInt2(pid, dst, dstIndex + 2);
    SMBUtil.writeInt2(uid, dst, dstIndex + 4);
    SMBUtil.writeInt2(mid, dst, dstIndex + 6);
    return SmbConstants.SMB1_HEADER_LENGTH;
  }

  @protected
  int readHeaderWireFormat(Uint8List buffer, int bufferIndex) {
    _command = buffer[bufferIndex + SmbConstants.CMD_OFFSET];
    errorCode =
        SMBUtil.readInt4(buffer, bufferIndex + SmbConstants.ERROR_CODE_OFFSET);
    _flags = buffer[bufferIndex + SmbConstants.FLAGS_OFFSET];
    flags2 =
        SMBUtil.readInt2(buffer, bufferIndex + SmbConstants.FLAGS_OFFSET + 1);
    tid = SMBUtil.readInt2(buffer, bufferIndex + SmbConstants.TID_OFFSET);
    pid = SMBUtil.readInt2(buffer, bufferIndex + SmbConstants.TID_OFFSET + 2);
    uid = SMBUtil.readInt2(buffer, bufferIndex + SmbConstants.TID_OFFSET + 4);
    mid = SMBUtil.readInt2(buffer, bufferIndex + SmbConstants.TID_OFFSET + 6);
    return SmbConstants.SMB1_HEADER_LENGTH;
  }

  @protected
  bool isResponse() {
    return (_flags & SmbConstants.FLAGS_RESPONSE) ==
        SmbConstants.FLAGS_RESPONSE;
  }

  /// For this packet deconstruction technique to work for
  /// other networking protocols the InputStream may need
  /// to be passed to the readXxxWireFormat methods. This is
  /// actually purer. However, in the case of smb we know the
  /// wordCount and byteCount. And since every subclass of
  /// ServerMessageBlock would have to perform the same read
  /// operation on the input stream, we might as will pull that
  /// common functionality into the superclass and read wordCount
  /// and byteCount worth of data.
  /// We will still use the readXxxWireFormat return values to
  /// indicate how many bytes(note: readParameterWordsWireFormat
  /// returns bytes read and not the number of words(but the
  /// wordCount member DOES store the number of words)) we
  /// actually read. Incedentally this is important to the
  /// AndXServerMessageBlock class that needs to potentially
  /// read in another smb's parameter words and bytes based on
  /// information in it's andxCommand, andxOffset, ...etc.
  @protected
  int writeParameterWordsWireFormat(Uint8List dst, int dstIndex);

  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex);

  @protected
  int readParameterWordsWireFormat(Uint8List buffer, int bufferIndex);

  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex);

  @override
  String toString() {
    String c = SmbComConstants.commandToString(_command);
    String str = errorCode == 0
        ? "0"
        : errorCode.toString(); //SmbException.getMessageByCode(errorCode);
    return "command=$c,received=$_received,errorCode=$str,flags=0x${Hexdump.toHexString(_flags & 0xFF, 4)},flags2=0x${Hexdump.toHexString(flags2, 4)},signSeq=$_signSeq,tid=$tid,pid=$pid,uid=$uid,mid=$mid,wordCount=$wordCount,byteCount=$byteCount";
  }
}
