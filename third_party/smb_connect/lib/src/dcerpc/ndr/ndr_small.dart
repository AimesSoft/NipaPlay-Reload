import 'package:smb_connect/src/dcerpc/ndr/ndr_buffer.dart';
import 'package:smb_connect/src/dcerpc/ndr/ndr_object.dart';

class NdrSmall extends NdrObject {
  int value;

  NdrSmall(int v) : value = v & 0xFF;

  @override
  void encode(NdrBuffer dst) {
    dst.encNdrSmall(value);
  }

  @override
  void decode(NdrBuffer src) {
    value = src.decNdrSmall();
  }
}
