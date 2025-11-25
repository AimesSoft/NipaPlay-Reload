import 'package:smb_connect/src/connect/fscc/file_system_information.dart';

abstract class AllocInfo extends FileSystemInformation {
  int getCapacity();

  // int getFree();
}
