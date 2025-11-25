import 'uuid.dart';

abstract class DcerpcConstants {
  static final UUID DCERPC_UUID_SYNTAX_NDR =
      UUID.str("8a885d04-1ceb-11c9-9fe8-08002b104860");

  /// First fragment
  static const int DCERPC_FIRST_FRAG = 0x01;

  /// Last fragment
  static const int DCERPC_LAST_FRAG = 0x02;

  /// Cancel was pending at sender
  static const int DCERPC_PENDING_CANCEL = 0x04;
  static const int DCERPC_RESERVED_1 = 0x08;

  /// supports concurrent multiplexing
  static const int DCERPC_CONC_MPX = 0x10;
  static const int DCERPC_DID_NOT_EXECUTE = 0x20;

  /// `maybe' call semantics requested
  static const int DCERPC_MAYBE = 0x40;

  /// if true, a non-nil object UUID
  static const int DCERPC_OBJECT_UUID = 0x80;
}
