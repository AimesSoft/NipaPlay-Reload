import 'package:smb_connect/src/connect/common/common_server_message_block.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block_response.dart';

import '../transport/request.dart';

abstract class CommonServerMessageBlockRequest
    implements CommonServerMessageBlock, Request {
  @override
  CommonServerMessageBlockRequest? getNext();

  int size();

  void setTid(int t);

  /// custom response timeout for this request
  int? getOverrideTimeout();

  @override
  CommonServerMessageBlockResponse? getResponse();
}
