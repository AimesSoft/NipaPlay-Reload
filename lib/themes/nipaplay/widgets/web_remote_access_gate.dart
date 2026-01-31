import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/web_remote_access_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/url_name_generator.dart';
import 'package:provider/provider.dart';

class WebRemoteAccessGate extends StatefulWidget {
  final Widget child;

  const WebRemoteAccessGate({super.key, required this.child});

  @override
  State<WebRemoteAccessGate> createState() => _WebRemoteAccessGateState();
}

class _WebRemoteAccessGateState extends State<WebRemoteAccessGate> {
  static const Color _accentColor = Color(0xFFFF2E55);
  final TextEditingController _controller = TextEditingController();
  bool _ready = !kIsWeb;
  bool _checking = kIsWeb;
  bool _connecting = false;
  String? _error;

  Future<void> _autoMountSharedLibraries(
    SharedRemoteLibraryProvider provider,
    String baseUrl,
  ) async {
    try {
      final normalized = WebRemoteAccessService.normalizeBaseUrl(baseUrl);

      bool matchesBaseUrl(String candidate, String existing) {
        final normalizedExisting =
            WebRemoteAccessService.normalizeBaseUrl(existing);
        if (candidate == normalizedExisting) return true;
        final candidateUri = Uri.tryParse(candidate);
        final existingUri = Uri.tryParse(normalizedExisting);
        if (candidateUri == null || existingUri == null) return false;
        if (candidateUri.scheme != existingUri.scheme ||
            candidateUri.host != existingUri.host) {
          return false;
        }
        if (!candidateUri.hasPort &&
            existingUri.hasPort &&
            existingUri.port == 1180 &&
            candidateUri.scheme == 'http') {
          return true;
        }
        return false;
      }

      SharedRemoteHost? matchedHost;
      for (final host in provider.hosts) {
        if (matchesBaseUrl(normalized, host.baseUrl)) {
          matchedHost = host;
          break;
        }
      }

      if (matchedHost != null) {
        if (provider.activeHostId != matchedHost.id) {
          await provider.setActiveHost(matchedHost.id);
        } else if (!provider.hasReachableActiveHost) {
          await provider.refreshLibrary(userInitiated: true);
        }
      } else {
        final displayName = UrlNameGenerator.generateAddressName(normalized);
        await provider.addHost(displayName: displayName, baseUrl: normalized);
      }

      await provider.refreshManagement(userInitiated: true);
    } catch (e) {
      debugPrint('[WebRemoteAccessGate] 自动挂载共享媒体库失败: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _loadInitial();
    }
  }

  Future<void> _loadInitial() async {
    await WebRemoteAccessService.ensureInitialized();
    final candidate = await WebRemoteAccessService.resolveCandidateBaseUrl();

    if (candidate != null && candidate.isNotEmpty) {
      _controller.text = candidate;
      final ok = await WebRemoteAccessService.probe(candidate);
      if (ok) {
        await WebRemoteAccessService.setBaseUrl(candidate);
        await DandanplayService.refreshWebApiBaseUrl();
        final sharedProvider =
            context.read<SharedRemoteLibraryProvider>();
        unawaited(_autoMountSharedLibraries(sharedProvider, candidate));
        if (mounted) {
          setState(() {
            _ready = true;
            _checking = false;
          });
        }
        return;
      } else {
        _error = '无法连接远程访问地址，请检查输入';
      }
    }

    if (mounted) {
      setState(() {
        _ready = false;
        _checking = false;
      });
    }
  }

  Future<void> _connect() async {
    final input = _controller.text.trim();
    if (!WebRemoteAccessService.isValidBaseUrl(input)) {
      setState(() {
        _error = '请输入有效的远程访问地址';
      });
      return;
    }

    final normalized = WebRemoteAccessService.normalizeBaseUrl(input);
    setState(() {
      _connecting = true;
      _error = null;
    });

    final ok = await WebRemoteAccessService.probe(normalized);
    if (!ok) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = '连接失败，请确认远程访问服务已开启';
        });
      }
      return;
    }

    await WebRemoteAccessService.setBaseUrl(normalized);
    await DandanplayService.refreshWebApiBaseUrl();
    final sharedProvider = context.read<SharedRemoteLibraryProvider>();
    unawaited(_autoMountSharedLibraries(sharedProvider, normalized));
    if (mounted) {
      setState(() {
        _connecting = false;
        _ready = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return widget.child;
    }
    if (_ready) {
      return widget.child;
    }

    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = globals.DialogSizes.getDialogWidth(screenSize.width);
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = colorScheme.onSurface.withOpacity(0.7);
    final hintColor = colorScheme.onSurface.withOpacity(0.5);
    final borderColor = colorScheme.onSurface.withOpacity(isDark ? 0.25 : 0.2);
    final surfaceColor =
        isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F2);
    final selectionTheme = TextSelectionThemeData(
      cursorColor: _accentColor,
      selectionColor: _accentColor.withOpacity(0.3),
      selectionHandleColor: _accentColor,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: Container(color: Colors.black54),
        ),
        if (_checking)
          const Center(
            child: CircularProgressIndicator(),
          )
        else
          NipaplayWindowScaffold(
            maxWidth: dialogWidth,
            maxHeightFactor: 0.7,
            onClose: () {},
            backgroundColor: surfaceColor,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: TextSelectionTheme(
                data: selectionTheme,
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: keyboardHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '连接远程访问',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '请输入已开启远程访问的 NipaPlay 地址，连接成功后才能使用 Web UI。',
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _controller,
                          autofocus: true,
                          enabled: !_connecting,
                          cursorColor: _accentColor,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) {
                            if (!_connecting) {
                              _connect();
                            }
                          },
                          decoration: InputDecoration(
                            labelText: '远程访问地址',
                            hintText: 'http://192.168.1.100:1180',
                            labelStyle: TextStyle(color: labelColor),
                            hintStyle: TextStyle(color: hintColor),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: borderColor),
                            ),
                            focusedBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: _accentColor),
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: _connecting ? null : _connect,
                            style: ButtonStyle(
                              foregroundColor:
                                  MaterialStateProperty.resolveWith(
                                (states) => states.contains(MaterialState.disabled)
                                    ? hintColor
                                    : _accentColor,
                              ),
                              overlayColor:
                                  MaterialStateProperty.all(Colors.transparent),
                              splashFactory: NoSplash.splashFactory,
                              padding: MaterialStateProperty.all(
                                const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                            child: _connecting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                        _accentColor,
                                      ),
                                    ),
                                  )
                                : const Text(
                                    '连接',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
