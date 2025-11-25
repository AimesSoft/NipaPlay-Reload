import 'package:smb_connect/src/connect/transport/response.dart';

import 'message.dart';

abstract class Request extends Message {
  /// number of credits this request requires
  int getCreditCost();

  /// credits
  void setRequestCredits(int credits);

  /// whether this is a cancel request
  // bool isCancel();

  /// chained request
  Request? getNext();

  /// the response for this request
  Response? getResponse();
}
