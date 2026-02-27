import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:flutter/foundation.dart';
import 'package:http/io_client.dart';

import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/services/nipaplay_lan_discovery.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';

class CupertinoSharedRemoteLanScanDialog {
  static Future<bool?> show(
    BuildContext context, {
    required SharedRemoteLibraryProvider provider,
  }) {
    return CupertinoBottomSheet.show<bool>(
      context: context,
      title: '扫描局域网',
      heightRatio: 0.6,
      child: _CupertinoSharedRemoteLanScanDialogContent(provider: provider),
    );
  }
}

class _DiscoveredHost {
  const _DiscoveredHost({
    required this.ip,
    required this.port,
    required this.baseUrl,
    this.hostname,
  });

  final String ip;
  final int port;
  final String baseUrl;
  final String? hostname;
}

class _ScanToken {
  bool canceled = false;
}

enum _LanScanPhase {
  discovering,
  compatibilityScan,
}

class _CupertinoSharedRemoteLanScanDialogContent extends StatefulWidget {
  const _CupertinoSharedRemoteLanScanDialogContent({
    required this.provider,
  });

  final SharedRemoteLibraryProvider provider;

  @override
  State<_CupertinoSharedRemoteLanScanDialogContent> createState() =>
      _CupertinoSharedRemoteLanScanDialogContentState();
}

class _CupertinoSharedRemoteLanScanDialogContentState
    extends State<_CupertinoSharedRemoteLanScanDialogContent> {
  bool _isScanning = false;
  bool _isAdding = false;
  String? _errorMessage;
  _LanScanPhase _scanPhase = _LanScanPhase.discovering;
  int _scanned = 0;
  int _total = 0;
  Set<String> _prefixes = {};
  final List<_DiscoveredHost> _foundHosts = [];

  _ScanToken? _scanToken;
  IOClient? _client;
  RawDatagramSocket? _udpSocket;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startScan();
    });
  }

  @override
  void dispose() {
    _cancelScan();
    super.dispose();
  }

  void _cancelScan({bool updateState = false}) {
    _scanToken?.canceled = true;
    _client?.close();
    _client = null;
    _udpSocket?.close();
    _udpSocket = null;
    if (updateState && mounted) {
      setState(() {
        _isScanning = false;
      });
    }
  }

  Future<void> _startScan() async {
    if (_isAdding) return;
    if (kIsWeb) {
      setState(() {
        _errorMessage = 'Web 端暂不支持局域网扫描';
      });
      return;
    }

    _cancelScan();
    final token = _ScanToken();

    setState(() {
      _scanToken = token;
      _isScanning = true;
      _scanPhase = _LanScanPhase.discovering;
      _errorMessage = null;
      _scanned = 0;
      _total = 0;
      _prefixes = {};
      _foundHosts.clear();
    });

    try {
      final targets = await _resolveScanTargets();
      if (!mounted || token.canceled) return;

      _prefixes = targets.prefixes;
      if (targets.candidates.isEmpty) {
        setState(() {
          _errorMessage = '未找到可扫描的局域网网段';
          _isScanning = false;
        });
        return;
      }

      setState(() {});

      await _discoverByUdp(prefixes: targets.prefixes, token: token);
      if (!mounted || token.canceled) return;

      if (_foundHosts.isEmpty) {
        final httpClient = HttpClient()
          ..connectionTimeout = const Duration(milliseconds: 350);
        final client = IOClient(httpClient);

        _client = client;
        _scanPhase = _LanScanPhase.compatibilityScan;
        _scanned = 0;
        _total = targets.candidates.length;
        if (mounted) setState(() {});

        final queue = Queue<String>.from(targets.candidates);
        const maxConcurrent = 32;

        Future<void> worker() async {
          while (!token.canceled && queue.isNotEmpty) {
            final ip = queue.removeFirst();
            final discovered = await _probeHost(
              client: client,
              ip: ip,
              port: 1180,
              token: token,
            );
            if (!mounted || token.canceled) return;

            if (discovered != null &&
                !_foundHosts.any((h) => h.baseUrl == discovered.baseUrl)) {
              _foundHosts.add(discovered);
            }

            _scanned += 1;
            if (mounted) setState(() {});
          }
        }

        await Future.wait(List.generate(maxConcurrent, (_) => worker()));
      }
    } catch (e) {
      if (!mounted || token.canceled) return;
      setState(() {
        _errorMessage = '扫描失败：$e';
      });
    } finally {
      final canUpdateState = mounted;
      if (canUpdateState) {
        setState(() {
          _isScanning = false;
        });
      }
      _cancelScan();
    }
  }

  Future<void> _discoverByUdp({
    required Set<String> prefixes,
    required _ScanToken token,
  }) async {
    if (token.canceled) return;

    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      if (token.canceled) return;

      _udpSocket = socket;

      socket.listen((event) {
        if (!mounted || token.canceled) return;
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = socket?.receive()) != null) {
          final parsed = NipaPlayLanDiscoveryProtocol.tryParseResponse(datagram!);
          if (parsed == null) continue;
          final host = _DiscoveredHost(
            ip: parsed.ip,
            port: parsed.port,
            baseUrl: parsed.baseUrl,
            hostname: parsed.hostname,
          );

          if (_foundHosts.any((h) => h.baseUrl == host.baseUrl)) {
            continue;
          }
          setState(() {
            _foundHosts.add(host);
          });
        }
      });

      final requestBytes = NipaPlayLanDiscoveryProtocol.buildRequestBytes();
      final targets = <InternetAddress>{
        InternetAddress('255.255.255.255'),
        ...prefixes.map((prefix) => InternetAddress('${prefix}255')),
      };

      void sendOnce() {
        for (final address in targets) {
          try {
            socket?.send(requestBytes, address, nipaplayLanDiscoveryPort);
          } catch (_) {
            // ignore
          }
        }
      }

      sendOnce();
      await Future.delayed(const Duration(milliseconds: 220));
      if (token.canceled) return;
      sendOnce();
      await Future.delayed(const Duration(milliseconds: 220));
      if (token.canceled) return;
      sendOnce();

      await Future.delayed(const Duration(milliseconds: 800));

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('[LAN发现] 创建/发送 UDP 发现包失败: $e');
    } finally {
      try {
        socket?.close();
      } catch (_) {
        // ignore
      }
      if (identical(_udpSocket, socket)) {
        _udpSocket = null;
      }
    }
  }

  Future<_DiscoveredHost?> _probeHost({
    required IOClient client,
    required String ip,
    required int port,
    required _ScanToken token,
  }) async {
    if (token.canceled) return null;
    final baseUrl = 'http://$ip:$port';

    Future<Map<String, dynamic>?> getJson(Uri uri, Duration timeout) async {
      try {
        final response = await client.get(uri).timeout(timeout);
        if (response.statusCode != 200) return null;
        final decoded = json.decode(utf8.decode(response.bodyBytes));
        return decoded is Map<String, dynamic> ? decoded : null;
      } catch (_) {
        return null;
      }
    }

    final infoUri = Uri.parse('$baseUrl/api/info');
    final infoJson = await getJson(infoUri, const Duration(milliseconds: 500));
    if (token.canceled) return null;

    if (infoJson != null) {
      final isNipaPlay =
          infoJson['app'] == 'NipaPlay' && (infoJson['success'] == true);
      if (isNipaPlay) {
        final hostname = infoJson['hostname'] is String
            ? infoJson['hostname'] as String
            : null;
        return _DiscoveredHost(
          ip: ip,
          port: port,
          baseUrl: baseUrl,
          hostname: hostname,
        );
      }
    }

    return null;
  }

  Future<void> _addDiscoveredHost(_DiscoveredHost host) async {
    if (_isAdding) return;
    _cancelScan(updateState: true);
    setState(() {
      _isAdding = true;
    });

    try {
      final normalized = _normalizeBaseUrl(host.baseUrl);
      SharedRemoteHost? existing;
      for (final current in widget.provider.hosts) {
        if (_normalizeBaseUrl(current.baseUrl) == normalized) {
          existing = current;
          break;
        }
      }

      if (existing != null) {
        await widget.provider.setActiveHost(existing.id);
      } else {
        final displayName = (host.hostname?.trim().isNotEmpty ?? false)
            ? host.hostname!.trim()
            : normalized;
        await widget.provider
            .addHost(displayName: displayName, baseUrl: normalized);
      }

      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '已连接到共享客户端',
        type: AdaptiveSnackBarType.success,
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '添加失败：$e',
        type: AdaptiveSnackBarType.error,
      );
      setState(() {
        _isAdding = false;
      });
    }
  }

  String _normalizeBaseUrl(String url) {
    var normalized = url.trim();
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    try {
      final uri = Uri.parse(normalized);
      final host = uri.host;
      final isLocalHost = host == 'localhost' || host == '127.0.0.1';
      final isLocal =
          isLocalHost || _isPrivateIpv4(host) || host.endsWith('.local');
      if (!uri.hasPort && uri.scheme == 'http' && isLocal) {
        normalized = uri.replace(port: 1180).toString();
      }
    } catch (_) {
      // ignore
    }
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  @override
  Widget build(BuildContext context) {
    const defaultPort = 1180;
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondaryLabelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final warnColor =
        CupertinoDynamicColor.resolve(CupertinoColors.systemOrange, context);
    final statusColor = _errorMessage != null ? warnColor : secondaryLabelColor;
    final prefixLabel = _prefixes.isEmpty ? '自动获取网段' : _prefixes.join('、');
    final statusText = _errorMessage ??
        (_isScanning
            ? (_scanPhase == _LanScanPhase.discovering
                ? '正在自动发现：$prefixLabel  已发现 ${_foundHosts.length} 台'
                : '正在扫描：$prefixLabel（默认端口 $defaultPort）  $_scanned/$_total  已发现 ${_foundHosts.length} 台')
            : '扫描完成：$prefixLabel  共找到 ${_foundHosts.length} 台');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '将自动发现局域网中已开启“远程访问”的 NipaPlay（无需手动输入端口）。若未发现设备，会回退扫描默认端口 1180（旧版本兼容）。',
            style: TextStyle(color: secondaryLabelColor, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Spacer(),
              CupertinoButton(
                onPressed: _isScanning
                    ? () => _cancelScan(updateState: true)
                    : _startScan,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.activeBlue, context),
                borderRadius: BorderRadius.circular(12),
                child: Text(
                  _isScanning ? '停止' : '重新扫描',
                  style: const TextStyle(
                    color: CupertinoColors.white,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                _isScanning
                    ? CupertinoIcons.wifi
                    : CupertinoIcons.check_mark_circled,
                color: statusColor,
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_isScanning) const CupertinoActivityIndicator(radius: 7),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildHostList(context, labelColor, secondaryLabelColor)),
        ],
      ),
    );
  }

  Widget _buildHostList(
    BuildContext context,
    Color labelColor,
    Color secondaryLabelColor,
  ) {
    if (_foundHosts.isEmpty) {
      return Center(
        child: Text(
          _isScanning ? '暂未发现设备…' : '未发现任何设备',
          style: TextStyle(color: secondaryLabelColor),
        ),
      );
    }

    final tileBackground = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemGroupedBackground,
      context,
    );
    final borderColor = CupertinoDynamicColor.resolve(
      CupertinoColors.separator,
      context,
    ).withValues(alpha: 0.4);
    final actionColor =
        CupertinoDynamicColor.resolve(CupertinoColors.activeBlue, context);

    return ListView.separated(
      itemCount: _foundHosts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final host = _foundHosts[index];
        final title = (host.hostname?.trim().isNotEmpty ?? false)
            ? host.hostname!.trim()
            : host.ip;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tileBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.desktopcomputer,
                color: secondaryLabelColor,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: labelColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      host.baseUrl,
                      style: TextStyle(
                        color: secondaryLabelColor,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              CupertinoButton(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: const Size(0, 0),
                onPressed: _isAdding ? null : () => _addDiscoveredHost(host),
                child: _isAdding
                    ? const CupertinoActivityIndicator(radius: 8)
                    : Text(
                        '添加',
                        style: TextStyle(
                          color: actionColor,
                          fontSize: 13,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ScanTargets {
  const _ScanTargets({
    required this.prefixes,
    required this.candidates,
  });

  final Set<String> prefixes;
  final List<String> candidates;
}

Future<_ScanTargets> _resolveScanTargets() async {
  final prefixes = <String>{};
  final selfIps = <String>{};

  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    includeLinkLocal: false,
    type: InternetAddressType.IPv4,
  );

  for (final interface in interfaces) {
    for (final addr in interface.addresses) {
      final ip = addr.address;
      if (!_isPrivateIpv4(ip)) continue;
      final parts = ip.split('.');
      if (parts.length != 4) continue;
      prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}.');
      selfIps.add(ip);
    }
  }

  final candidates = <String>[];
  final seen = <String>{};
  for (final prefix in prefixes) {
    for (var i = 1; i <= 254; i++) {
      final ip = '$prefix$i';
      if (selfIps.contains(ip)) continue;
      if (!seen.add(ip)) continue;
      candidates.add(ip);
    }
  }

  return _ScanTargets(prefixes: prefixes, candidates: candidates);
}

bool _isPrivateIpv4(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return false;
  final a = int.tryParse(parts[0]);
  final b = int.tryParse(parts[1]);
  if (a == null || b == null) return false;

  if (a == 10) return true;
  if (a == 192 && b == 168) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  return false;
}
