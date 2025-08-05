import 'package:flutter/material.dart';
import 'dart:async';

class TypingText extends StatefulWidget {
  final List<String> messages;
  final TextStyle? style;
  final Duration typingSpeed;
  final Duration deleteSpeed;
  final Duration pauseDuration;

  const TypingText({
    super.key,
    required this.messages,
    this.style,
    this.typingSpeed = const Duration(milliseconds: 50),
    this.deleteSpeed = const Duration(milliseconds: 30),
    this.pauseDuration = const Duration(seconds: 2),
  });

  @override
  State<TypingText> createState() => _TypingTextState();
}

class _TypingTextState extends State<TypingText> {
  String _currentText = '';
  int _currentMessageIndex = 0;
  Timer? _timer;
  bool _isDeleting = false;
  int _charIndex = 0;

  @override
  void initState() {
    super.initState();
    _startTypingAnimation();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(TypingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messages != widget.messages) {
      _currentMessageIndex = 0;
      _charIndex = 0;
      _isDeleting = false;
      _currentText = '';
      _startTypingAnimation();
    }
  }

  void _startTypingAnimation() {
    _timer?.cancel();

    if (widget.messages.isEmpty) {
      setState(() => _currentText = '');
      return;
    }

    _timer = Timer.periodic(
      _isDeleting ? widget.deleteSpeed : widget.typingSpeed,
      (timer) {
        if (widget.messages.isEmpty) return;

        setState(() {
          if (_isDeleting) {
            if (_currentText.isEmpty) {
              _isDeleting = false;
              _currentMessageIndex = (_currentMessageIndex + 1) % widget.messages.length;
              _charIndex = 0;
            } else {
              _currentText = _currentText.substring(0, _currentText.length - 1);
            }
          } else {
            final targetMessage = widget.messages[_currentMessageIndex];
            if (_charIndex < targetMessage.length) {
              _currentText += targetMessage[_charIndex];
              _charIndex++;
            } else {
              timer.cancel();
              if (widget.messages.length > 1) {
                Timer(widget.pauseDuration, () {
                  if (mounted) {
                    _isDeleting = true;
                    _startTypingAnimation();
                  }
                });
              }
            }
          }
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _currentText,
      style: widget.style,
    );
  }
} 