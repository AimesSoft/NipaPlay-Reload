import 'dart:typed_data';

class Smb2Constants {
  /// These are all the smbs supported by this library. This includes requests
  /// and well as their responses for each type however the actual implementation?s
  /// of the readXxxWireFormat and writeXxxWireFormat methods may not be in
  /// place. For example at the time of this writing the readXxxWireFormat
  /// for requests and the writeXxxWireFormat for responses are not implemented
  /// and simply return 0. These would need to be completed for a server
  /// implementation.
  static const int SMB2_NEGOTIATE = 0x00;
  static const int SMB2_SESSION_SETUP = 0x01;
  static const int SMB2_LOGOFF = 0x02;
  static const int SMB2_TREE_CONNECT = 0x0003;
  static const int SMB2_TREE_DISCONNECT = 0x0004;
  static const int SMB2_CREATE = 0x0005;
  static const int SMB2_CLOSE = 0x0006;
  static const int SMB2_FLUSH = 0x0007;
  static const int SMB2_READ = 0x0008;
  static const int SMB2_WRITE = 0x0009;
  static const int SMB2_LOCK = 0x000A;
  static const int SMB2_IOCTL = 0x000B;
  static const int SMB2_CANCEL = 0x000C;
  static const int SMB2_ECHO = 0x000D;
  static const int SMB2_QUERY_DIRECTORY = 0x000E;
  static const int SMB2_CHANGE_NOTIFY = 0x000F;
  static const int SMB2_QUERY_INFO = 0x0010;
  static const int SMB2_SET_INFO = 0x0011;
  static const int SMB2_OPLOCK_BREAK = 0x0012;

  static const int SMB2_FLAGS_SERVER_TO_REDIR = 0x00000001;
  static const int SMB2_FLAGS_ASYNC_COMMAND = 0x00000002;
  static const int SMB2_FLAGS_RELATED_OPERATIONS = 0x00000004;
  static const int SMB2_FLAGS_SIGNED = 0x00000008;
  static const int SMB2_FLAGS_PRIORITY_MASK = 0x00000070;
  static const int SMB2_FLAGS_DFS_OPERATIONS = 0x10000000;
  static const int SMB2_FLAGS_REPLAY_OPERATION = 0x20000000;

  static const int SMB2_SHARE_TYPE_DISK = 0x1;
  static const int SMB2_SHARE_TYPE_PIPE = 0x2;
  static const int SMB2_SHARE_TYPE_PRINT = 0x3;

  static const int SMB2_SHAREFLAG_MANUAL_CACHING = 0x0;
  static const int SMB2_SHAREFLAG_AUTO_CACHING = 0x10;
  static const int SMB2_SHAREFLAG_VDO_CACHING = 0x20;

  static const int SMB2_SHAREFLAG_DFS = 0x1;
  static const int SMB2_SHAREFLAG_DFS_ROOT = 0x2;

  static const int SMB2_SHAREFLAG_RESTRICT_EXCLUSIVE_OPENS = 0x100;
  static const int SMB2_SHAREFLAG_FORCE_SHARED_DELETE = 0x200;
  static const int SMB2_SHAREFLAG_ALLOW_NAMESPACE_CACHING = 0x400;
  static const int SMB2_SHAREFLAG_ACCESS_BASED_DIRECTORY_ENUM = 0x800;
  static const int SMB2_SHAREFLAG_FORCE_LEVEL2_OPLOCK = 0x1000;
  static const int SMB2_SHAREFLAG_ENABLE_HASH_V1 = 0x2000;
  static const int SMB2_SHAREFLAG_ENABLE_HASH_V2 = 0x4000;
  static const int SMB2_SHAREFLAG_ENCRYPT_DATA = 0x8000;

  static const int SMB2_SHARE_CAP_DFS = 0x8;
  static const int SMB2_SHARE_CAP_CONTINUOUS_AVAILABILITY = 0x10;
  static const int SMB2_SHARE_CAP_SCALEOUT = 0x20;
  static const int SMB2_SHARE_CAP_CLUSTER = 0x40;

  static const int SMB2_SHARE_CAP_ASYMMETRIC = 0x80;
  static const int SMB2_HEADER_LENGTH = 64;
  static const int SMB2_NEGOTIATE_SIGNING_ENABLED = 0x0001;
  static const int SMB2_NEGOTIATE_SIGNING_REQUIRED = 0x0002;
  static const int SMB2_DIALECT_0202 = 0x0202;
  static const int SMB2_DIALECT_0210 = 0x0210;
  static const int SMB2_DIALECT_0300 = 0x0300;
  static const int SMB2_DIALECT_0302 = 0x0302;
  static const int SMB2_DIALECT_0311 = 0x0311;
  static const int SMB2_DIALECT_ANY = 0x02FF;
  static const int SMB2_GLOBAL_CAP_DFS = 0x1;
  static const int SMB2_GLOBAL_CAP_LEASING = 0x2;
  static const int SMB2_GLOBAL_CAP_LARGE_MTU = 0x4;
  static const int SMB2_GLOBAL_CAP_MULTI_CHANNEL = 0x8;
  static const int SMB2_GLOBAL_CAP_PERSISTENT_HANDLES = 0x10;
  static const int SMB2_GLOBAL_CAP_DIRECTORY_LEASING = 0x20;
  static const int SMB2_GLOBAL_CAP_ENCRYPTION = 0x40;

  static const int SMB2_0_INFO_FILE = 1;
  static const int SMB2_0_INFO_FILESYSTEM = 2;
  static const int SMB2_0_INFO_SECURITY = 3;
  static const int SMB2_0_INFO_QUOTA = 4;

  static const int SMB2_OPLOCK_LEVEL_NONE = 0x0;
  static const int SMB2_OPLOCK_LEVEL_II = 0x1;
  static const int SMB2_OPLOCK_LEVEL_EXCLUSIVE = 0x8;
  static const int SMB2_OPLOCK_LEVEL_BATCH = 0x9;
  static const int SMB2_OPLOCK_LEVEL_LEASE = 0xFF;

  static const int SMB2_IMPERSONATION_LEVEL_ANONYMOUS = 0x0;

  static const int SMB2_IMPERSONATION_LEVEL_IDENTIFICATION = 0x1;

  static const int SMB2_IMPERSONATION_LEVEL_IMPERSONATION = 0x2;

  static const int SMB2_IMPERSONATION_LEVEL_DELEGATE = 0x3;

  static const int FILE_SHARE_READ = 0x1;

  static const int FILE_SHARE_WRITE = 0x2;

  static const int FILE_SHARE_DELETE = 0x4;

  static const int FILE_SUPERSEDE = 0x0;
  static const int FILE_OPEN = 0x1;
  static const int FILE_CREATE = 0x2;
  static const int FILE_OPEN_IF = 0x3;
  static const int FILE_OVERWRITE = 0x4;
  static const int FILE_OVERWRITE_IF = 0x5;

  static const int FILE_DIRECTORY_FILE = 0x1;
  static const int FILE_WRITE_THROUGH = 0x2;
  static const int FILE_SEQUENTIAL_ONLY = 0x4;
  static const int FILE_NO_IMTERMEDIATE_BUFFERING = 0x8;
  static const int FILE_SYNCHRONOUS_IO_ALERT = 0x10;
  static const int FILE_SYNCHRONOUS_IO_NONALERT = 0x20;
  static const int FILE_NON_DIRECTORY_FILE = 0x40;
  static const int FILE_COMPLETE_IF_OPLOCKED = 0x100;
  static const int FILE_NO_EA_KNOWLEDGE = 0x200;
  static const int FILE_OPEN_REMOTE_INSTANCE = 0x400;
  static const int FILE_RANDOM_ACCESS = 0x800;
  static const int FILE_DELETE_ON_CLOSE = 0x1000;
  static const int FILE_OPEN_BY_FILE_ID = 0x2000;
  static const int FILE_OPEN_FOR_BACKUP_INTENT = 0x4000;
  static const int FILE_NO_COMPRESSION = 0x8000;
  static const int FILE_OPEN_REQUIRING_OPLOCK = 0x10000;
  static const int FILE_DISALLOW_EXCLUSIVE = 0x20000;
  static const int FILE_RESERVE_OPFILTER = 0x100000;
  static const int FILE_OPEN_REPARSE_POINT = 0x200000;
  static const int FILE_NOP_RECALL = 0x400000;
  static const int FILE_OPEN_FOR_FREE_SPACE_QUERY = 0x800000;

  static const int FLAGS_NAME_LIST_REFERRAL = 0x0002;
  static const int FLAGS_TARGET_SET_BOUNDARY = 0x0004;
  static const int TYPE_ROOT_TARGETS = 0x0;
  static const int TYPE_NON_ROOT_TARGETS = 0x1;

  static final Uint8List UNSPECIFIED_FILEID = Uint8List.fromList([
    0xFF,
    0xFF,
    0xFF,
    0xFF,
    0xFF,
    0xFF,
    0xFF,
    0xFF,
    0xFF,
    0xFF,
    0xFF,
    0xFF,
    0xFF,
    0xFF,
    0xFF,
    0xFF
  ]);

  static const int UNSPECIFIED_TREEID = 0xFFFFFFFF;

  static const int UNSPECIFIED_SESSIONID = -1;

  static String commandToString(int cmd) {
    String c;
    switch (cmd) {
      case SMB2_NEGOTIATE:
        c = "SMB2_NEGOTIATE";
        break;
      case SMB2_SESSION_SETUP:
        c = "SMB2_SESSION_SETUP";
        break;
      case SMB2_LOGOFF:
        c = "SMB2_LOGOFF";
        break;
      case SMB2_TREE_CONNECT:
        c = "SMB2_TREE_CONNECT";
        break;
      case SMB2_TREE_DISCONNECT:
        c = "SMB2_TREE_DISCONNECT";
        break;
      case SMB2_CREATE:
        c = "SMB2_CREATE";
        break;
      case SMB2_CLOSE:
        c = "SMB2_CLOSE";
        break;
      case SMB2_FLUSH:
        c = "SMB2_FLUSH";
        break;
      case SMB2_READ:
        c = "SMB2_READ";
        break;
      case SMB2_WRITE:
        c = "SMB2_WRITE";
        break;
      case SMB2_LOCK:
        c = "SMB2_LOCK";
        break;
      case SMB2_IOCTL:
        c = "SMB2_IOCTL";
        break;
      case SMB2_CANCEL:
        c = "SMB2_CANCEL";
        break;
      case SMB2_ECHO:
        c = "SMB2_ECHO";
        break;
      case SMB2_QUERY_DIRECTORY:
        c = "SMB2_QUERY_DIRECTORY";
        break;
      case SMB2_CHANGE_NOTIFY:
        c = "SMB2_CHANGE_NOTIFY";
        break;
      case SMB2_QUERY_INFO:
        c = "SMB2_QUERY_INFO";
        break;
      case SMB2_SET_INFO:
        c = "SMB2_SET_INFO";
        break;
      case SMB2_OPLOCK_BREAK:
        c = "SMB2_OPLOCK_BREAK";
        break;
      default:
        c = "UNKNOWN";
    }
    return c;
  }
}
