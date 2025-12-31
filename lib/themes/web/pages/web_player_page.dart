import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:nipaplay/themes/web/models/web_playback_item.dart';

class WebPlayerPage extends StatefulWidget {
  const WebPlayerPage({
    super.key,
    required this.item,
  });

  final WebPlaybackItem? item;

  @override
  State<WebPlayerPage> createState() => _WebPlayerPageState();
}

class _WebPlayerPageState extends State<WebPlayerPage> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;
  Object? _initError;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadItem(widget.item);
  }

  @override
  void didUpdateWidget(covariant WebPlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item?.uri != widget.item?.uri) {
      _loadItem(widget.item);
    }
  }

  Future<void> _loadItem(WebPlaybackItem? item) async {
    final int generation = ++_loadGeneration;
    _initError = null;

    final oldController = _controller;
    _controller = null;
    _initializeFuture = null;
    setState(() {});

    if (oldController != null) {
      try {
        await oldController.dispose();
      } catch (_) {}
    }

    if (!mounted || generation != _loadGeneration) return;
    if (item == null) return;

    final controller = VideoPlayerController.networkUrl(item.uri);
    _controller = controller;

    final initFuture = controller.initialize();
    _initializeFuture = initFuture;
    setState(() {});

    try {
      await initFuture;
      if (!mounted || generation != _loadGeneration) return;
      try {
        await controller.play();
      } catch (_) {
        // 浏览器可能会阻止自动播放，用户可手动点击播放按钮。
      }
      if (mounted && generation == _loadGeneration) {
        setState(() {});
      }
    } catch (e) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _initError = e;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _formatDuration(Duration value) {
    final int totalSeconds = value.inSeconds;
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final controller = _controller;
    final initFuture = _initializeFuture;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '播放',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (item == null)
            const Expanded(
              child: Center(
                child: Text('暂无播放内容，请从媒体库/观看记录中选择剧集进行播放。'),
              ),
            )
          else if (_initError != null)
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '无法加载视频',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _initError.toString(),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '提示：浏览器可能不支持该格式（例如 MKV），或远程端未允许跨域/Range 请求。',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if ((item.subtitle ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              item.subtitle!.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Expanded(
                            child: (controller == null || initFuture == null)
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : FutureBuilder<void>(
                                    future: initFuture,
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState !=
                                          ConnectionState.done) {
                                        return const Center(
                                          child: CircularProgressIndicator(),
                                        );
                                      }
                                      if (!controller.value.isInitialized) {
                                        return const Center(
                                          child: Text('初始化失败'),
                                        );
                                      }

                                      final aspectRatio =
                                          controller.value.aspectRatio == 0
                                              ? 16 / 9
                                              : controller.value.aspectRatio;
                                      return Column(
                                        children: [
                                          Expanded(
                                            child: AspectRatio(
                                              aspectRatio: aspectRatio,
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                child: VideoPlayer(controller),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          VideoProgressIndicator(
                                            controller,
                                            allowScrubbing: true,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 4,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              IconButton(
                                                tooltip: controller.value
                                                        .isPlaying
                                                    ? '暂停'
                                                    : '播放',
                                                onPressed: () async {
                                                  if (controller
                                                      .value.isPlaying) {
                                                    await controller.pause();
                                                  } else {
                                                    try {
                                                      await controller.play();
                                                    } catch (_) {}
                                                  }
                                                  if (context.mounted) {
                                                    setState(() {});
                                                  }
                                                },
                                                icon: Icon(
                                                  controller.value.isPlaying
                                                      ? Icons.pause
                                                      : Icons.play_arrow,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                '${_formatDuration(controller.value.position)} / ${_formatDuration(controller.value.duration)}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      );
                                    },
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
      ),
    );
  }
}

