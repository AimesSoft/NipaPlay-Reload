/// URL名称生成工具类
class UrlNameGenerator {
  /// 根据URL生成地址名称
  /// 如果提供了自定义名称，则使用自定义名称；否则根据URL特征自动生成
  static String generateAddressName(String url, {String? customName}) {
    // 如果提供了自定义名称且不为空，直接使用
    if (customName != null && customName.trim().isNotEmpty) {
      return customName.trim();
    }
    
    // 根据URL自动生成名称
    return _generateNameFromUrl(url);
  }
  
  /// 根据URL特征自动生成名称
  static String _generateNameFromUrl(String url) {
    final lowercaseUrl = url.toLowerCase();
    
    // 本地地址
    if (lowercaseUrl.contains('localhost') || lowercaseUrl.contains('127.0.0.1')) {
      return '本地';
    }
    
    // 局域网地址
    if (lowercaseUrl.contains('192.168') || 
        lowercaseUrl.contains('10.') || 
        (lowercaseUrl.contains('172.') && _isPrivateIPRange172(url))) {
      return '局域网';
    }
    
    // 其他情况默认为公网
    return '公网';
  }
  
  /// 检查是否为172.16.0.0到172.31.255.255的私有IP范围
  static bool _isPrivateIPRange172(String url) {
    final regex = RegExp(r'172\.(\d+)\.');
    final match = regex.firstMatch(url);
    if (match != null) {
      final secondOctet = int.tryParse(match.group(1) ?? '');
      return secondOctet != null && secondOctet >= 16 && secondOctet <= 31;
    }
    return false;
  }
  
  /// 为首次连接生成服务器名称建议
  static String generateServerNameSuggestion(String url, String serverType) {
    final baseName = _generateNameFromUrl(url);
    return '$serverType服务器 - $baseName';
  }
}
