import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block_request.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block_response.dart';

abstract class Request<T extends CommonServerMessageBlockResponse>
    extends CommonServerMessageBlockRequest {
  T initResponse(Configuration config);

  @override
  T? getResponse();
}
