import 'package:smb_connect/src/dcerpc/dcerpc_constants.dart';
import 'package:smb_connect/src/dcerpc/msrpc/msrpc_share_info1.dart';
import 'package:smb_connect/src/dcerpc/msrpc/srvsvc.dart';
import 'package:smb_connect/src/smb/file_entry.dart';

class MsrpcShareEnum extends SrvsvcShareEnumAll {
  MsrpcShareEnum(String server)
      : super("\\\\$server", 1, SrvsvcShareInfoCtr1(), -1, 0, 0) {
    ptype = 0;
    flags =
        DcerpcConstants.DCERPC_FIRST_FRAG | DcerpcConstants.DCERPC_LAST_FRAG;
  }

  List<FileEntry> getEntries() {
    /// The ShareInfo1 class does not implement the FileEntry
    /// abstract class (because it is generated from IDL). Therefore
    /// we must create an array of objects that do.
    SrvsvcShareInfoCtr1 ctr = info as SrvsvcShareInfoCtr1;
    List<MsrpcShareInfo1> entries = List.generate(
        ctr.count, (index) => MsrpcShareInfo1.info(ctr.array![index]));
    return entries;
  }
}
