import 'package:smb_connect/src/dcerpc/ndr/ndr_buffer.dart';
import 'package:smb_connect/src/dcerpc/ndr/ndr_object.dart';

class NdrLong extends NdrObject {
  int value;

  NdrLong(this.value);

  @override
  void encode(NdrBuffer dst) {
    dst.encNdrLong(value);
  }

  @override
  void decode(NdrBuffer src) {
    value = src.decNdrLong();
  }
}
