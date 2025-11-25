import 'dart:typed_data';

import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/common/request_with_path.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2.dart';
import 'package:smb_connect/src/connect/impl/smb2/server_message_block2_request.dart';
import 'package:smb_connect/src/connect/impl/smb2/smb2_constants.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/base.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/strings.dart';

import 'smb2_create_response.dart';

class Smb2CreateRequest extends ServerMessageBlock2Request<Smb2CreateResponse>
    implements RequestWithPath {
  int _securityFlags = 0;
  int _requestedOplockLevel = Smb2Constants.SMB2_OPLOCK_LEVEL_NONE;
  int _impersonationLevel =
      Smb2Constants.SMB2_IMPERSONATION_LEVEL_IMPERSONATION;
  int _smbCreateFlags = 0;
  int _desiredAccess = 0x00120089; // 0x80000000 | 0x1;
  int _fileAttributes = 0;
  int _shareAccess =
      Smb2Constants.FILE_SHARE_READ | Smb2Constants.FILE_SHARE_WRITE;
  int _createDisposition = Smb2Constants.FILE_OPEN;
  int _createOptions = 0;

  late String _name;
  String? _fullName;

  String? _domain;

  String? _server;

  bool _resolveDfs = false;

  Smb2CreateRequest(super.config, String name)
      : super(command: Smb2Constants.SMB2_CREATE) {
    setPath(name);
  }

  @override
  @protected
  Smb2CreateResponse createResponse(Configuration config,
      ServerMessageBlock2Request<Smb2CreateResponse> req) {
    return Smb2CreateResponse(config, _name);
  }

  @override
  String getPath() {
    return '\\$_name';
  }

  @override
  String? getFullUNCPath() {
    return _fullName;
  }

  @override
  String? getServer() {
    return _server;
  }

  @override
  String? getDomain() {
    return _domain;
  }

  @override
  void setFullUNCPath(String? domain, String? server, String? fullName) {
    _domain = domain;
    _server = server;
    _fullName = fullName;
  }

  @override
  void setPath(String path) {
    if (path.isNotEmpty && path[0] == '\\') {
      path = path.substring(1);
    }
    // win8.1 returns ACCESS_DENIED if the trailing backslash is included
    if (path.length > 1 && path[path.length - 1] == '\\') {
      path = path.substring(0, path.length - 1);
    }
    _name = path;
  }

  @override
  void setResolveInDfs(bool resolve) {
    addFlags(Smb2Constants.SMB2_FLAGS_DFS_OPERATIONS);
    _resolveDfs = resolve;
  }

  @override
  bool isResolveInDfs() {
    return _resolveDfs;
  }

  void setSecurityFlags(int securityFlags) {
    _securityFlags = securityFlags;
  }

  void setRequestedOplockLevel(int requestedOplockLevel) {
    _requestedOplockLevel = requestedOplockLevel;
  }

  void setImpersonationLevel(int impersonationLevel) {
    _impersonationLevel = impersonationLevel;
  }

  void setSmbCreateFlags(int smbCreateFlags) {
    _smbCreateFlags = smbCreateFlags;
  }

  void setDesiredAccess(int desiredAccess) {
    _desiredAccess = desiredAccess;
  }

  void setFileAttributes(int fileAttributes) {
    _fileAttributes = fileAttributes;
  }

  void setShareAccess(int shareAccess) {
    _shareAccess = shareAccess;
  }

  void setCreateDisposition(int createDisposition) {
    _createDisposition = createDisposition;
  }

  void setCreateOptions(int createOptions) {
    _createOptions = createOptions;
  }

  @override
  int size() {
    int size = Smb2Constants.SMB2_HEADER_LENGTH + 56;
    int nameLen = 2 * _name.length;
    if (nameLen == 0) {
      nameLen++;
    }

    size += ServerMessageBlock2.size8(nameLen);
    // if (_createContexts != null) {
    //   for (CreateContextRequest ccr in _createContexts!) {
    //     size += ServerMessageBlock2.size8(ccr.size());
    //   }
    // }
    return ServerMessageBlock2.size8(size);
  }

  @override
  @protected
  int writeBytesWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;

    SMBUtil.writeInt2(57, dst, dstIndex);
    dst[dstIndex + 2] = _securityFlags;
    dst[dstIndex + 3] = _requestedOplockLevel;
    dstIndex += 4;

    SMBUtil.writeInt4(_impersonationLevel, dst, dstIndex);
    dstIndex += 4;
    SMBUtil.writeInt8(_smbCreateFlags, dst, dstIndex);
    dstIndex += 8;
    dstIndex += 8; // Reserved

    SMBUtil.writeInt4(_desiredAccess, dst, dstIndex);
    dstIndex += 4;
    SMBUtil.writeInt4(_fileAttributes, dst, dstIndex);
    dstIndex += 4;
    SMBUtil.writeInt4(_shareAccess, dst, dstIndex);
    dstIndex += 4;
    SMBUtil.writeInt4(_createDisposition, dst, dstIndex);
    dstIndex += 4;
    SMBUtil.writeInt4(_createOptions, dst, dstIndex);
    dstIndex += 4;

    int nameOffsetOffset = dstIndex;
    Uint8List nameBytes = _name.getUNIBytes();
    SMBUtil.writeInt2(nameBytes.length, dst, dstIndex + 2);
    dstIndex += 4;

    int createContextOffsetOffset = dstIndex;
    dstIndex += 4;
    int createContextLengthOffset = dstIndex;
    dstIndex += 4;

    SMBUtil.writeInt2(dstIndex - getHeaderStart(), dst, nameOffsetOffset);

    byteArrayCopy(
        src: nameBytes,
        srcOffset: 0,
        dst: dst,
        dstOffset: dstIndex,
        length: nameBytes.length);
    if (nameBytes.isEmpty) {
      // buffer must contain at least one int
      dstIndex++;
    } else {
      dstIndex += nameBytes.length;
    }

    dstIndex += pad8(dstIndex);

    int totalCreateContextLength = 0;
    // if (_createContexts == null || _createContexts.isEmpty) {
    SMBUtil.writeInt4(0, dst, createContextOffsetOffset);
    // } else {
    //   SMBUtil.writeInt4(
    //       dstIndex - getHeaderStart(), dst, createContextOffsetOffset);
    //   int lastStart = -1;
    //   for (CreateContextRequest createContext in _createContexts) {
    //     int structStart = dstIndex;

    //     SMBUtil.writeInt4(0, dst, structStart);
    //     if (lastStart > 0) {
    //       // set next pointer of previous CREATE_CONTEXT
    //       SMBUtil.writeInt4(structStart - dstIndex, dst, lastStart);
    //     }

    //     dstIndex += 4;
    //     Uint8List cnBytes = createContext.getName();
    //     int cnOffsetOffset = dstIndex;
    //     SMBUtil.writeInt2(cnBytes.length, dst, dstIndex + 2);
    //     dstIndex += 4;

    //     int dataOffsetOffset = dstIndex + 2;
    //     dstIndex += 4;
    //     int dataLengthOffset = dstIndex;
    //     dstIndex += 4;

    //     SMBUtil.writeInt2(dstIndex - structStart, dst, cnOffsetOffset);
    //     byteArrayCopy(
    //         src: cnBytes,
    //         srcOffset: 0,
    //         dst: dst,
    //         dstOffset: dstIndex,
    //         length: cnBytes.length);
    //     dstIndex += cnBytes.length;
    //     dstIndex += pad8(dstIndex);

    //     SMBUtil.writeInt2(dstIndex - structStart, dst, dataOffsetOffset);
    //     int len = createContext.encode(dst, dstIndex);
    //     SMBUtil.writeInt4(len, dst, dataLengthOffset);
    //     dstIndex += len;

    //     int pad = pad8(dstIndex);
    //     totalCreateContextLength += len + pad;
    //     dstIndex += pad;
    //     lastStart = structStart;
    //   }
    // }
    SMBUtil.writeInt4(totalCreateContextLength, dst, createContextLengthOffset);
    return dstIndex - start;
  }

  @override
  @protected
  int readBytesWireFormat(Uint8List buffer, int bufferIndex) {
    return 0;
  }

  @override
  String toString() {
    return "${super.toString()},name=$_name,resolveDfs=$_resolveDfs";
  }
}
