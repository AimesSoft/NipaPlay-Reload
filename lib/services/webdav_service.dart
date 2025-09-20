import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

class WebDAVConnection {
  final String name;
  final String url;
  final String username;
  final String password;
  final bool isConnected;
  
  WebDAVConnection({
    required this.name,
    required this.url,
    required this.username,
    required this.password,
    this.isConnected = false,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'url': url,
      'username': username,
      'password': password,
      'isConnected': isConnected,
    };
  }
  
  factory WebDAVConnection.fromJson(Map<String, dynamic> json) {
    return WebDAVConnection(
      name: json['name'] ?? '',
      url: json['url'] ?? '',
      username: json['username'] ?? '',
      password: json['password'] ?? '',
      isConnected: json['isConnected'] ?? false,
    );
  }
  
  WebDAVConnection copyWith({
    String? name,
    String? url,
    String? username,
    String? password,
    bool? isConnected,
  }) {
    return WebDAVConnection(
      name: name ?? this.name,
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
      isConnected: isConnected ?? this.isConnected,
    );
  }
}

class WebDAVFile {
  final String name;
  final String path;
  final bool isDirectory;
  final int? size;
  final DateTime? lastModified;
  
  WebDAVFile({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size,
    this.lastModified,
  });
}

class WebDAVService {
  static const String _connectionsKey = 'webdav_connections';
  static WebDAVService? _instance;
  
  static WebDAVService get instance {
    _instance ??= WebDAVService._();
    return _instance!;
  }
  
  WebDAVService._();
  
  List<WebDAVConnection> _connections = [];
  
  List<WebDAVConnection> get connections => List.unmodifiable(_connections);
  
  /// 初始化，加载保存的连接
  Future<void> initialize() async {
    await _loadConnections();
  }
  
  /// 加载保存的连接
  Future<void> _loadConnections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final connectionsJson = prefs.getString(_connectionsKey);
      if (connectionsJson != null) {
        final List<dynamic> decoded = json.decode(connectionsJson);
        _connections = decoded.map((e) => WebDAVConnection.fromJson(e)).toList();
      }
    } catch (e) {
      print('加载WebDAV连接失败: $e');
    }
  }
  
  /// 保存连接到本地存储
  Future<void> _saveConnections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final connectionsJson = json.encode(_connections.map((e) => e.toJson()).toList());
      await prefs.setString(_connectionsKey, connectionsJson);
    } catch (e) {
      print('保存WebDAV连接失败: $e');
    }
  }
  
  /// 添加新的WebDAV连接
  Future<bool> addConnection(WebDAVConnection connection) async {
    try {
      // 测试连接
      final isValid = await testConnection(connection);
      if (isValid) {
        _connections.add(connection.copyWith(isConnected: true));
        await _saveConnections();
        return true;
      }
      return false;
    } catch (e) {
      print('添加WebDAV连接失败: $e');
      return false;
    }
  }
  
  /// 删除WebDAV连接
  Future<void> removeConnection(String name) async {
    _connections.removeWhere((conn) => conn.name == name);
    await _saveConnections();
  }
  
  /// 测试WebDAV连接
  Future<bool> testConnection(WebDAVConnection connection) async {
    try {
      print('🔍 测试WebDAV连接: ${connection.url}');
      
      // 验证URL格式
      Uri uri;
      try {
        uri = Uri.parse(connection.url);
        print('✅ URL解析成功: ${uri.toString()}');
        print('  协议: ${uri.scheme}');
        print('  主机: ${uri.host}');
        print('  端口: ${uri.port}');
        print('  路径: ${uri.path}');
      } catch (e) {
        print('❌ URL格式错误: $e');
        return false;
      }
      
      // 检查协议
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        print('❌ 不支持的协议: ${uri.scheme}，仅支持 http 和 https');
        return false;
      }
      
      // 准备认证信息
      String credentials = '';
      if (connection.username.isNotEmpty || connection.password.isNotEmpty) {
        credentials = base64Encode(utf8.encode('${connection.username}:${connection.password}'));
        print('🔐 认证信息已准备 (用户名: ${connection.username})');
      } else {
        print('ℹ️ 未提供认证信息，尝试匿名访问');
      }
      
      print('📡 发送WebDAV PROPFIND请求...');
      final headers = <String, String>{
        'User-Agent': 'NipaPlay/1.0',
        'Content-Type': 'application/xml',
        'Depth': '0', // 只获取当前目录信息
      };
      
      if (credentials.isNotEmpty) {
        headers['Authorization'] = 'Basic $credentials';
      }
      
      // 使用PROPFIND方法测试WebDAV连接
      final request = http.Request('PROPFIND', uri);
      request.headers.addAll(headers);
      request.body = '''<?xml version="1.0" encoding="utf-8" ?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:resourcetype/>
  </D:prop>
</D:propfind>''';
      
      final streamedResponse = await request.send().timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamedResponse);
      
      print('📥 收到响应: ${response.statusCode}');
      print('📄 响应头: ${response.headers}');
      
      if (response.body.isNotEmpty && response.body.length < 2000) {
        print('📄 响应体: ${response.body}');
      } else {
        print('📄 响应体长度: ${response.body.length} 字符');
      }
      
      // WebDAV PROPFIND的成功状态码
      final isSuccess = response.statusCode == 207 || // Multi-Status (WebDAV标准)
                       response.statusCode == 200 || // OK
                       response.statusCode == 301 || // Moved Permanently
                       response.statusCode == 302;   // Found
      
      if (response.statusCode == 401) {
        print('❌ 认证失败 (401)，请检查用户名和密码');
      } else if (response.statusCode == 403) {
        print('❌ 访问被拒绝 (403)，请检查权限设置');
      } else if (response.statusCode == 404) {
        print('❌ 路径不存在 (404)，请检查WebDAV路径');
      } else if (response.statusCode == 405) {
        print('⚠️ 方法不被允许 (405)，服务器可能不支持PROPFIND，尝试备用方法...');
        // 如果PROPFIND不支持，尝试OPTIONS方法
        return await _testWithOptions(connection);
      } else if (response.statusCode >= 500) {
        print('❌ 服务器错误 (${response.statusCode})');
      }
      
      print(isSuccess ? '✅ WebDAV连接成功!' : '❌ WebDAV连接失败 (状态码: ${response.statusCode})');
      
      return isSuccess;
    } catch (e, stackTrace) {
      print('❌ 测试WebDAV连接异常: $e');
      if (e.toString().contains('SocketException')) {
        print('🌐 网络连接问题，请检查：');
        print('  1. 服务器地址是否正确');
        print('  2. 网络连接是否正常');
        print('  3. 防火墙是否阻挡');
      } else if (e.toString().contains('TimeoutException')) {
        print('⏱️ 连接超时，请检查：');
        print('  1. 服务器是否响应');
        print('  2. 网络延迟是否过高');
      } else if (e.toString().contains('FormatException')) {
        print('📝 URL格式错误，请检查地址格式');
      }
      print('📍 堆栈跟踪: $stackTrace');
      return false;
    }
  }
  
  /// 使用OPTIONS方法测试连接（备用方法）
  Future<bool> _testWithOptions(WebDAVConnection connection) async {
    try {
      print('🔄 尝试OPTIONS方法测试连接...');
      final uri = Uri.parse(connection.url);
      
      final headers = <String, String>{
        'User-Agent': 'NipaPlay/1.0',
      };
      
      if (connection.username.isNotEmpty || connection.password.isNotEmpty) {
        final credentials = base64Encode(utf8.encode('${connection.username}:${connection.password}'));
        headers['Authorization'] = 'Basic $credentials';
      }
      
      final request = http.Request('OPTIONS', uri);
      request.headers.addAll(headers);
      
      final streamedResponse = await request.send().timeout(const Duration(seconds: 10));
      final response = await http.Response.fromStream(streamedResponse);
      
      print('📥 OPTIONS响应: ${response.statusCode}');
      print('📄 支持的方法: ${response.headers['allow'] ?? 'unknown'}');
      
      final isSuccess = response.statusCode == 200 || response.statusCode == 204;
      print(isSuccess ? '✅ OPTIONS连接成功!' : '❌ OPTIONS连接失败');
      
      return isSuccess;
    } catch (e) {
      print('❌ OPTIONS方法也失败: $e');
      return false;
    }
  }
  
  /// 获取WebDAV目录内容
  Future<List<WebDAVFile>> listDirectory(WebDAVConnection connection, String path) async {
    try {
      print('📂 获取WebDAV目录内容: ${connection.name}:$path');
      
      // 构建正确的URL
      Uri uri;
      if (path == '/' || path.isEmpty) {
        // 根目录，直接使用connection.url
        uri = Uri.parse(connection.url);
      } else if (path.startsWith('/')) {
        // 绝对路径，使用服务器base + path
        final baseUri = Uri.parse(connection.url);
        uri = Uri(
          scheme: baseUri.scheme,
          host: baseUri.host,
          port: baseUri.port,
          path: path,
        );
      } else {
        // 相对路径，拼接到connection.url
        uri = Uri.parse('${connection.url.replaceAll(RegExp(r'/$'), '')}/$path');
      }
      
      print('🔗 请求URL: $uri');
      
      final credentials = base64Encode(utf8.encode('${connection.username}:${connection.password}'));
      
      final request = http.Request('PROPFIND', uri);
      request.headers.addAll({
        'Authorization': 'Basic $credentials',
        'User-Agent': 'NipaPlay/1.0',
        'Depth': '1', // 获取当前目录和直接子项
        'Content-Type': 'application/xml',
      });
      
      request.body = '''<?xml version="1.0" encoding="utf-8" ?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:displayname/>
    <D:getcontentlength/>
    <D:getlastmodified/>
    <D:resourcetype/>
  </D:prop>
</D:propfind>''';

      print('📡 发送PROPFIND请求...');
      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();
      
      print('📥 收到响应: ${streamedResponse.statusCode}');
      print('📄 响应体长度: ${responseBody.length}');
      
      if (responseBody.length < 2000) {
        print('📄 响应体内容: $responseBody');
      }
      
      if (streamedResponse.statusCode != 207 && streamedResponse.statusCode != 200) {
        print('❌ PROPFIND失败: ${streamedResponse.statusCode}');
        throw Exception('WebDAV PROPFIND failed: ${streamedResponse.statusCode}');
      }
      
      final files = _parseWebDAVResponse(responseBody, path);
      print('📁 解析到 ${files.length} 个项目');
      
      return files;
    } catch (e, stackTrace) {
      print('❌ 获取WebDAV目录内容失败: $e');
      print('📍 堆栈跟踪: $stackTrace');
      throw e;
    }
  }
  
  /// 解析WebDAV PROPFIND响应
  List<WebDAVFile> _parseWebDAVResponse(String xmlResponse, String basePath) {
    final List<WebDAVFile> files = [];
    
    try {
      print('🔍 开始解析WebDAV响应...');
      print('📄 原始XML前500字符: ${xmlResponse.substring(0, xmlResponse.length > 500 ? 500 : xmlResponse.length)}');
      
      final document = XmlDocument.parse(xmlResponse);
      
      // 尝试不同的response元素查找方式
      var responses = document.findAllElements('response');
      if (responses.isEmpty) {
        responses = document.findAllElements('d:response');
      }
      if (responses.isEmpty) {
        responses = document.findAllElements('D:response');
      }
      if (responses.isEmpty) {
        // 尝试忽略命名空间查找
        responses = document.descendants.where((node) => 
          node is XmlElement && 
          (node.name.local.toLowerCase() == 'response')
        ).cast<XmlElement>();
      }
      
      print('📋 找到 ${responses.length} 个response元素');
      
      if (responses.isEmpty) {
        print('⚠️ 未找到任何response元素，打印完整XML结构：');
        print('📄 完整XML: $xmlResponse');
        return files;
      }
      
      for (final response in responses) {
        try {
          // 尝试多种href查找方式
          var hrefElements = response.findElements('href');
          if (hrefElements.isEmpty) {
            hrefElements = response.findElements('d:href');
          }
          if (hrefElements.isEmpty) {
            hrefElements = response.findElements('D:href');
          }
          if (hrefElements.isEmpty) {
            hrefElements = response.descendants.where((node) => 
              node is XmlElement && 
              node.name.local.toLowerCase() == 'href'
            ).cast<XmlElement>();
          }
          
          if (hrefElements.isEmpty) {
            print('⚠️ 跳过：没有href元素');
            continue;
          }
          
          final href = hrefElements.first.text;
          print('📎 处理href: $href');
          
          // 跳过当前目录本身，但要更精确的匹配
          final normalizedHref = href.endsWith('/') ? href.substring(0, href.length - 1) : href;
          final normalizedBasePath = basePath.endsWith('/') ? basePath.substring(0, basePath.length - 1) : basePath;
          
          if (normalizedHref == normalizedBasePath || href == basePath || href == '$basePath/') {
            print('📂 跳过当前目录: $href');
            continue;
          }
          
          // 尝试多种propstat查找方式
          var propstatElements = response.findElements('propstat');
          if (propstatElements.isEmpty) {
            propstatElements = response.findElements('d:propstat');
          }
          if (propstatElements.isEmpty) {
            propstatElements = response.findElements('D:propstat');
          }
          if (propstatElements.isEmpty) {
            propstatElements = response.descendants.where((node) => 
              node is XmlElement && 
              node.name.local.toLowerCase() == 'propstat'
            ).cast<XmlElement>();
          }
          
          if (propstatElements.isEmpty) {
            print('⚠️ 跳过：没有propstat元素');
            continue;
          }
          
          final propstat = propstatElements.first;
          
          // 尝试多种prop查找方式
          var propElements = propstat.findElements('prop');
          if (propElements.isEmpty) {
            propElements = propstat.findElements('d:prop');
          }
          if (propElements.isEmpty) {
            propElements = propstat.findElements('D:prop');
          }
          if (propElements.isEmpty) {
            propElements = propstat.descendants.where((node) => 
              node is XmlElement && 
              node.name.local.toLowerCase() == 'prop'
            ).cast<XmlElement>();
          }
          
          if (propElements.isEmpty) {
            print('⚠️ 跳过：没有prop元素');
            continue;
          }
          
          final prop = propElements.first;
          
          // 获取显示名称 - 尝试多种方式
          var displayNameElements = prop.findElements('displayname');
          if (displayNameElements.isEmpty) {
            displayNameElements = prop.findElements('d:displayname');
          }
          if (displayNameElements.isEmpty) {
            displayNameElements = prop.findElements('D:displayname');
          }
          if (displayNameElements.isEmpty) {
            displayNameElements = prop.descendants.where((node) => 
              node is XmlElement && 
              node.name.local.toLowerCase() == 'displayname'
            ).cast<XmlElement>();
          }
          
          String displayName = '';
          if (displayNameElements.isNotEmpty) {
            displayName = displayNameElements.first.text;
          }
          
          // 如果没有displayname，从href中提取
          if (displayName.isEmpty) {
            displayName = Uri.decodeComponent(href.split('/').where((s) => s.isNotEmpty).last);
            if (displayName.isEmpty) {
              displayName = href;
            }
          }
          
          print('📝 显示名称: $displayName');
          
          // 检查是否为目录 - 尝试多种方式
          var resourceTypeElements = prop.findElements('resourcetype');
          if (resourceTypeElements.isEmpty) {
            resourceTypeElements = prop.findElements('d:resourcetype');
          }
          if (resourceTypeElements.isEmpty) {
            resourceTypeElements = prop.findElements('D:resourcetype');
          }
          if (resourceTypeElements.isEmpty) {
            resourceTypeElements = prop.descendants.where((node) => 
              node is XmlElement && 
              node.name.local.toLowerCase() == 'resourcetype'
            ).cast<XmlElement>();
          }
          
          bool isDirectory = false;
          if (resourceTypeElements.isNotEmpty) {
            final resourceType = resourceTypeElements.first;
            var collectionElements = resourceType.findElements('collection');
            if (collectionElements.isEmpty) {
              collectionElements = resourceType.findElements('d:collection');
            }
            if (collectionElements.isEmpty) {
              collectionElements = resourceType.findElements('D:collection');
            }
            if (collectionElements.isEmpty) {
              collectionElements = resourceType.descendants.where((node) => 
                node is XmlElement && 
                node.name.local.toLowerCase() == 'collection'
              ).cast<XmlElement>();
            }
            isDirectory = collectionElements.isNotEmpty;
          }
          
          print('📁 是否为目录: $isDirectory');
          
          // 获取文件大小
          int? size;
          if (!isDirectory) {
            var contentLengthElements = prop.findElements('getcontentlength');
            if (contentLengthElements.isEmpty) {
              contentLengthElements = prop.findElements('d:getcontentlength');
            }
            if (contentLengthElements.isEmpty) {
              contentLengthElements = prop.findElements('D:getcontentlength');
            }
            if (contentLengthElements.isEmpty) {
              contentLengthElements = prop.descendants.where((node) => 
                node is XmlElement && 
                node.name.local.toLowerCase() == 'getcontentlength'
              ).cast<XmlElement>();
            }
            
            if (contentLengthElements.isNotEmpty) {
              size = int.tryParse(contentLengthElements.first.text);
            }
          }
          
          // 获取最后修改时间
          DateTime? lastModified;
          var lastModifiedElements = prop.findElements('getlastmodified');
          if (lastModifiedElements.isEmpty) {
            lastModifiedElements = prop.findElements('d:getlastmodified');
          }
          if (lastModifiedElements.isEmpty) {
            lastModifiedElements = prop.findElements('D:getlastmodified');
          }
          if (lastModifiedElements.isEmpty) {
            lastModifiedElements = prop.descendants.where((node) => 
              node is XmlElement && 
              node.name.local.toLowerCase() == 'getlastmodified'
            ).cast<XmlElement>();
          }
          
          if (lastModifiedElements.isNotEmpty) {
            try {
              lastModified = HttpDate.parse(lastModifiedElements.first.text);
            } catch (e) {
              print('⚠️ 解析修改时间失败: $e');
            }
          }
          
          // 添加所有目录，只对文件进行视频格式过滤
          if (isDirectory) {
            // 目录总是添加
            final file = WebDAVFile(
              name: displayName,
              path: href,
              isDirectory: isDirectory,
              size: size,
              lastModified: lastModified,
            );
            files.add(file);
            print('✅ 添加目录: $displayName');
          } else if (isVideoFile(displayName)) {
            // 只有视频文件才添加
            final file = WebDAVFile(
              name: displayName,
              path: href,
              isDirectory: isDirectory,
              size: size,
              lastModified: lastModified,
            );
            files.add(file);
            print('✅ 添加视频文件: $displayName');
          } else {
            print('⏭️ 跳过非视频文件: $displayName');
          }
        } catch (e) {
          print('❌ 解析单个response失败: $e');
          continue;
        }
      }
      
      print('📊 解析完成，共 ${files.length} 个有效项目');
      
    } catch (e) {
      print('❌ 解析WebDAV响应失败: $e');
      print('📄 完整XML: $xmlResponse');
    }
    
    return files;
  }
  
  /// 检查是否为视频文件
  bool isVideoFile(String filename) {
    final extension = filename.toLowerCase().split('.').last;
    return ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v'].contains(extension);
  }
  
  /// 获取WebDAV文件的下载URL
  String getFileUrl(WebDAVConnection connection, String filePath) {
    String finalUrl;
    
    // 如果filePath已经是完整的绝对路径（如 /dav/file.mp4），
    // 则使用服务器的base URL + filePath
    if (filePath.startsWith('/')) {
      final baseUri = Uri.parse(connection.url);
      
      // 如果有用户名和密码，在URL中包含认证信息
      if (connection.username.isNotEmpty && connection.password.isNotEmpty) {
        final uri = Uri(
          scheme: baseUri.scheme,
          userInfo: '${Uri.encodeComponent(connection.username)}:${Uri.encodeComponent(connection.password)}',
          host: baseUri.host,
          port: baseUri.port,
          path: filePath,
        );
        finalUrl = uri.toString();
      } else {
        final uri = Uri(
          scheme: baseUri.scheme,
          host: baseUri.host,
          port: baseUri.port,
          path: filePath,
        );
        finalUrl = uri.toString();
      }
    } else {
      // 如果是相对路径，拼接到connection.url
      if (connection.username.isNotEmpty && connection.password.isNotEmpty) {
        final baseUri = Uri.parse(connection.url);
        final uri = Uri(
          scheme: baseUri.scheme,
          userInfo: '${Uri.encodeComponent(connection.username)}:${Uri.encodeComponent(connection.password)}',
          host: baseUri.host,
          port: baseUri.port,
          path: '${baseUri.path}/$filePath',
        );
        finalUrl = uri.toString();
      } else {
        finalUrl = '${connection.url.replaceAll(RegExp(r'/$'), '')}/$filePath';
      }
    }
    
    print('🎥 生成播放URL: $filePath → $finalUrl');
    return finalUrl;
  }
  
  /// 获取连接状态
  Future<void> updateConnectionStatus(String name) async {
    final index = _connections.indexWhere((conn) => conn.name == name);
    if (index != -1) {
      final connection = _connections[index];
      final isConnected = await testConnection(connection);
      _connections[index] = connection.copyWith(isConnected: isConnected);
      await _saveConnections();
    }
  }
  
  /// 获取指定名称的连接
  WebDAVConnection? getConnection(String name) {
    try {
      return _connections.firstWhere((conn) => conn.name == name);
    } catch (e) {
      return null;
    }
  }
}