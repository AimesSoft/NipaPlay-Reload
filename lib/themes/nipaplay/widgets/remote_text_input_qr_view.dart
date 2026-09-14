import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class RemoteTextInputQrView extends StatelessWidget {
  const RemoteTextInputQrView({
    super.key,
    required this.inputUri,
    required this.displayKey,
    required this.fieldCount,
  });

  final Uri inputUri;
  final String displayKey;
  final int fieldCount;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final instructions = SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '使用手机扫描二维码输入',
            style: TextStyle(
              color: textColor,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            fieldCount > 1
                ? '一次填写 $fieldCount 项；NipaPlay 内扫码打开原生表单，系统相机扫码打开浏览器。'
                : 'NipaPlay 内扫码会打开原生输入菜单，系统相机扫码会打开浏览器。',
            style: TextStyle(
              color: textColor.withValues(alpha: 0.66),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'KEY $displayKey',
            style: TextStyle(
              color: textColor,
              fontSize: 20,
              letterSpacing: 2,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            inputUri.toString(),
            style: TextStyle(
              color: textColor.withValues(alpha: 0.54),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth >= 420;
          // Size against the dialog's remaining body, after its header and
          // safe-area margins. Only the instructions scroll, never the QR.
          final qrSize = math.max(
            0.0,
            math.min(
              320.0,
              math.min(
                horizontal ? constraints.maxWidth * 0.48 : constraints.maxWidth,
                horizontal
                    ? constraints.maxHeight
                    : constraints.maxHeight * 0.6,
              ),
            ),
          );
          final qr = SizedBox.square(
            dimension: qrSize,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: QrImageView(
                data: inputUri.toString(),
                version: QrVersions.auto,
                size: qrSize,
                padding: const EdgeInsets.all(12),
                backgroundColor: Colors.white,
              ),
            ),
          );

          if (horizontal) {
            return Row(
              children: [
                qr,
                const SizedBox(width: 24),
                Expanded(child: instructions),
              ],
            );
          }
          return Column(
            children: [
              qr,
              const SizedBox(height: 16),
              Expanded(child: instructions),
            ],
          );
        },
      ),
    );
  }
}
