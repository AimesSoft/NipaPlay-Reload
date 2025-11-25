abstract class FileEntry {
  String getName();
  int getType();
  int getAttributes();
  int createTime();
  int lastModified();
  int lastAccess();
  int length();
  int getFileIndex();
}
