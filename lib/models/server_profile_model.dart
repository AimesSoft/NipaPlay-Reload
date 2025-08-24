

/// 服务器配置文件模型，支持多地址管理
class ServerProfile {
  final String id; // 服务器唯一标识
  final String serverName; // 服务器名称
  final String serverType; // 服务器类型: emby, jellyfin
  final List<ServerAddress> addresses; // 多个地址列表
  final String username; // 用户名
  final String? serverId; // 远程服务器ID（Emby/Jellyfin服务器的唯一标识）
  String? accessToken; // 访问令牌
  String? userId; // 用户ID
  String? lastSuccessfulAddressId; // 最近成功连接的地址ID
  DateTime? lastConnectionTime; // 最后连接时间
  
  ServerProfile({
    required this.id,
    required this.serverName,
    required this.serverType,
    required this.addresses,
    required this.username,
    this.serverId,
    this.accessToken,
    this.userId,
    this.lastSuccessfulAddressId,
    this.lastConnectionTime,
  });

  /// 获取当前应该使用的地址（优先使用最近成功的地址）
  ServerAddress? get currentAddress {
    if (addresses.isEmpty) return null;
    
    // 优先使用最近成功连接的地址
    if (lastSuccessfulAddressId != null) {
      final lastAddress = addresses.firstWhere(
        (addr) => addr.id == lastSuccessfulAddressId,
        orElse: () => addresses.first,
      );
      if (lastAddress.isEnabled) return lastAddress;
    }
    
    // 返回第一个启用的地址
    return addresses.firstWhere(
      (addr) => addr.isEnabled,
      orElse: () => addresses.first,
    );
  }

  /// 获取所有启用的地址列表（按优先级排序）
  List<ServerAddress> get enabledAddresses {
    final List<ServerAddress> enabled = addresses.where((addr) => addr.isEnabled).toList();
    
    // 按优先级和最近成功时间排序
    enabled.sort((a, b) {
      // 最近成功的地址优先
      if (a.id == lastSuccessfulAddressId) return -1;
      if (b.id == lastSuccessfulAddressId) return 1;
      
      // 按优先级排序
      final priorityCompare = a.priority.compareTo(b.priority);
      if (priorityCompare != 0) return priorityCompare;
      
      // 按最后成功时间排序
      if (a.lastSuccessTime != null && b.lastSuccessTime != null) {
        return b.lastSuccessTime!.compareTo(a.lastSuccessTime!);
      }
      if (a.lastSuccessTime != null) return -1;
      if (b.lastSuccessTime != null) return 1;
      
      return 0;
    });
    
    return enabled;
  }

  /// 标记某个地址为成功连接
  ServerProfile markAddressSuccess(String addressId) {
    final updatedAddresses = addresses.map((addr) {
      if (addr.id == addressId) {
        return addr.copyWith(
          lastSuccessTime: DateTime.now(),
          failureCount: 0,
        );
      }
      return addr;
    }).toList();
    
    return copyWith(
      addresses: updatedAddresses,
      lastSuccessfulAddressId: addressId,
      lastConnectionTime: DateTime.now(),
    );
  }

  /// 标记某个地址连接失败
  ServerProfile markAddressFailed(String addressId) {
    final updatedAddresses = addresses.map((addr) {
      if (addr.id == addressId) {
        return addr.copyWith(
          lastFailureTime: DateTime.now(),
          failureCount: addr.failureCount + 1,
        );
      }
      return addr;
    }).toList();
    
    return copyWith(addresses: updatedAddresses);
  }

  ServerProfile copyWith({
    String? id,
    String? serverName,
    String? serverType,
    List<ServerAddress>? addresses,
    String? username,
    String? serverId,
    String? accessToken,
    String? userId,
    String? lastSuccessfulAddressId,
    DateTime? lastConnectionTime,
  }) {
    return ServerProfile(
      id: id ?? this.id,
      serverName: serverName ?? this.serverName,
      serverType: serverType ?? this.serverType,
      addresses: addresses ?? this.addresses,
      username: username ?? this.username,
      serverId: serverId ?? this.serverId,
      accessToken: accessToken ?? this.accessToken,
      userId: userId ?? this.userId,
      lastSuccessfulAddressId: lastSuccessfulAddressId ?? this.lastSuccessfulAddressId,
      lastConnectionTime: lastConnectionTime ?? this.lastConnectionTime,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'serverName': serverName,
      'serverType': serverType,
      'addresses': addresses.map((addr) => addr.toJson()).toList(),
      'username': username,
      'serverId': serverId,
      'accessToken': accessToken,
      'userId': userId,
      'lastSuccessfulAddressId': lastSuccessfulAddressId,
      'lastConnectionTime': lastConnectionTime?.toIso8601String(),
    };
  }

  factory ServerProfile.fromJson(Map<String, dynamic> json) {
    return ServerProfile(
      id: json['id'],
      serverName: json['serverName'],
      serverType: json['serverType'],
      addresses: (json['addresses'] as List)
          .map((addr) => ServerAddress.fromJson(addr))
          .toList(),
      username: json['username'],
      serverId: json['serverId'],
      accessToken: json['accessToken'],
      userId: json['userId'],
      lastSuccessfulAddressId: json['lastSuccessfulAddressId'],
      lastConnectionTime: json['lastConnectionTime'] != null
          ? DateTime.parse(json['lastConnectionTime'])
          : null,
    );
  }
}

/// 服务器地址模型
class ServerAddress {
  final String id; // 地址唯一标识
  final String url; // 服务器URL
  final String name; // 地址名称（如：家庭网络、公网访问等）
  final int priority; // 优先级（数字越小优先级越高）
  final bool isEnabled; // 是否启用
  final DateTime? lastSuccessTime; // 最后成功连接时间
  final DateTime? lastFailureTime; // 最后失败时间
  final int failureCount; // 连续失败次数
  final Map<String, dynamic>? metadata; // 额外元数据

  ServerAddress({
    required this.id,
    required this.url,
    required this.name,
    this.priority = 0,
    this.isEnabled = true,
    this.lastSuccessTime,
    this.lastFailureTime,
    this.failureCount = 0,
    this.metadata,
  });

  /// 规范化URL（确保URL格式正确）
  String get normalizedUrl {
    String normalized = url.trim();
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  /// 是否应该重试（基于失败次数和时间）
  bool shouldRetry({int maxFailures = 3, Duration cooldownPeriod = const Duration(minutes: 5)}) {
    if (failureCount < maxFailures) return true;
    
    if (lastFailureTime != null) {
      final timeSinceFailure = DateTime.now().difference(lastFailureTime!);
      return timeSinceFailure > cooldownPeriod;
    }
    
    return true;
  }

  ServerAddress copyWith({
    String? id,
    String? url,
    String? name,
    int? priority,
    bool? isEnabled,
    DateTime? lastSuccessTime,
    DateTime? lastFailureTime,
    int? failureCount,
    Map<String, dynamic>? metadata,
  }) {
    return ServerAddress(
      id: id ?? this.id,
      url: url ?? this.url,
      name: name ?? this.name,
      priority: priority ?? this.priority,
      isEnabled: isEnabled ?? this.isEnabled,
      lastSuccessTime: lastSuccessTime ?? this.lastSuccessTime,
      lastFailureTime: lastFailureTime ?? this.lastFailureTime,
      failureCount: failureCount ?? this.failureCount,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'name': name,
      'priority': priority,
      'isEnabled': isEnabled,
      'lastSuccessTime': lastSuccessTime?.toIso8601String(),
      'lastFailureTime': lastFailureTime?.toIso8601String(),
      'failureCount': failureCount,
      'metadata': metadata,
    };
  }

  factory ServerAddress.fromJson(Map<String, dynamic> json) {
    return ServerAddress(
      id: json['id'],
      url: json['url'],
      name: json['name'],
      priority: json['priority'] ?? 0,
      isEnabled: json['isEnabled'] ?? true,
      lastSuccessTime: json['lastSuccessTime'] != null
          ? DateTime.parse(json['lastSuccessTime'])
          : null,
      lastFailureTime: json['lastFailureTime'] != null
          ? DateTime.parse(json['lastFailureTime'])
          : null,
      failureCount: json['failureCount'] ?? 0,
      metadata: json['metadata'],
    );
  }
}
