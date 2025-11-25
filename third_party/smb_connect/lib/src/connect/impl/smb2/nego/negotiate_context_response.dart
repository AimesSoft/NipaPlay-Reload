import 'package:smb_connect/src/decodable.dart';

abstract class NegotiateContextResponse extends Decodable {
  // @return context type
  int getContextType();
}
