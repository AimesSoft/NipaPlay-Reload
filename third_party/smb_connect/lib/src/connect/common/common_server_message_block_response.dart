import 'package:smb_connect/src/connect/common/common_server_message_block.dart';
import 'package:smb_connect/src/connect/transport/response.dart';

import 'common_server_message_block_request.dart';

abstract class CommonServerMessageBlockResponse
    implements CommonServerMessageBlock, Response {
  @override
  CommonServerMessageBlockResponse? getNextResponse();

  void prepare(CommonServerMessageBlockRequest next);
}
