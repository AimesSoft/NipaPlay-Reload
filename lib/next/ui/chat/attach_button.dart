import 'dart:async';

import 'package:file_selector/file_selector.dart' show XFile, openFiles;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker;
import 'package:nipaplay/utils/globals.dart' as globals;

import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/sheet.dart';

/// How files are picked; replaced in tests.
abstract interface class AttachmentPicker {
  /// Pictures from the photo library (a phone's).
  Future<List<String>> pictures();

  /// Files of any kind, from the system's file dialog.
  Future<List<String>> files();
}

final class SystemAttachmentPicker implements AttachmentPicker {
  const SystemAttachmentPicker();

  @override
  Future<List<String>> pictures() async => [
        for (final image in await ImagePicker().pickMultiImage()) image.path
      ];

  @override
  Future<List<String>> files() async => [
        for (final XFile file in await openFiles()) file.path
      ];
}

/// Whether picking offers the photo library besides files: a phone keeps
/// its pictures there, a computer in folders.
bool get attachmentsOfferPictures =>
    !kIsWeb &&
    !globals.isTvOS &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android ||
        globals.isHarmonyOS);

/// Files and pictures to go with what you say next, picked rather than
/// dropped: a phone has nothing to drop, and the file dialog is where most
/// people look for a file. On a computer it opens the dialog; on a phone it
/// asks first whether from the photos or from files.
class AttachButton extends StatefulWidget {
  const AttachButton({
    super.key,
    required this.onFiles,
    this.enabled = true,
    this.picker = const SystemAttachmentPicker(),
    this.offerPictures,
    this.refused,
  });

  final ValueChanged<List<String>> onFiles;
  final bool enabled;

  /// Why files cannot go now ([NipaChat.filesRefused]): the button stays,
  /// dimmed, and says so when pressed instead of picking.
  final String? refused;
  final AttachmentPicker picker;

  /// Null: [attachmentsOfferPictures].
  final bool? offerPictures;

  @override
  State<AttachButton> createState() => _AttachButtonState();
}

class _AttachButtonState extends State<AttachButton> {
  bool _picking = false;

  Future<void> _pick() async {
    if (_picking) return;
    if (widget.refused case final why?) {
      await showNextSheet<void>(
          (context, close) => _Refused(why: why, onClose: close),
          width: 380);
      return;
    }
    final pictures = widget.offerPictures ?? attachmentsOfferPictures;
    final from = pictures
        ? await showNextSheet<String>(
            (context, close) => _FromSheet(onChoose: close), width: 360)
        : 'files';
    if (from == null || !mounted) return;
    setState(() => _picking = true);
    try {
      final paths = from == 'pictures'
          ? await widget.picker.pictures()
          : await widget.picker.files();
      if (paths.isNotEmpty && mounted) widget.onFiles(paths);
    } catch (error) {
      // A picker the platform does not have, or permission refused: nothing
      // is attached, and the conversation goes on.
      debugPrint('[NextUi] attachments not picked: $error');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) => Pressable(
        key: const Key('chat.attach'),
        semanticLabel: '添加附件',
        onTap: widget.enabled && !_picking ? _pick : null,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hovered ? const Color(0x14FFFFFF) : null,
          ),
          child: NextIcon(NextGlyph.plus,
              size: 17,
              color: !widget.enabled || _picking || widget.refused != null
                  ? NextColors.p4
                  : hovered
                      ? NextColors.paper
                      : NextColors.p2),
        ),
      );
}

class _Refused extends StatelessWidget {
  const _Refused({required this.why, required this.onClose});
  final String why;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => SheetSurface(
        padding: const EdgeInsets.fromLTRB(22, 18, 14, 18),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(why,
                  key: const Key('chat.attach.refused'),
                  style: NextText.sans(14, height: 1.5)),
            ),
          ),
          NextIconButton(glyph: NextGlyph.close, label: '关闭', onTap: onClose),
        ]),
      );
}

class _FromSheet extends StatelessWidget {
  const _FromSheet({required this.onChoose});
  final void Function([String?]) onChoose;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _Choice(
              key: const Key('chat.attach.pictures'),
              glyph: NextGlyph.file,
              label: '照片',
              onTap: () => onChoose('pictures')),
          _Choice(
              key: const Key('chat.attach.files'),
              glyph: NextGlyph.file,
              label: '文件',
              onTap: () => onChoose('files')),
        ]),
      );
}

class _Choice extends StatelessWidget {
  const _Choice(
      {super.key,
      required this.glyph,
      required this.label,
      required this.onTap});
  final NextGlyph glyph;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        pressScale: 0.99,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: hovered ? const Color(0x12FFFFFF) : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            NextIcon(glyph, size: 16, color: NextColors.p2),
            const SizedBox(width: 12),
            Text(label, style: NextText.sans(14.5)),
          ]),
        ),
      );
}
