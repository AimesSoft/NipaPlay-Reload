import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';

class TranslationButton extends StatefulWidget {
  final int animeId;
  final String summary;
  final Map<int, String> translatedSummaries;
  final Function(Map<int, String>) onTranslationUpdated;
  final bool isShowingTranslation;
  final Function(bool) onTranslationStateChanged;

  const TranslationButton({
    super.key,
    required this.animeId,
    required this.summary,
    required this.translatedSummaries,
    required this.onTranslationUpdated,
    required this.isShowingTranslation,
    required this.onTranslationStateChanged,
  });

  @override
  State<TranslationButton> createState() => _TranslationButtonState();
}

class _TranslationButtonState extends State<TranslationButton> {
  static const String _translationCacheKey = 'bangumi_translation_cache';
  static const Duration _translationCacheDuration = Duration(days: 7);
  bool _isTranslating = false;
  String? _errorMessage;

  Future<String?> _translateSummary(String text) async {
    try {
      setState(() {
        _isTranslating = true;
        _errorMessage = null;
      });
      
      final appSecret = await DandanplayService.getAppSecret();
      ////debugPrint('开始请求翻译...');
      
      final response = await http.post(
        Uri.parse('https://nipaplay.aimes-soft.com/tran.php'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'appSecret': appSecret,
          'text': text,
        }),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('翻译请求超时');
        },
      );

      if (response.statusCode == 200) {
        ////debugPrint('翻译请求成功');
        return response.body;
      }
      ////debugPrint('翻译请求失败，状态码: ${response.statusCode}');
      throw Exception('翻译请求失败，状态码: ${response.statusCode}');
    } on TimeoutException {
      const error = '翻译请求超时，请检查网络连接';
      setState(() {
        _errorMessage = error;
      });
      _showErrorSnackBar(error);
      return null;
    } on SocketException {
      const error = '网络连接失败，请检查网络设置';
      setState(() {
        _errorMessage = error;
      });
      _showErrorSnackBar(error);
      return null;
    } catch (e) {
      final error = '翻译失败: ${e.toString()}';
      setState(() {
        _errorMessage = error;
      });
      _showErrorSnackBar(error);
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isTranslating = false;
        });
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    BlurSnackBar.show(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _isTranslating ? null : () async {
                if (!widget.translatedSummaries.containsKey(widget.animeId)) {
                  ////debugPrint('未找到缓存翻译，开始请求翻译...');
                  final translation = await _translateSummary(widget.summary);
                  if (translation != null) {
                    ////debugPrint('翻译成功，更新状态');
                    final updatedTranslations = Map<int, String>.from(widget.translatedSummaries);
                    updatedTranslations[widget.animeId] = translation;
                    widget.onTranslationUpdated(updatedTranslations);
                    widget.onTranslationStateChanged(true);
                  }
                } else {
                  ////debugPrint('使用缓存翻译');
                  widget.onTranslationStateChanged(!widget.isShowingTranslation);
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isTranslating)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    else if (_errorMessage != null)
                      Icon(
                        Icons.error_outline,
                        size: 16,
                        color: Colors.red[300],
                      )
                    else
                      const Icon(
                        Ionicons.language,
                        size: 16,
                        color: Colors.white,
                      ),
                    const SizedBox(width: 6),
                    Text(
                      _isTranslating
                          ? '翻译中...'
                          : (_errorMessage != null
                              ? '重试'
                              : (widget.translatedSummaries.containsKey(widget.animeId)
                                  ? (widget.isShowingTranslation ? '显示原文' : '显示翻译')
                                  : '翻译为中文')),
                      locale:Locale("zh-Hans","zh"),
style: TextStyle(
                        color: _errorMessage != null ? Colors.red[300] : Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
} 