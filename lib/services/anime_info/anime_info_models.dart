part of 'anime_info_service.dart';

class DandanplayFileMatchArgument {

  final String fileName;
  final String fileHash;
  final int    fileSize;

  DandanplayFileMatchArgument({
    required this.fileName,
    required this.fileHash,
    required this.fileSize,
  });
}

class DandanplayFileMatchResult {

  final int    dandanplayAnimeId;
  final int    dandanplayEpisodeId;
  final double danmakuOffset;

  DandanplayFileMatchResult({
    required this.dandanplayAnimeId,
    required this.dandanplayEpisodeId,
    required this.danmakuOffset,
  });
}

typedef _AnimeEpisodeDebugTitles = ({
  Map<int, String> dandanplayAnime,
  Map<int, String> bangumiAnime,
  Map<int, String> dandanplayEpisode,
  Map<int, String> bangumiEpisode,
});


class FileInfo {

  final String fileDirectory;       // 文件所在目录
  final String fileNameNoExtension; // 文件名 (不含扩展名)
  final String fileExtension;       // 文件扩展名 (不含点号)
  final int    fileSize;            // 文件大小 (字节)

  final Uint8List  filePre16MiBMd5Hash; // 文件前 16MiB 的 MD5 哈希值
  final Uint8List? fileSha256Hash;      // 文件的 SHA256 哈希值 (可选)

  FileInfo({
    required this.fileDirectory,
    required this.fileNameNoExtension,
    required this.fileExtension,
    required this.fileSize,
    required this.filePre16MiBMd5Hash,
    this.fileSha256Hash,
  });

  DandanplayFileMatchArgument toDandanplayFileMatchArgument() {
    return DandanplayFileMatchArgument(
      fileName: '$fileNameNoExtension.$fileExtension',
      fileHash: encodeHex(filePre16MiBMd5Hash),
      fileSize: fileSize,
    );
  }

  DbAssetRecord toDbAssetRecord() {
    return DbAssetRecord(
      hashPre16MiBMd5: filePre16MiBMd5Hash,
      size: fileSize,
      codec: fileExtension,
      hashSha256: fileSha256Hash,
    );
  }
}