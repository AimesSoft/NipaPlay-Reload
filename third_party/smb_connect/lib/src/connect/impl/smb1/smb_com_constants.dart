class SmbComConstants {
  static const int SMB_INFO_STANDARD = 1;
  static const int SMB_INFO_QUERY_EA_SIZE = 2;
  static const int SMB_INFO_QUERY_EAS_FROM_LIST = 3;
  static const int SMB_FIND_FILE_DIRECTORY_INFO = 0x101;
  static const int SMB_FIND_FILE_FULL_DIRECTORY_INFO = 0x102;
  static const int SMB_FILE_NAMES_INFO = 0x103;
  static const int SMB_FILE_BOTH_DIRECTORY_INFO = 0x104;

  /// These are all the smbs supported by this library. This includes requests
  /// and well as their responses for each type however the actuall implementations
  /// of the readXxxWireFormat and writeXxxWireFormat methods may not be in
  /// place. For example at the time of this writing the readXxxWireFormat
  /// for requests and the writeXxxWireFormat for responses are not implemented
  /// and simply return 0. These would need to be completed for a server
  /// implementation.
  static const int SMB_COM_CREATE_DIRECTORY = 0x00;
  static const int SMB_COM_DELETE_DIRECTORY = 0x01;
  static const int SMB_COM_CLOSE = 0x04;
  static const int SMB_COM_DELETE = 0x06;
  static const int SMB_COM_RENAME = 0x07;
  static const int SMB_COM_QUERY_INFORMATION = 0x08;
  static const int SMB_COM_SET_INFORMATION = 0x09;
  static const int SMB_COM_WRITE = 0x0B;
  static const int SMB_COM_CHECK_DIRECTORY = 0x10;
  static const int SMB_COM_SEEK = 0x12;
  static const int SMB_COM_LOCKING_ANDX = 0x24;
  static const int SMB_COM_TRANSACTION = 0x25;
  static const int SMB_COM_TRANSACTION_SECONDARY = 0x26;
  static const int SMB_COM_MOVE = 0x2A;
  static const int SMB_COM_ECHO = 0x2B;
  static const int SMB_COM_OPEN_ANDX = 0x2D;
  static const int SMB_COM_READ_ANDX = 0x2E;
  static const int SMB_COM_WRITE_ANDX = 0x2F;
  static const int SMB_COM_TRANSACTION2 = 0x32;
  static const int SMB_COM_FIND_CLOSE2 = 0x34;
  static const int SMB_COM_TREE_DISCONNECT = 0x71;
  static const int SMB_COM_NEGOTIATE = 0x72;
  static const int SMB_COM_SESSION_SETUP_ANDX = 0x73;
  static const int SMB_COM_LOGOFF_ANDX = 0x74;
  static const int SMB_COM_TREE_CONNECT_ANDX = 0x75;
  static const int SMB_COM_NT_TRANSACT = 0xA0;
  static const int SMB_COM_NT_CANCEL = 0xA4;
  static const int SMB_COM_NT_TRANSACT_SECONDARY = 0xA1;
  static const int SMB_COM_NT_CREATE_ANDX = 0xA2;

  static const SMB_COM_NEGOTIATE_STR = "SMB_COM_NEGOTIATE";
  static const SMB_COM_SESSION_SETUP_ANDX_STR = "SMB_COM_SESSION_SETUP_ANDX";
  static const SMB_COM_TREE_CONNECT_ANDX_STR = "SMB_COM_TREE_CONNECT_ANDX";
  static const SMB_COM_QUERY_INFORMATION_STR = "SMB_COM_QUERY_INFORMATION";
  static const SMB_COM_CHECK_DIRECTORY_STR = "SMB_COM_CHECK_DIRECTORY";
  static const SMB_COM_TRANSACTION_STR = "SMB_COM_TRANSACTION";
  static const SMB_COM_TRANSACTION2_STR = "SMB_COM_TRANSACTION2";
  static const SMB_COM_TRANSACTION_SECONDARY_STR =
      "SMB_COM_TRANSACTION_SECONDARY";
  static const SMB_COM_FIND_CLOSE2_STR = "SMB_COM_FIND_CLOSE2";
  static const SMB_COM_TREE_DISCONNECT_STR = "SMB_COM_TREE_DISCONNECT";
  static const SMB_COM_LOGOFF_ANDX_STR = "SMB_COM_LOGOFF_ANDX";
  static const SMB_COM_ECHO_STR = "SMB_COM_ECHO";
  static const SMB_COM_MOVE_STR = "SMB_COM_MOVE";
  static const SMB_COM_RENAME_STR = "SMB_COM_RENAME";
  static const SMB_COM_DELETE_STR = "SMB_COM_DELETE";
  static const SMB_COM_DELETE_DIRECTORY_STR = "SMB_COM_DELETE_DIRECTORY";
  static const SMB_COM_NT_CREATE_ANDX_STR = "SMB_COM_NT_CREATE_ANDX";
  static const SMB_COM_OPEN_ANDX_STR = "SMB_COM_OPEN_ANDX";
  static const SMB_COM_READ_ANDX_STR = "SMB_COM_READ_ANDX";
  static const SMB_COM_CLOSE_STR = "SMB_COM_CLOSE";
  static const SMB_COM_WRITE_ANDX_STR = "SMB_COM_WRITE_ANDX";
  static const SMB_COM_CREATE_DIRECTORY_STR = "SMB_COM_CREATE_DIRECTORY";
  static const SMB_COM_NT_TRANSACT_STR = "SMB_COM_NT_TRANSACT";
  static const SMB_COM_NT_TRANSACT_SECONDARY_STR =
      "SMB_COM_NT_TRANSACT_SECONDARY";
  static const SMB_COM_LOCKING_ANDX_STR = "SMB_COM_LOCKING_ANDX";

  static String commandToString(int cmd) {
    String c;
    switch (cmd) {
      case SMB_COM_NEGOTIATE:
        c = SMB_COM_NEGOTIATE_STR;
        break;
      case SMB_COM_SESSION_SETUP_ANDX:
        c = SMB_COM_SESSION_SETUP_ANDX_STR;
        break;
      case SMB_COM_TREE_CONNECT_ANDX:
        c = SMB_COM_TREE_CONNECT_ANDX_STR;
        break;
      case SMB_COM_QUERY_INFORMATION:
        c = SMB_COM_QUERY_INFORMATION_STR;
        break;
      case SMB_COM_CHECK_DIRECTORY:
        c = SMB_COM_CHECK_DIRECTORY_STR;
        break;
      case SMB_COM_TRANSACTION:
        c = SMB_COM_TRANSACTION_STR;
        break;
      case SMB_COM_TRANSACTION2:
        c = SMB_COM_TRANSACTION2_STR;
        break;
      case SMB_COM_TRANSACTION_SECONDARY:
        c = SMB_COM_TRANSACTION_SECONDARY_STR;
        break;
      case SMB_COM_FIND_CLOSE2:
        c = SMB_COM_FIND_CLOSE2_STR;
        break;
      case SMB_COM_TREE_DISCONNECT:
        c = SMB_COM_TREE_DISCONNECT_STR;
        break;
      case SMB_COM_LOGOFF_ANDX:
        c = SMB_COM_LOGOFF_ANDX_STR;
        break;
      case SMB_COM_ECHO:
        c = SMB_COM_ECHO_STR;
        break;
      case SMB_COM_MOVE:
        c = SMB_COM_MOVE_STR;
        break;
      case SMB_COM_RENAME:
        c = SMB_COM_RENAME_STR;
        break;
      case SMB_COM_DELETE:
        c = SMB_COM_DELETE_STR;
        break;
      case SMB_COM_DELETE_DIRECTORY:
        c = SMB_COM_DELETE_DIRECTORY_STR;
        break;
      case SMB_COM_NT_CREATE_ANDX:
        c = SMB_COM_NT_CREATE_ANDX_STR;
        break;
      case SMB_COM_OPEN_ANDX:
        c = SMB_COM_OPEN_ANDX_STR;
        break;
      case SMB_COM_READ_ANDX:
        c = SMB_COM_READ_ANDX_STR;
        break;
      case SMB_COM_CLOSE:
        c = SMB_COM_CLOSE_STR;
        break;
      case SMB_COM_WRITE_ANDX:
        c = SMB_COM_WRITE_ANDX_STR;
        break;
      case SMB_COM_CREATE_DIRECTORY:
        c = SMB_COM_CREATE_DIRECTORY_STR;
        break;
      case SMB_COM_NT_TRANSACT:
        c = SMB_COM_NT_TRANSACT_STR;
        break;
      case SMB_COM_NT_TRANSACT_SECONDARY:
        c = SMB_COM_NT_TRANSACT_SECONDARY_STR;
        break;
      case SMB_COM_LOCKING_ANDX:
        c = SMB_COM_LOCKING_ANDX_STR;
        break;
      default:
        c = "UNKNOWN";
    }
    return c;
  }
}
