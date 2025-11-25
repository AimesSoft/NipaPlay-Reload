import 'ndr_buffer.dart';

abstract class NdrObject {
  void encode(NdrBuffer dst);
  void decode(NdrBuffer src);
}
