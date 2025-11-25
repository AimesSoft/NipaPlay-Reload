import 'package:smb_connect/src/decodable.dart';
import 'package:smb_connect/src/encodable.dart';

abstract class FileInformation implements Decodable, Encodable {
  // information levels
  static const int FILE_ENDOFFILE_INFO = 20;
  static const int FILE_BASIC_INFO = 0x4;
  static const int FILE_STANDARD_INFO = 0x5;
  static const int FILE_INTERNAL_INFO = 0x6;
  static const int FILE_RENAME_INFO = 10;

  /// the file information class
  int getFileInformationLevel();
}
