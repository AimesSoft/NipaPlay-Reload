import 'package:smb_connect/src/decodable.dart';

abstract class FileSystemInformation extends Decodable {
  static const int SMB_INFO_ALLOCATION = -1;

  static const int FS_SIZE_INFO = 3;
  static const int FS_FULL_SIZE_INFO = 7;

  int getFileSystemInformationClass();
}
