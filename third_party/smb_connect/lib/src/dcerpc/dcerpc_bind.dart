import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/dcerpc/dcerpc_binding.dart';
import 'package:smb_connect/src/dcerpc/dcerpc_constants.dart';
import 'package:smb_connect/src/dcerpc/dcerpc_message.dart';
import 'package:smb_connect/src/dcerpc/ndr/ndr_buffer.dart';
import 'package:smb_connect/src/utils/strings.dart';

class DcerpcBind extends DcerpcMessage {
  static final List<String> resultMessage = [
    "0",
    "DcerpcConstants.DCERPC_BIND_ERR_ABSTRACT_SYNTAX_NOT_SUPPORTED",
    "DcerpcConstants.DCERPC_BIND_ERR_PROPOSED_TRANSFER_SYNTAXES_NOT_SUPPORTED",
    "DcerpcConstants.DCERPC_BIND_ERR_LOCAL_LIMIT_EXCEEDED"
  ];

  static String _getResultMessage(int result) {
    return result < 4
        ? resultMessage[result]
        : "0x${Hexdump.toHexString(result, 4)}";
  }

  @override
  DcerpcException? getResult() {
    if (result != 0) return DcerpcException(_getResultMessage(result));
    return null;
  }

  DcerpcBinding? binding;
  final int _maxXmit, _maxRecv;

  DcerpcBind({this.binding, int? maxXmit, int? maxRecv})
      : _maxXmit = maxXmit ?? 0,
        _maxRecv = maxRecv ?? 0 {
    ptype = 11;
    flags =
        DcerpcConstants.DCERPC_FIRST_FRAG | DcerpcConstants.DCERPC_LAST_FRAG;
  }

  @override
  int getOpnum() {
    return 0;
  }

  @override
  void encodeIn(NdrBuffer buf) {
    buf.encNdrShort(_maxXmit);
    buf.encNdrShort(_maxRecv);
    buf.encNdrLong(0); /* assoc. group */
    buf.encNdrSmall(1); /* num context items */
    buf.encNdrSmall(0); /* reserved */
    buf.encNdrShort(0); /* reserved2 */
    buf.encNdrShort(0); /* context id */
    buf.encNdrSmall(1); /* number of items */
    buf.encNdrSmall(0); /* reserved */
    binding!.getUuid()!.encode(buf);
    buf.encNdrShort(binding!.getMajor());
    buf.encNdrShort(binding!.getMinor());
    DcerpcConstants.DCERPC_UUID_SYNTAX_NDR.encode(buf);
    buf.encNdrLong(2); /* syntax version */
  }

  @override
  void decodeOut(NdrBuffer buf) {
    buf.decNdrShort(); /* max transmit frag size */
    buf.decNdrShort(); /* max receive frag size */
    buf.decNdrLong(); /* assoc. group */
    int n = buf.decNdrShort(); /* secondary addr len */
    buf.advance(n); /* secondary addr */
    buf.align(4);
    buf.decNdrSmall(); /* num results */
    buf.align(4);
    result = buf.decNdrShort();
    buf.decNdrShort();
    buf.advance(20); /* transfer syntax / version */
  }
}
