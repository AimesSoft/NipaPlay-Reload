import 'package:smb_connect/src/encodable.dart';

abstract class NegotiateContextRequest extends Encodable {
  int getContextType();
}
