import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/io_client.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';

import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/services/nipaplay_lan_discovery.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';

class SharedRemoteLanScanDialog {
  static Future<bool?> show(
    BuildContext context, {
    required SharedRemoteLibraryProvider provider,
  }) {
    final textColor = Theme.of(context).colorScheme.onSurface.withOpacity(0.7);
    return BlurDialog.show<bool>(
      context: context,
      title: '扫描局域网',
      contentWidget: _SharedRemoteLanScanDialogContent(provider: provider),
      actions: [
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('关闭', style: TextStyle(color: textColor)),
        ),
      ],
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

class _SharedRemoteLanScanDialogContent extends StatefulWidget {
  const _SharedRemoteLanScanDialogContent({
    required this.provider,
  });

  final SharedRemoteLibraryProvider provider;

  @override
  State<_SharedRemoteLanScanDialogContent> createState() =>
      _SharedRemoteLanScanDialogContentState();
}

class _SharedRemoteLanScanDialogContentState
    extends State<_SharedRemoteLanScanDialogContent> {
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

      // 1) 自动发现：无需用户输入端口，速度快且能拿到真实端口号
      await _discoverByUdp(prefixes: targets.prefixes, token: token);
      if (!mounted || token.canceled) return;

      // 2) 兼容旧版本：若对方未实现 UDP 发现，则回退到默认端口 1180 的网段探测
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

      // 连发几次提高成功率（不同平台/路由器对广播包的处理不一致）
      sendOnce();
      await Future.delayed(const Duration(milliseconds: 220));
      if (token.canceled) return;
      sendOnce();
      await Future.delayed(const Duration(milliseconds: 220));
      if (token.canceled) return;
      sendOnce();

      // 等待响应回包
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
            ip: ip, port: port, baseUrl: baseUrl, hostname: hostname);
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
      BlurSnackBar.show(context, '已连接到共享客户端');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      BlurSnackBar.show(context, '添加失败：$e');
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
      final isLocal = isLocalHost || _isPrivateIpv4(host) || host.endsWith('.local');
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
    const accentColor = Color(0xFFFF2E55);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final subTextColor = textColor.withOpacity(0.7);
    final mutedTextColor = textColor.withOpacity(0.5);
    final borderColor = textColor.withOpacity(isDark ? 0.12 : 0.18);
    final itemColor = isDark ? const Color(0xFF2B2B2B) : const Color(0xFFF7F7F7);
    final backgroundColor =
        isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F2);
    final ButtonStyle actionButtonStyle = ButtonStyle(
      foregroundColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.disabled)) {
          return mutedTextColor;
        }
        if (states.contains(MaterialState.hovered)) {
          return accentColor;
        }
        return accentColor;
      }),
      overlayColor: MaterialStateProperty.all(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      padding: MaterialStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
    );
    final height = (MediaQuery.of(context).size.height * 0.55)
        .clamp(320.0, 520.0)
        .toDouble();
    final prefixLabel = _prefixes.isEmpty ? '自动获取网段' : _prefixes.join('、');
    final statusText = _errorMessage ??
        (_isScanning
            ? (_scanPhase == _LanScanPhase.discovering
                ? '正在自动发现：$prefixLabel  已发现 ${_foundHosts.length} 台'
                : '正在扫描：$prefixLabel（默认端口 $defaultPort）  $_scanned/$_total  已发现 ${_foundHosts.length} 台')
            : '扫描完成：$prefixLabel  共找到 ${_foundHosts.length} 台');

    return Container(
      color: backgroundColor,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '将自动发现局域网中已开启“远程访问”的 NipaPlay（无需手动输入端口）。若未发现设备，会回退扫描默认端口 1180（旧版本兼容）。',
              style: TextStyle(
                color: subTextColor,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Spacer(),
                SizedBox(
                  width: 120,
                  child: TextButton.icon(
                    icon: const Icon(Ionicons.refresh_outline, size: 18),
                    label: Text(_isScanning ? '停止' : '重新扫描'),
                    onPressed: _isScanning
                        ? () => _cancelScan(updateState: true)
                        : _startScan,
                    style: actionButtonStyle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  _isScanning
                      ? Ionicons.radio_outline
                      : Ionicons.checkmark_circle_outline,
                  color: _isScanning ? subTextColor : mutedTextColor,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: _errorMessage != null
                          ? Colors.orangeAccent
                          : subTextColor,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_isScanning)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _foundHosts.isEmpty
                  ? Center(
                      child: Text(
                        _isScanning ? '暂未发现设备…' : '未发现任何设备',
                        style: TextStyle(color: mutedTextColor),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _foundHosts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final host = _foundHosts[index];
                        final title =
                            (host.hostname?.trim().isNotEmpty ?? false)
                                ? host.hostname!.trim()
                                : host.ip;
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor),
                            color: itemColor,
                          ),
                          child: Row(
                            children: [
                              Icon(Ionicons.desktop_outline,
                                  color: subTextColor, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: TextStyle(
                                        color: textColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      host.baseUrl,
                                      style: TextStyle(
                                        color: subTextColor,
                                        fontSize: 12,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              TextButton(
                                onPressed: _isAdding
                                    ? null
                                    : () => _addDiscoveredHost(host),
                                style: actionButtonStyle,
                                child: _isAdding
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            accentColor,
                                          ),
                                        ),
                                      )
                                    : const Text('添加'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
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
