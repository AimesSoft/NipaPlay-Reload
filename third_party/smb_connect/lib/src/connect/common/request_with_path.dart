import 'package:smb_connect/src/connect/common/common_server_message_block.dart';

abstract class RequestWithPath extends CommonServerMessageBlock {
  String? getPath();

  String? getServer();

  String? getDomain();

  String? getFullUNCPath();

  void setPath(String path);

  void setFullUNCPath(String? domain, String? server, String? fullPath);

  void setResolveInDfs(bool resolve);

  bool isResolveInDfs();
}
