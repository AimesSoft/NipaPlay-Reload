import 'package:smb_connect/src/connect/common/common_server_message_block_response.dart';

abstract class TreeConnectResponse extends CommonServerMessageBlockResponse {
  int getTid();
}
