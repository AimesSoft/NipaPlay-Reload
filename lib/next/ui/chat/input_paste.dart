import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../../../services/clipboard_image_service.dart';
import '../../../utils/storage_service.dart';

/// One paste path for keyboard shortcuts and the editor's context menu.
/// Clipboard images become durable files, just like dropped attachments.
class ChatInputPaste extends StatefulWidget {
  const ChatInputPaste({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onImages,
    required this.builder,
    this.readImages = readClipboardImages,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<List<String>> onImages;
  final Widget Function(EditableTextContextMenuBuilder contextMenuBuilder)
      builder;
  final Future<List<String>> Function() readImages;

  static Future<List<String>> readClipboardImages() async {
    final root = await StorageService.getAppStorageDirectory();
    return ClipboardImageService.readImageFiles(
        path.join(root.path, 'next', 'chat-attachments'));
  }

  @override
  State<ChatInputPaste> createState() => _ChatInputPasteState();
}

class _ChatInputPasteState extends State<ChatInputPaste> {
  bool _pasting = false;

  Future<void> _paste() async {
    if (_pasting || !widget.enabled) return;
    _pasting = true;
    try {
      final images = await widget.readImages();
      if (!mounted || !widget.enabled) return;
      if (images.isNotEmpty) {
        widget.onImages(images);
        return;
      }
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted || !widget.enabled || data?.text == null) return;
      final value = widget.controller.value;
      final selection = value.selection.isValid
          ? value.selection
          : TextSelection.collapsed(offset: value.text.length);
      widget.controller.value = value.copyWith(
        text: value.text
            .replaceRange(selection.start, selection.end, data!.text!),
        selection: TextSelection.collapsed(
            offset: selection.start + data.text!.length),
        composing: TextRange.empty,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('图片粘贴失败，请重试')));
      }
    } finally {
      _pasting = false;
    }
  }

  Widget _menu(BuildContext context, EditableTextState editor) {
    void paste() {
      editor.hideToolbar();
      _paste();
    }

    final items = [
      for (final item in editor.contextMenuButtonItems)
        if (item.type != ContextMenuButtonType.paste) item,
      // Flutter only checks for text when deciding whether Paste is enabled.
      // Keep it available for an image-only clipboard too.
      if (widget.enabled)
        ContextMenuButtonItem(
            type: ContextMenuButtonType.paste, onPressed: paste),
    ];
    return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: editor.contextMenuAnchors, buttonItems: items);
  }

  @override
  Widget build(BuildContext context) => Actions(
        actions: {
          PasteTextIntent: CallbackAction<PasteTextIntent>(onInvoke: (_) {
            _paste();
            return null;
          }),
        },
        child: widget.builder(_menu),
      );
}
