class MediaSourceUtils {
  MediaSourceUtils._();

  static bool isSmbPath(String filePath) {
    if (filePath.isEmpty) return false;
    final lower = filePath.toLowerCase();
    if (lower.startsWith('smb://')) return true;
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return false;
    }

    final uri = Uri.tryParse(filePath);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    if (host != '127.0.0.1' && host != 'localhost' && host != '::1') {
      return false;
    }
    return uri.path.startsWith('/smb/');
  }
}

