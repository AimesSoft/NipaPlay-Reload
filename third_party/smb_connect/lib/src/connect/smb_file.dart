import 'package:smb_connect/src/connect/fscc/smb_basic_file_info.dart';
import 'package:smb_connect/src/smb_constants.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/strings.dart';

class SmbFile {
  late final String name;
  final String path;
  final String uncPath;
  final String share;

  final int createTime;
  final int lastModified;
  final int lastAccess;
  final int attributes;
  // final int attrExpiration;
  final int size;
  // final int sizeExpiration;
  final bool isExists;

  SmbFile(
      this.path,
      this.uncPath,
      this.share,
      // this.fileId,
      // this.fid,
      this.createTime,
      this.lastModified,
      this.lastAccess,
      this.attributes,
      // this.attrExpiration,
      this.size,
      // this.sizeExpiration,
      this.isExists) {
    name = path.filename(pathSeparator: PATH_DIV);
  }

  SmbFile.info(String path, String uncPath, String share, SmbBasicFileInfo info)
      : this(
            path,
            uncPath,
            share,
            info.getCreateTime(),
            info.getLastWriteTime(),
            info.getLastAccessTime(),
            info.getAttributes() & SmbFile.ATTR_GET_MASK,
            info.getSize(),
            true);

  SmbFile.standard(
      String path, String uncPath, String share, SmbBasicFileInfo info)
      : this(
            path,
            uncPath,
            share,
            info.getCreateTime(),
            info.getLastWriteTime(),
            info.getLastAccessTime(),
            info.getAttributes() & SmbFile.ATTR_GET_MASK,
            info.getSize(),
            true);

  SmbFile.notExists(
    String path,
    String uncPath,
    String share,
  ) : this(path, uncPath, share, 0, 0, 0, 0, 0, false);

  bool isDirectory() => attributes.isFlag(SmbConstants.ATTR_DIRECTORY);
  bool isFile() => !isDirectory();
  bool isArchive() => attributes.isFlag(SmbConstants.ATTR_ARCHIVE);
  bool isCompressed() => attributes.isFlag(SmbConstants.ATTR_COMPRESSED);
  bool isHidden() => attributes.isFlag(SmbConstants.ATTR_HIDDEN);
  bool isReadonly() => attributes.isFlag(SmbConstants.ATTR_READONLY);
  bool isSystem() => attributes.isFlag(SmbConstants.ATTR_SYSTEM);
  bool isTemporary() => attributes.isFlag(SmbConstants.ATTR_TEMPORARY);
  bool isVolume() => attributes.isFlag(SmbConstants.ATTR_VOLUME);

  bool canRead() => isExists;
  bool canWrite() => isExists && (attributes & SmbConstants.ATTR_READONLY) == 0;

  @override
  String toString() {
    return 'SmbFile(name: $name, path: $path, uncPath: $uncPath, share: $share, createTime: $createTime, lastModified: $lastModified, lastAccess: $lastAccess, attributes: $attributes, size: $size, isExists: $isExists)';
  }

  static const int ATTR_GET_MASK = 0x7FFF;
  static const String PATH_DIV = "/";
  static const NAME_DOT = ".";
  static const NAME_DOT_DOT = "..";
}
