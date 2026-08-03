import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/services/remote_text_input_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_input_controls.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_view_container.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:qr_flutter/qr_flutter.dart';

typedef TvOSRemoteInputRequestHandler = Future<void> Function(
  BuildContext context,
  TvOSRemoteTextInputTarget target,
);

@visibleForTesting
bool resolveTvOSRemoteTextInputEnabled({
  required bool platformIsTvOS,
  required AppDisplaySurface surface,
}) {
  return platformIsTvOS || surface == AppDisplaySurface.television;
}

bool useTvOSRemoteTextInput(BuildContext context) {
  return resolveTvOSRemoteTextInputEnabled(
    platformIsTvOS: globals.isTvOS,
    surface: AppDisplaySurfaceScope.of(context),
  );
}

/// Groups related fields into one QR session. Only explicitly anchored fields
/// inside this subtree are collected, so unrelated controls remain untouched.
class TvOSRemoteTextInputGroup extends StatelessWidget {
  const TvOSRemoteTextInputGroup({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Marks a focusable TV control whose activation target is the text field
/// inside it. The global handler never searches arbitrary focused subtrees.
class TvOSRemoteTextInputAnchor extends StatelessWidget {
  const TvOSRemoteTextInputAnchor({
    super.key,
    required this.child,
    this.title,
    this.maxLength,
    this.fieldId,
    this.required = false,
    this.obscureText,
  });

  final Widget child;
  final String? title;
  final int? maxLength;
  final String? fieldId;
  final bool required;
  final bool? obscureText;

  @override
  Widget build(BuildContext context) => child;
}

/// Keeps tvOS focus on a Flutter control instead of handing it to the native
/// text input. The global remote-input handler can then consume Select before
/// tvOS presents its on-screen keyboard.
class TvOSRemoteTextInputControl extends StatefulWidget {
  const TvOSRemoteTextInputControl({
    super.key,
    required this.child,
    this.focusNode,
    this.title,
    this.maxLength,
    this.fieldId,
    this.required = false,
    this.obscureText,
    this.autofocus = false,
  });

  final FocusNode? focusNode;
  final Widget child;
  final String? title;
  final int? maxLength;
  final String? fieldId;
  final bool required;
  final bool? obscureText;
  final bool autofocus;

  @override
  State<TvOSRemoteTextInputControl> createState() =>
      _TvOSRemoteTextInputControlState();
}

class _TvOSRemoteTextInputControlState
    extends State<TvOSRemoteTextInputControl> {
  late final FocusNode _internalFocusNode;
  bool _showFocusHighlight = false;
  FocusNode get _focusNode => widget.focusNode ?? _internalFocusNode;

  @override
  void initState() {
    super.initState();
    _internalFocusNode = FocusNode(
      debugLabel: 'tvos_remote_text_input_control',
    );
  }

  @override
  void dispose() {
    _internalFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!useTvOSRemoteTextInput(context)) {
      return widget.child;
    }
    return TvOSRemoteTextInputAnchor(
      title: widget.title,
      maxLength: widget.maxLength,
      fieldId: widget.fieldId,
      required: widget.required,
      obscureText: widget.obscureText,
      child: FocusableActionDetector(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onShowFocusHighlight: (value) {
          if (_showFocusHighlight == value) return;
          setState(() => _showFocusHighlight = value);
        },
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => null,
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _focusNode.requestFocus,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _showFocusHighlight
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 2,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
            ),
            child: ExcludeFocus(child: widget.child),
          ),
        ),
      ),
    );
  }
}

class TvOSRemoteTextInputFieldTarget {
  const TvOSRemoteTextInputFieldTarget({
    required this.id,
    required this.element,
    required this.editableText,
    required this.title,
    required this.maxLength,
    required this.required,
    required this.obscureText,
  });

  final String id;
  final Element element;
  final EditableText editableText;
  final String title;
  final int? maxLength;
  final bool required;
  final bool obscureText;

  TextEditingController get controller => editableText.controller;
  bool get multiline => editableText.maxLines != 1;
  String get inputType => _remoteInputTypeName(editableText.keyboardType);
}

class TvOSRemoteTextInputTarget {
  const TvOSRemoteTextInputTarget({
    required this.element,
    required this.title,
    required this.fields,
    required this.primaryIndex,
  });

  final Element element;
  final String title;
  final List<TvOSRemoteTextInputFieldTarget> fields;
  final int primaryIndex;

  TvOSRemoteTextInputFieldTarget get primaryField => fields[primaryIndex];
  EditableText get editableText => primaryField.editableText;
  TextEditingController get controller => primaryField.controller;
  bool get obscureText => primaryField.obscureText;
  bool get multiline => primaryField.multiline;
  String get inputType => primaryField.inputType;
  int? get maxLength => primaryField.maxLength;
  bool get isGroup => fields.length > 1;
}

@visibleForTesting
TvOSRemoteTextInputTarget? findTvOSRemoteTextInputTarget(FocusNode? focusNode) {
  final focusContext = focusNode?.context;
  if (focusContext is! Element) return null;

  Element? editableElement;
  Element? anchorElement;
  Element? groupElement;
  if (focusContext.widget is EditableText) {
    editableElement = focusContext;
  }
  focusContext.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (editableElement == null && widget is EditableText) {
      editableElement = ancestor;
    }
    if (anchorElement == null && widget is TvOSRemoteTextInputAnchor) {
      anchorElement = ancestor;
    }
    if (groupElement == null && widget is TvOSRemoteTextInputGroup) {
      groupElement = ancestor;
    }
    return true;
  });

  Element? findEditableInDescendants(Element root) {
    Element? result;
    void visit(Element element) {
      if (result != null) return;
      if (element != root && element.widget is TvOSRemoteTextInputGroup) return;
      if (element.widget is EditableText) {
        result = element;
        return;
      }
      element.visitChildElements(visit);
    }

    root.visitChildElements(visit);
    return result;
  }

  if (editableElement == null && anchorElement != null) {
    editableElement = findEditableInDescendants(anchorElement!);
  }
  final resolvedElement = editableElement;
  if (resolvedElement == null) return null;

  TvOSRemoteTextInputFieldTarget buildFieldTarget(
    Element fieldElement,
    TvOSRemoteTextInputAnchor? anchor,
    int index,
  ) {
    final editable = fieldElement.widget as EditableText;
    String? title = anchor?.title;
    int? maxLength = anchor?.maxLength;
    fieldElement.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is TextField) {
        title ??= widget.decoration?.labelText ?? widget.decoration?.hintText;
        maxLength ??= widget.maxLength;
      } else if (widget is CupertinoTextField) {
        title ??= widget.placeholder;
        maxLength ??= widget.maxLength;
      }
      return title == null || maxLength == null;
    });
    return TvOSRemoteTextInputFieldTarget(
      id: anchor?.fieldId?.trim().isNotEmpty == true
          ? anchor!.fieldId!.trim()
          : 'field_$index',
      element: fieldElement,
      editableText: editable,
      title: title?.trim().isNotEmpty == true ? title!.trim() : '输入文字',
      maxLength: maxLength,
      required: anchor?.required ?? false,
      obscureText: anchor?.obscureText ?? editable.obscureText,
    );
  }

  final group = groupElement?.widget is TvOSRemoteTextInputGroup
      ? groupElement!.widget as TvOSRemoteTextInputGroup
      : null;
  if (group != null) {
    final groupedFields = <TvOSRemoteTextInputFieldTarget>[];
    void collectAnchors(Element element) {
      if (element != groupElement &&
          element.widget is TvOSRemoteTextInputGroup) {
        return;
      }
      final widget = element.widget;
      if (widget is TvOSRemoteTextInputAnchor) {
        final fieldElement = findEditableInDescendants(element);
        if (fieldElement != null) {
          groupedFields.add(
            buildFieldTarget(fieldElement, widget, groupedFields.length),
          );
        }
        return;
      }
      element.visitChildElements(collectAnchors);
    }

    groupElement!.visitChildElements(collectAnchors);
    if (groupedFields.isNotEmpty) {
      final primaryIndex = groupedFields.indexWhere(
        (field) => identical(field.element, resolvedElement),
      );
      return TvOSRemoteTextInputTarget(
        element: groupElement!,
        title: group.title.trim().isEmpty ? '远程输入' : group.title.trim(),
        fields: List<TvOSRemoteTextInputFieldTarget>.unmodifiable(
          groupedFields,
        ),
        primaryIndex: primaryIndex < 0 ? 0 : primaryIndex,
      );
    }
  }

  final anchor = anchorElement?.widget is TvOSRemoteTextInputAnchor
      ? anchorElement!.widget as TvOSRemoteTextInputAnchor
      : null;
  final field = buildFieldTarget(resolvedElement, anchor, 0);
  return TvOSRemoteTextInputTarget(
    element: resolvedElement,
    title: field.title,
    fields: <TvOSRemoteTextInputFieldTarget>[field],
    primaryIndex: 0,
  );
}

void _applyTvOSRemoteTextInputFieldValue(
  TvOSRemoteTextInputFieldTarget target,
  String value,
) {
  if (!target.element.mounted) return;
  final editable = target.editableText;
  final oldValue = editable.controller.value;
  var newValue = TextEditingValue(
    text: value,
    selection: TextSelection.collapsed(offset: value.length),
  );
  for (final formatter
      in editable.inputFormatters ?? const <TextInputFormatter>[]) {
    newValue = formatter.formatEditUpdate(oldValue, newValue);
  }
  editable.controller.value = newValue;
  editable.onChanged?.call(newValue.text);
}

@visibleForTesting
void applyTvOSRemoteTextInputValues(
  TvOSRemoteTextInputTarget target,
  Map<String, String> values,
) {
  for (final field in target.fields) {
    final value = values[field.id];
    if (value != null) {
      _applyTvOSRemoteTextInputFieldValue(field, value);
    }
  }
}

@visibleForTesting
void applyTvOSRemoteTextInputValue(
  TvOSRemoteTextInputTarget target,
  String value,
) {
  _applyTvOSRemoteTextInputFieldValue(target.primaryField, value);
}

class TvOSRemoteTextInputScope extends StatefulWidget {
  const TvOSRemoteTextInputScope({
    super.key,
    required this.child,
    this.enabled = true,
    this.onRemoteInputRequested,
  });

  final Widget child;
  final bool enabled;
  final TvOSRemoteInputRequestHandler? onRemoteInputRequested;

  @override
  State<TvOSRemoteTextInputScope> createState() =>
      _TvOSRemoteTextInputScopeState();
}

class _TvOSRemoteTextInputScopeState extends State<TvOSRemoteTextInputScope> {
  bool _isOpening = false;
  OnKeyEventCallback? _earlyKeyHandler;

  @override
  void initState() {
    super.initState();
    _earlyKeyHandler = _handleEarlyKeyEvent;
    FocusManager.instance.addEarlyKeyEventHandler(_earlyKeyHandler!);
  }

  @override
  void dispose() {
    if (_earlyKeyHandler != null) {
      FocusManager.instance.removeEarlyKeyEventHandler(_earlyKeyHandler!);
      _earlyKeyHandler = null;
    }
    super.dispose();
  }

  KeyEventResult _handleEarlyKeyEvent(KeyEvent event) {
    if (!widget.enabled || _isOpening || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (NipaplayLargeScreenInputControls.fromKeyEvent(event) !=
        NipaplayLargeScreenInputCommand.activate) {
      return KeyEventResult.ignored;
    }
    final target = findTvOSRemoteTextInputTarget(
      FocusManager.instance.primaryFocus,
    );
    if (target == null) return KeyEventResult.ignored;
    _isOpening = true;
    unawaited(_openRemoteInput(target));
    return KeyEventResult.handled;
  }

  Future<void> _openRemoteInput(TvOSRemoteTextInputTarget target) async {
    try {
      final handler = widget.onRemoteInputRequested;
      if (handler != null) {
        await handler(context, target);
        return;
      }
      await _showRemoteInput(target);
    } catch (error) {
      if (mounted) {
        BlurSnackBar.show(
          context,
          '无法开始远程输入：${error.toString().replaceFirst('Bad state: ', '')}',
        );
      }
    } finally {
      _isOpening = false;
    }
  }

  Future<void> _showRemoteInput(TvOSRemoteTextInputTarget target) async {
    final server = ServiceProvider.webServer;
    if (!server.isRunning) {
      final started = await server.startServer();
      if (!started) {
        throw StateError(server.lastStartErrorMessage ?? '无法启动远程输入服务');
      }
    }
    final accessUrls = await server.getAccessUrls();
    String? baseUrl;
    for (final url in accessUrls) {
      if (!_isLoopbackUrl(url)) {
        baseUrl = url;
        break;
      }
    }
    if (baseUrl == null) {
      throw StateError('没有可供手机访问的局域网地址');
    }

    final session = RemoteTextInputService.instance.createGroupSession(
      title: target.title,
      fields: target.fields
          .map(
            (field) => RemoteTextInputField(
              id: field.id,
              title: field.title,
              initialValue: field.controller.text,
              obscureText: field.obscureText,
              multiline: field.multiline,
              inputType: field.inputType,
              maxLength: field.maxLength,
              required: field.required,
            ),
          )
          .toList(growable: false),
    );
    final inputUri = RemoteTextInputService.instance.buildInputUri(
      baseUrl,
      session,
    );

    BuildContext? routeContext;
    var routeActive = true;
    unawaited(session.submissionResult.then((submission) {
      if (!routeActive || submission == null) return;
      final context = routeContext;
      if (context == null || !context.mounted) return;
      Navigator.of(context).pop(submission.values);
    }));

    Map<String, String>? result;
    try {
      if (!target.element.mounted) {
        session.cancel();
        return;
      }
      result = await NipaplayLargeScreenViewContainer.show<Map<String, String>>(
        context: target.element,
        title: target.title,
        subtitle:
            'KEY ${session.displayKey} · ${target.fields.length} 项 · 10 分钟内有效',
        maxWidth: 720,
        maxHeightFactor: 0.84,
        builder: (context) {
          routeContext = context;
          if (session.status == RemoteTextInputSessionStatus.submitted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                Navigator.of(context).pop(session.submittedValues);
              }
            });
          }
          return _TvOSRemoteTextInputQrView(
            inputUri: inputUri,
            displayKey: session.displayKey,
            fieldCount: target.fields.length,
          );
        },
      );
    } finally {
      routeActive = false;
      if (session.isPending) {
        session.cancel();
      }
    }
    if (result != null) {
      applyTvOSRemoteTextInputValues(target, result);
    }
  }

  bool _isLoopbackUrl(String value) {
    final host = Uri.tryParse(value)?.host.toLowerCase();
    return host == null ||
        host.isEmpty ||
        host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1';
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _TvOSRemoteTextInputQrView extends StatelessWidget {
  const _TvOSRemoteTextInputQrView({
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
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(34, 24, 34, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '使用手机扫描二维码输入',
              style: TextStyle(
                color: textColor,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              fieldCount > 1
                  ? '一次填写 $fieldCount 项；NipaPlay 内扫码打开原生表单，系统相机扫码打开浏览器。'
                  : 'NipaPlay 内扫码会打开原生输入菜单，系统相机扫码会打开浏览器。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor.withValues(alpha: 0.66),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 22),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: QrImageView(
                  data: inputUri.toString(),
                  version: QrVersions.auto,
                  size: 300,
                  backgroundColor: Colors.white,
                ),
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
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor.withValues(alpha: 0.54),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _remoteInputTypeName(TextInputType type) {
  final value = type.toString().toLowerCase();
  if (value.contains('number')) return 'number';
  if (value.contains('phone')) return 'phone';
  if (value.contains('email')) return 'email';
  if (value.contains('url')) return 'url';
  return 'text';
}
