abstract class NtStatus {
  /// Don't bother to edit this. Everything within the interface
  /// block is automatically generated from the ntstatus package.
  static const int NT_STATUS_OK = 0x00000000;
  static const int NT_STATUS_PENDING = 0x00000103;
  static const int NT_STATUS_NOTIFY_ENUM_DIR = 0x0000010C;
  static const int NT_STATUS_BUFFER_OVERFLOW = 0x80000005;
  static const int NT_STATUS_UNSUCCESSFUL = 0xC0000001;
  static const int NT_STATUS_NOT_IMPLEMENTED = 0xC0000002;
  static const int NT_STATUS_INVALID_INFO_CLASS = 0xC0000003;
  static const int NT_STATUS_ACCESS_VIOLATION = 0xC0000005;
  static const int NT_STATUS_INVALID_HANDLE = 0xC0000008;
  static const int NT_STATUS_INVALID_PARAMETER = 0xC000000d;
  static const int NT_STATUS_NO_SUCH_DEVICE = 0xC000000e;
  static const int NT_STATUS_NO_SUCH_FILE = 0xC000000f;
  static const int NT_STATUS_END_OF_FILE = 0xC0000011;
  static const int NT_STATUS_MORE_PROCESSING_REQUIRED = 0xC0000016;
  static const int NT_STATUS_ACCESS_DENIED = 0xC0000022;
  static const int NT_STATUS_BUFFER_TOO_SMALL = 0xC0000023;
  static const int NT_STATUS_OBJECT_NAME_INVALID = 0xC0000033;
  static const int NT_STATUS_OBJECT_NAME_NOT_FOUND = 0xC0000034;
  static const int NT_STATUS_OBJECT_NAME_COLLISION = 0xC0000035;
  static const int NT_STATUS_PORT_DISCONNECTED = 0xC0000037;
  static const int NT_STATUS_OBJECT_PATH_INVALID = 0xC0000039;
  static const int NT_STATUS_OBJECT_PATH_NOT_FOUND = 0xC000003a;
  static const int NT_STATUS_OBJECT_PATH_SYNTAX_BAD = 0xC000003b;
  static const int NT_STATUS_SHARING_VIOLATION = 0xC0000043;
  static const int NT_STATUS_DELETE_PENDING = 0xC0000056;
  static const int NT_STATUS_NO_LOGON_SERVERS = 0xC000005e;
  static const int NT_STATUS_USER_EXISTS = 0xC0000063;
  static const int NT_STATUS_NO_SUCH_USER = 0xC0000064;
  static const int NT_STATUS_WRONG_PASSWORD = 0xC000006a;
  static const int NT_STATUS_LOGON_FAILURE = 0xC000006d;
  static const int NT_STATUS_ACCOUNT_RESTRICTION = 0xC000006e;
  static const int NT_STATUS_INVALID_LOGON_HOURS = 0xC000006f;
  static const int NT_STATUS_INVALID_WORKSTATION = 0xC0000070;
  static const int NT_STATUS_PASSWORD_EXPIRED = 0xC0000071;
  static const int NT_STATUS_ACCOUNT_DISABLED = 0xC0000072;
  static const int NT_STATUS_NONE_MAPPED = 0xC0000073;
  static const int NT_STATUS_INVALID_SID = 0xC0000078;
  static const int NT_STATUS_DISK_FULL = 0xC000007f;
  static const int NT_STATUS_INSTANCE_NOT_AVAILABLE = 0xC00000ab;
  static const int NT_STATUS_PIPE_NOT_AVAILABLE = 0xC00000ac;
  static const int NT_STATUS_INVALID_PIPE_STATE = 0xC00000ad;
  static const int NT_STATUS_PIPE_BUSY = 0xC00000ae;
  static const int NT_STATUS_PIPE_DISCONNECTED = 0xC00000b0;
  static const int NT_STATUS_PIPE_CLOSING = 0xC00000b1;
  static const int NT_STATUS_PIPE_LISTENING = 0xC00000b3;
  static const int NT_STATUS_FILE_IS_A_DIRECTORY = 0xC00000ba;
  static const int NT_STATUS_DUPLICATE_NAME = 0xC00000bd;
  static const int NT_STATUS_NETWORK_NAME_DELETED = 0xC00000c9;
  static const int NT_STATUS_NETWORK_ACCESS_DENIED = 0xC00000ca;
  static const int NT_STATUS_BAD_DEVICE_TYPE = 0xC00000cb;
  static const int NT_STATUS_BAD_NETWORK_NAME = 0xC00000cc;
  static const int NT_STATUS_REQUEST_NOT_ACCEPTED = 0xC00000d0;
  static const int NT_STATUS_CANT_ACCESS_DOMAIN_INFO = 0xC00000da;
  static const int NT_STATUS_NO_SUCH_DOMAIN = 0xC00000df;
  static const int NT_STATUS_NOT_A_DIRECTORY = 0xC0000103;
  static const int NT_STATUS_CANNOT_DELETE = 0xC0000121;
  static const int NT_STATUS_INVALID_COMPUTER_NAME = 0xC0000122;
  static const int NT_STATUS_PIPE_BROKEN = 0xC000014b;
  static const int NT_STATUS_NO_SUCH_ALIAS = 0xC0000151;
  static const int NT_STATUS_LOGON_TYPE_NOT_GRANTED = 0xC000015b;
  static const int NT_STATUS_NO_TRUST_SAM_ACCOUNT = 0xC000018b;
  static const int NT_STATUS_TRUSTED_DOMAIN_FAILURE = 0xC000018c;
  static const int NT_STATUS_TRUSTED_RELATIONSHIP_FAILURE = 0xC000018d;
  static const int NT_STATUS_NOLOGON_WORKSTATION_TRUST_ACCOUNT = 0xC0000199;
  static const int NT_STATUS_PASSWORD_MUST_CHANGE = 0xC0000224;
  static const int NT_STATUS_NOT_FOUND = 0xC0000225;
  static const int NT_STATUS_ACCOUNT_LOCKED_OUT = 0xC0000234;
  static const int NT_STATUS_CONNECTION_REFUSED = 0xC0000236;
  static const int NT_STATUS_PATH_NOT_COVERED = 0xC0000257;
  static const int NT_STATUS_IO_REPARSE_TAG_NOT_HANDLED = 0xC0000279;
  static const int NT_STATUS_NO_MORE_FILES = 0x80000006;

  static const List<int> NT_STATUS_CODES = [
    NT_STATUS_OK,
    NT_STATUS_PENDING,
    NT_STATUS_NOTIFY_ENUM_DIR,
    NT_STATUS_BUFFER_OVERFLOW,
    NT_STATUS_UNSUCCESSFUL,
    NT_STATUS_NOT_IMPLEMENTED,
    NT_STATUS_INVALID_INFO_CLASS,
    NT_STATUS_ACCESS_VIOLATION,
    NT_STATUS_INVALID_HANDLE,
    NT_STATUS_INVALID_PARAMETER,
    NT_STATUS_NO_SUCH_DEVICE,
    NT_STATUS_NO_SUCH_FILE,
    NT_STATUS_END_OF_FILE,
    NT_STATUS_MORE_PROCESSING_REQUIRED,
    NT_STATUS_ACCESS_DENIED,
    NT_STATUS_BUFFER_TOO_SMALL,
    NT_STATUS_OBJECT_NAME_INVALID,
    NT_STATUS_OBJECT_NAME_NOT_FOUND,
    NT_STATUS_OBJECT_NAME_COLLISION,
    NT_STATUS_PORT_DISCONNECTED,
    NT_STATUS_OBJECT_PATH_INVALID,
    NT_STATUS_OBJECT_PATH_NOT_FOUND,
    NT_STATUS_OBJECT_PATH_SYNTAX_BAD,
    NT_STATUS_SHARING_VIOLATION,
    NT_STATUS_DELETE_PENDING,
    NT_STATUS_NO_LOGON_SERVERS,
    NT_STATUS_USER_EXISTS,
    NT_STATUS_NO_SUCH_USER,
    NT_STATUS_WRONG_PASSWORD,
    NT_STATUS_LOGON_FAILURE,
    NT_STATUS_ACCOUNT_RESTRICTION,
    NT_STATUS_INVALID_LOGON_HOURS,
    NT_STATUS_INVALID_WORKSTATION,
    NT_STATUS_PASSWORD_EXPIRED,
    NT_STATUS_ACCOUNT_DISABLED,
    NT_STATUS_NONE_MAPPED,
    NT_STATUS_INVALID_SID,
    NT_STATUS_DISK_FULL,
    NT_STATUS_INSTANCE_NOT_AVAILABLE,
    NT_STATUS_PIPE_NOT_AVAILABLE,
    NT_STATUS_INVALID_PIPE_STATE,
    NT_STATUS_PIPE_BUSY,
    NT_STATUS_PIPE_DISCONNECTED,
    NT_STATUS_PIPE_CLOSING,
    NT_STATUS_PIPE_LISTENING,
    NT_STATUS_FILE_IS_A_DIRECTORY,
    NT_STATUS_DUPLICATE_NAME,
    NT_STATUS_NETWORK_NAME_DELETED,
    NT_STATUS_NETWORK_ACCESS_DENIED,
    NT_STATUS_BAD_DEVICE_TYPE,
    NT_STATUS_BAD_NETWORK_NAME,
    NT_STATUS_REQUEST_NOT_ACCEPTED,
    NT_STATUS_CANT_ACCESS_DOMAIN_INFO,
    NT_STATUS_NO_SUCH_DOMAIN,
    NT_STATUS_NOT_A_DIRECTORY,
    NT_STATUS_CANNOT_DELETE,
    NT_STATUS_INVALID_COMPUTER_NAME,
    NT_STATUS_PIPE_BROKEN,
    NT_STATUS_NO_SUCH_ALIAS,
    NT_STATUS_LOGON_TYPE_NOT_GRANTED,
    NT_STATUS_NO_TRUST_SAM_ACCOUNT,
    NT_STATUS_TRUSTED_DOMAIN_FAILURE,
    NT_STATUS_TRUSTED_RELATIONSHIP_FAILURE,
    NT_STATUS_NOLOGON_WORKSTATION_TRUST_ACCOUNT,
    NT_STATUS_PASSWORD_MUST_CHANGE,
    NT_STATUS_NOT_FOUND,
    NT_STATUS_ACCOUNT_LOCKED_OUT,
    NT_STATUS_CONNECTION_REFUSED,
    NT_STATUS_PATH_NOT_COVERED,
    NT_STATUS_IO_REPARSE_TAG_NOT_HANDLED,
    NT_STATUS_NO_MORE_FILES,
  ];

  static final List<String> NT_STATUS_MESSAGES = [
    "The operation completed successfully.",
    "Request is pending",
    "A notify change request is being completed.",
    "The data was too large to fit into the specified buffer.",
    "A device attached to the system is not functioning.",
    "Incorrect function.",
    "The parameter is incorrect.",
    "Invalid access to memory location.",
    "The handle is invalid.",
    "The parameter is incorrect.",
    "The system cannot find the file specified.",
    "The system cannot find the file specified.",
    "End of file",
    "More data is available.",
    "Access is denied.",
    "The data area passed to a system call is too small.",
    "The filename, directory name, or volume label syntax is incorrect.",
    "The system cannot find the file specified.",
    "Cannot create a file when that file already exists.",
    "The handle is invalid.",
    "The specified path is invalid.",
    "The system cannot find the path specified.",
    "The specified path is invalid.",
    "The process cannot access the file because it is being used by another process.",
    "Access is denied.",
    "There are currently no logon servers available to service the logon request.",
    "The specified user already exists.",
    "The specified user does not exist.",
    "The specified network password is not correct.",
    "Logon failure: unknown user name or bad password.",
    "Logon failure: user account restriction.",
    "Logon failure: account logon time restriction violation.",
    "Logon failure: user not allowed to log on to this computer.",
    "Logon failure: the specified account password has expired.",
    "Logon failure: account currently disabled.",
    "No mapping between account names and security IDs was done.",
    "The security ID structure is invalid.",
    "The file system is full.",
    "All pipe instances are busy.",
    "All pipe instances are busy.",
    "The pipe state is invalid.",
    "All pipe instances are busy.",
    "No process is on the other end of the pipe.",
    "The pipe is being closed.",
    "Waiting for a process to open the other end of the pipe.",
    "File is a directory.",
    "A duplicate name exists on the network.",
    "The specified network name is no longer available.",
    "Network access is denied.",
    "Bad device type",
    "The network name cannot be found.",
    "No more connections can be made to this remote computer at this time because there are already as many connections as the computer can accept.",
    "Indicates a Windows NT Server could not be contacted or that objects within the domain are protected such that necessary information could not be retrieved.",
    "The specified domain did not exist.",
    "The directory name is invalid.",
    "Access is denied.",
    "The format of the specified computer name is invalid.",
    "The pipe has been ended.",
    "The specified local group does not exist.",
    "Logon failure: the user has not been granted the requested logon type at this computer.",
    "The SAM database on the Windows NT Server does not have a computer account for this workstation trust relationship.",
    "The logon request failed because the trust relationship between the primary domain and the trusted domain failed.",
    "The logon request failed because the trust relationship between this workstation and the primary domain failed.",
    "The account used is a Computer Account. Use your global user account or local user account to access this server.",
    "The user must change his password before he logs on the first time.",
    "The object was not found.",
    "The referenced account is currently locked out and may not be logged on to.",
    "Connection refused",
    "The remote system is not reachable by the transport.",
    "The layered file system driver for this I/O tag did not handle it when needed.",
    "No more files were found that match the file specification.",
  ];
}
