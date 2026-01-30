import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/web_remote_access_service.dart';

class WebRemoteAccessGate extends StatefulWidget {
  final Widget child;

  const WebRemoteAccessGate({super.key, required this.child});

  @override
  State<WebRemoteAccessGate> createState() => _WebRemoteAccessGateState();
}

class _WebRemoteAccessGateState extends State<WebRemoteAccessGate> {
  final TextEditingController _controller = TextEditingController();
  bool _ready = !kIsWeb;
  bool _checking = kIsWeb;
  bool _connecting = false;
  String? _error;

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

    return Stack(
      children: [
        if (_checking)
          const Center(
            child: CircularProgressIndicator(),
          )
        else
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Material(
                  color: Theme.of(context).dialogBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '连接远程访问',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '请输入已开启远程访问的 NipaPlay 地址，连接成功后才能使用 Web UI。',
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _controller,
                          autofocus: true,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) {
                            if (!_connecting) {
                              _connect();
                            }
                          },
                          decoration: const InputDecoration(
                            labelText: '远程访问地址',
                            hintText: 'http://192.168.1.100:1180',
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
                        ElevatedButton(
                          onPressed: _connecting ? null : _connect,
                          child: Text(_connecting ? '连接中...' : '连接'),
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
