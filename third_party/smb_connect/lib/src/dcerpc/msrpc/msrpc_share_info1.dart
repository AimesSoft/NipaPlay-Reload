import 'package:smb_connect/src/dcerpc/msrpc/srvsvc.dart';
import 'package:smb_connect/src/smb/file_entry.dart';
import 'package:smb_connect/src/smb_constants.dart';
import 'package:smb_connect/src/utils/strings.dart';

class MsrpcShareInfo1 implements FileEntry {
  final String netName;
  final int type;
  final String? remark;

  MsrpcShareInfo1(this.netName, this.type, this.remark);

  MsrpcShareInfo1.info(SrvsvcShareInfo1 info1)
      : this(info1.netname!, info1.type, info1.remark);

  @override
  String getName() {
    return netName;
  }

  @override
  int getFileIndex() {
    return 0;
  }

  @override
  int getType() {
    ///
    /// 0x80000000 means hidden but SmbFile.isHidden() checks for $ at end
    ///
    switch (type & 0xFFFF) {
      case 1:
        return SmbConstants.TYPE_PRINTER;
      case 3:
        return SmbConstants.TYPE_NAMED_PIPE;
    }
    return SmbConstants.TYPE_SHARE;
  }

  @override
  int getAttributes() {
    return SmbConstants.ATTR_READONLY | SmbConstants.ATTR_DIRECTORY;
  }

  @override
  int createTime() {
    return 0;
  }

  @override
  int lastModified() {
    return 0;
  }

  @override
  int lastAccess() {
    return 0;
  }

  @override
  int length() {
    return 0;
  }

  @override
  String toString() {
    return "SmbShareInfo[netName=$netName,type=0x${Hexdump.toHexString(type, 8)},remark=$remark]";
  }
}
