import 'package:flutter/widgets.dart';

import '../data/downloads.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';

/// “1.2 GB”, “340 MB”.
String bytesText(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  if (unit == 0) return '$bytes B';
  final whole = value >= 100 || unit == 1 || value == value.roundToDouble();
  return '${whole ? value.round() : value.toStringAsFixed(1)} ${units[unit]}';
}

/// “3.9 MB/s”.
String rateText(int bytesPerSecond) => '${bytesText(bytesPerSecond)}/s';

/// “52 分钟”, “1 小时 20 分”.
String leftText(Duration d) {
  if (d.inMinutes < 1) return '不到 1 分钟';
  if (d.inHours < 1) return '${d.inMinutes} 分钟';
  final m = d.inMinutes % 60;
  return m == 0 ? '${d.inHours} 小时' : '${d.inHours} 小时 $m 分';
}

/// A download's state in a word.
String downloadWord(UiDownload d) => switch (d.state) {
      UiDownloadState.downloading => d.stalledFor != null ? '没有进展' : '下载中',
      UiDownloadState.queued => '排队',
      UiDownloadState.paused => '已暂停',
      UiDownloadState.finished => '完成',
      UiDownloadState.failed => _failure(d.error),
    };

String _failure(String? error) {
  final e = error?.toLowerCase() ?? '';
  if (e.contains('space')) return '磁盘满了';
  if (e.contains('permission') || e.contains('denied')) return '没有写入权限';
  if (e.contains('metadata') || e.contains('timeout')) return '找不到来源';
  return '没能下载';
}

/// A small square checkbox: crimson when on, a dash when some are.
class NextCheck extends StatelessWidget {
  const NextCheck(
      {super.key, required this.on, this.some = false, this.onTap, this.label});
  final bool on;
  final bool some;
  final VoidCallback? onTap;
  final String? label;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        pressScale: 0.9,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on || some
                ? NextColors.accent
                : hovered
                    ? const Color(0x14FFFFFF)
                    : const Color(0x00FFFFFF),
            borderRadius: BorderRadius.circular(5),
            border: on || some
                ? null
                : Border.all(
                    color: hovered ? NextColors.p3 : NextColors.p4, width: 1.4),
          ),
          child: on
              ? CustomPaint(size: const Size(10, 8), painter: _Tick())
              : some
                  ? Container(width: 8, height: 2, color: NextColors.paper)
                  : null,
        ),
      );
}

class _Tick extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
        Path()
          ..moveTo(0, size.height * 0.5)
          ..lineTo(size.width * 0.38, size.height)
          ..lineTo(size.width, 0),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = NextColors.paper);
  }

  @override
  bool shouldRepaint(_Tick old) => false;
}

/// One file of a download or of a magnet's preview: whether it is
/// wanted, its name and folder, its size, and how far it is.
class DownloadFileRow extends StatelessWidget {
  const DownloadFileRow({
    super.key,
    required this.file,
    required this.included,
    this.onToggle,
    this.onPlay,
    this.progress = true,
  });
  final UiDownloadFile file;
  final bool included;
  final VoidCallback? onToggle;
  final VoidCallback? onPlay;

  /// Show how far it is (not in a preview).
  final bool progress;

  @override
  Widget build(BuildContext context) {
    final p = file.progress;
    return Pressable(
      onTap: onToggle,
      semanticLabel: file.name,
      pressScale: 1,
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: hovered ? const Color(0x0AFFFFFF) : const Color(0x00FFFFFF),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          NextCheck(on: included, onTap: onToggle, label: '选择 ${file.name}'),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(
                  TextSpan(children: [
                    if (file.folder != null)
                      TextSpan(
                          text: '${file.folder} / ',
                          style: NextText.sans(13, color: NextColors.p4)),
                    TextSpan(text: file.name),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NextText.sans(13,
                      color: included ? NextColors.paper : NextColors.p3),
                ),
                if (progress && included && p != null && p < 1) ...[
                  const SizedBox(height: 6),
                  _FileBar(progress: p),
                ],
              ],
            ),
          ),
          const SizedBox(width: 14),
          if (progress && included && file.complete)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: _Done(),
            )
          else if (progress && included && p != null)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text('${(p * 100).floor()}%',
                  style: NextText.num(12, color: NextColors.p3)),
            ),
          SizedBox(
            width: 64,
            child: Text(bytesText(file.size),
                textAlign: TextAlign.right,
                style: NextText.num(12,
                    color: included ? NextColors.p2 : NextColors.p4)),
          ),
          if (progress)
            SizedBox(
              width: 34,
              child: onPlay == null
                  ? null
                  : Align(
                      alignment: Alignment.centerRight,
                      child: Pressable(
                        onTap: onPlay,
                        semanticLabel: '播放 ${file.name}',
                        builder: (context, hovered) => AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hovered
                                ? NextColors.accent
                                : const Color(0x14FFFFFF),
                          ),
                          child: CustomPaint(
                              size: const Size(8, 9), painter: _PlayGlyph()),
                        ),
                      ),
                    ),
            ),
        ]),
      ),
    );
  }
}

class _FileBar extends StatelessWidget {
  const _FileBar({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(1),
        child: SizedBox(
          height: 2,
          child: Stack(fit: StackFit.expand, children: [
            const ColoredBox(color: Color(0x1AFFFFFF)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress,
              child: const ColoredBox(color: NextColors.accent2),
            ),
          ]),
        ),
      );
}

class _Done extends StatelessWidget {
  const _Done();

  @override
  Widget build(BuildContext context) => Container(
        width: 16,
        height: 16,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
            shape: BoxShape.circle, color: Color(0x2E5BE3B0)),
        child: CustomPaint(
            size: const Size(8, 6),
            painter: _TickColored(NextColors.mint)),
      );
}

class _TickColored extends CustomPainter {
  _TickColored(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
        Path()
          ..moveTo(0, size.height * 0.5)
          ..lineTo(size.width * 0.38, size.height)
          ..lineTo(size.width, 0),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..color = color);
  }

  @override
  bool shouldRepaint(_TickColored old) => old.color != color;
}

class _PlayGlyph extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
        Path()
          ..moveTo(size.width * 0.1, 0)
          ..lineTo(size.width, size.height / 2)
          ..lineTo(size.width * 0.1, size.height)
          ..close(),
        Paint()..color = NextColors.paper);
  }

  @override
  bool shouldRepaint(_PlayGlyph old) => false;
}

/// A torrent's mark where there is no picture: a quiet tile with the
/// download arrow.
class TorrentTile extends StatelessWidget {
  const TorrentTile({super.key, this.width = 64, this.height = 36});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF241A22), Color(0xFF15151C)],
          ),
          border: Border.all(color: NextColors.line),
        ),
        child: CustomPaint(size: const Size(12, 14), painter: _Arrow()),
      );
}

class _Arrow extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = NextColors.accent2;
    final w = size.width, h = size.height;
    canvas
      ..drawLine(Offset(w / 2, 0), Offset(w / 2, h * 0.7), p)
      ..drawPath(
          Path()
            ..moveTo(w * 0.15, h * 0.42)
            ..lineTo(w / 2, h * 0.72)
            ..lineTo(w * 0.85, h * 0.42),
          p)
      ..drawLine(Offset(0, h), Offset(w, h), p);
  }

  @override
  bool shouldRepaint(_Arrow old) => false;
}
