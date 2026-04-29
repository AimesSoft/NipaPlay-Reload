import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/services/danmaku_spoiler_filter_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_editable_slider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_item.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class DanmakuSettingsPage extends StatefulWidget {
  const DanmakuSettingsPage({super.key});

  @override
  State<DanmakuSettingsPage> createState() => _DanmakuSettingsPageState();
}

class _DanmakuSettingsPageState extends State<DanmakuSettingsPage> {
  static const Color _fluentAccentColor = Color(0xFFFF2E55);

  DanmakuRenderEngine _selectedDanmakuRenderEngine = DanmakuRenderEngine.canvas;

  final GlobalKey _danmakuRenderEngineDropdownKey = GlobalKey();
  final GlobalKey _spoilerAiApiFormatDropdownKey = GlobalKey();

  final TextEditingController _spoilerAiUrlController = TextEditingController();
  final TextEditingController _spoilerAiModelController =
      TextEditingController();
  final TextEditingController _spoilerAiApiKeyController =
      TextEditingController();
  bool _spoilerAiControllersInitialized = false;
  bool _isSavingSpoilerAiSettings = false;
  SpoilerAiApiFormat _spoilerAiApiFormatDraft = SpoilerAiApiFormat.openai;
  double _spoilerAiTemperatureDraft = 0.5;

  @override
  void initState() {
    super.initState();
    _loadDanmakuRenderEngineSettings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_spoilerAiControllersInitialized) return;

    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    _spoilerAiApiFormatDraft = videoState.spoilerAiApiFormat;
    _spoilerAiTemperatureDraft = videoState.spoilerAiTemperature;
    _spoilerAiUrlController.text = videoState.spoilerAiApiUrl;
    _spoilerAiModelController.text = videoState.spoilerAiModel;
    _spoilerAiApiKeyController.text = videoState.spoilerAiApiKey;
    _spoilerAiControllersInitialized = true;
  }

  @override
  void dispose() {
    _spoilerAiUrlController.dispose();
    _spoilerAiModelController.dispose();
    _spoilerAiApiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadDanmakuRenderEngineSettings() async {
    if (!mounted) return;
    setState(() {
      _selectedDanmakuRenderEngine = DanmakuKernelFactory.getKernelType();
    });
  }

  Future<void> _saveDanmakuRenderEngineSettings(
      DanmakuRenderEngine engine) async {
    await DanmakuKernelFactory.saveKernelType(engine);

    if (!mounted) return;
    BlurSnackBar.show(context, '弹幕渲染引擎已切换');

    setState(() {
      _selectedDanmakuRenderEngine = engine;
    });
  }

  Future<void> _saveSpoilerAiSettings(VideoPlayerState videoState) async {
    if (_isSavingSpoilerAiSettings) return;

    final url = _spoilerAiUrlController.text.trim();
    final model = _spoilerAiModelController.text.trim();
    final apiKeyInput = _spoilerAiApiKeyController.text.trim();

    if (url.isEmpty) {
      BlurSnackBar.show(context, '请输入 AI 接口 URL');
      return;
    }
    if (model.isEmpty) {
      BlurSnackBar.show(context, '请输入模型名称');
      return;
    }
    if (apiKeyInput.isEmpty) {
      BlurSnackBar.show(context, '请输入 API Key');
      return;
    }

    setState(() {
      _isSavingSpoilerAiSettings = true;
    });

    try {
      await videoState.updateSpoilerAiSettings(
        apiFormat: _spoilerAiApiFormatDraft,
        apiUrl: url,
        model: model,
        temperature: _spoilerAiTemperatureDraft,
        apiKey: apiKeyInput,
      );
      _spoilerAiApiKeyController.text = apiKeyInput;
      if (!mounted) return;
      BlurSnackBar.show(context, '防剧透 AI 设置已保存');
    } catch (e) {
      if (!mounted) return;
      BlurSnackBar.show(context, '保存失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSavingSpoilerAiSettings = false;
        });
      }
    }
  }

  String _getDanmakuRenderEngineDescription(DanmakuRenderEngine engine) {
    switch (engine) {
      case DanmakuRenderEngine.cpu:
        return 'CPU 渲染引擎\n使用 Flutter Widget 进行绘制，兼容性好，但在低端设备上弹幕量大时可能卡顿。';
      case DanmakuRenderEngine.gpu:
        return 'GPU 渲染引擎 (实验性)\n使用自定义着色器和字体图集，性能更高，功耗更低，但目前仍在开发中。';
      case DanmakuRenderEngine.canvas:
        return 'Canvas 弹幕渲染引擎\n来自软件kazumi的开发者\n使用Canvas绘制弹幕，高性能，低功耗，支持大量弹幕同时显示。';
      case DanmakuRenderEngine.nipaplayNext:
        return 'NipaPlay Next\n是CPU弹幕和Canvas弹幕优点的集合体，包含两边的全部优点。';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      children: [
        SettingsItem.dropdown(
          title: '弹幕渲染引擎',
          subtitle: '选择弹幕的渲染方式',
          icon: Ionicons.hardware_chip_outline,
          items: [
            DropdownMenuItemData(
              title: 'CPU 渲染',
              value: DanmakuRenderEngine.cpu,
              isSelected:
                  _selectedDanmakuRenderEngine == DanmakuRenderEngine.cpu,
              description:
                  _getDanmakuRenderEngineDescription(DanmakuRenderEngine.cpu),
            ),
            DropdownMenuItemData(
              title: 'GPU 渲染 (实验性)',
              value: DanmakuRenderEngine.gpu,
              isSelected:
                  _selectedDanmakuRenderEngine == DanmakuRenderEngine.gpu,
              description:
                  _getDanmakuRenderEngineDescription(DanmakuRenderEngine.gpu),
            ),
            DropdownMenuItemData(
              title: 'Canvas 弹幕 (实验性)',
              value: DanmakuRenderEngine.canvas,
              isSelected:
                  _selectedDanmakuRenderEngine == DanmakuRenderEngine.canvas,
              description: _getDanmakuRenderEngineDescription(
                DanmakuRenderEngine.canvas,
              ),
            ),
            DropdownMenuItemData(
              title: 'NipaPlay Next',
              value: DanmakuRenderEngine.nipaplayNext,
              isSelected: _selectedDanmakuRenderEngine ==
                  DanmakuRenderEngine.nipaplayNext,
              description: _getDanmakuRenderEngineDescription(
                DanmakuRenderEngine.nipaplayNext,
              ),
            ),
          ],
          onChanged: (dynamic value) {
            if (value is! DanmakuRenderEngine) return;
            _saveDanmakuRenderEngineSettings(value);
          },
          dropdownKey: _danmakuRenderEngineDropdownKey,
        ),
        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            return SettingsItem.toggle(
              title: context.l10n.rememberDanmakuOffset,
              subtitle: context.l10n.rememberDanmakuOffsetSubtitle,
              icon: Icons.av_timer,
              value: videoState.rememberDanmakuOffset,
              onChanged: (bool value) async {
                await videoState.setRememberDanmakuOffset(value);
                if (!context.mounted) return;
                BlurSnackBar.show(
                  context,
                  value
                      ? context.l10n.rememberDanmakuOffsetEnabled
                      : context.l10n.rememberDanmakuOffsetDisabled,
                );
              },
            );
          },
        ),
        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        Consumer<SettingsProvider>(
          builder: (context, settingsProvider, child) {
            return SettingsItem.toggle(
              title: context.l10n.danmakuConvertToSimplified,
              subtitle: context.l10n.danmakuConvertToSimplifiedSubtitle,
              icon: Ionicons.language_outline,
              value: settingsProvider.danmakuConvertToSimplified,
              onChanged: (bool value) {
                settingsProvider.setDanmakuConvertToSimplified(value);
                if (context.mounted) {
                  BlurSnackBar.show(
                    context,
                    value
                        ? context.l10n.danmakuConvertToSimplifiedEnabled
                        : context.l10n.danmakuConvertToSimplifiedDisabled,
                  );
                }
              },
            );
          },
        ),
        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            final widgets = <Widget>[
              SettingsItem.toggle(
                title: '防剧透模式',
                subtitle: '开启后，加载弹幕后将通过 AI 识别并屏蔽疑似剧透弹幕',
                icon: Ionicons.shield_outline,
                value: videoState.spoilerPreventionEnabled,
                onChanged: (bool value) async {
                  if (value && !videoState.spoilerAiConfigReady) {
                    BlurSnackBar.show(context, '请先填写并保存 AI 接口配置');
                    return;
                  }
                  await videoState.setSpoilerPreventionEnabled(value);
                  if (!context.mounted) return;
                  BlurSnackBar.show(
                    context,
                    value ? '已开启防剧透模式' : '已关闭防剧透模式',
                  );
                },
              ),
            ];

            widgets.add(
              Divider(
                color: colorScheme.onSurface.withOpacity(0.12),
                height: 1,
              ),
            );

            final bool isGemini =
                _spoilerAiApiFormatDraft == SpoilerAiApiFormat.gemini;
            final urlHint = isGemini
                ? 'https://generativelanguage.googleapis.com/v1beta/models'
                : 'https://api.openai.com/v1/chat/completions';
            final modelHint = isGemini ? 'gemini-1.5-flash' : 'gpt-5';

            widgets.add(
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                child: SettingsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Ionicons.settings_outline,
                            color: colorScheme.onSurface,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '防剧透 AI 设置',
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '开启防剧透前请先填写并保存配置（必须提供接口 URL / Key / 模型）。',
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isGemini
                            ? 'Gemini：URL 可填到 /v1beta/models，实际请求会自动拼接 /<模型>:generateContent。'
                            : 'OpenAI：URL 建议填写 /v1/chat/completions（兼容接口亦可）。',
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            '接口格式',
                            style: TextStyle(
                              color: colorScheme.onSurface.withOpacity(0.7),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 12),
                          BlurDropdown<SpoilerAiApiFormat>(
                            dropdownKey: _spoilerAiApiFormatDropdownKey,
                            items: [
                              DropdownMenuItemData(
                                title: 'OpenAI 兼容',
                                value: SpoilerAiApiFormat.openai,
                                isSelected: _spoilerAiApiFormatDraft ==
                                    SpoilerAiApiFormat.openai,
                              ),
                              DropdownMenuItemData(
                                title: 'Gemini',
                                value: SpoilerAiApiFormat.gemini,
                                isSelected: _spoilerAiApiFormatDraft ==
                                    SpoilerAiApiFormat.gemini,
                              ),
                            ],
                            onItemSelected: (format) {
                              setState(() {
                                _spoilerAiApiFormatDraft = format;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _spoilerAiUrlController,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        enableSuggestions: false,
                        cursorColor: _fluentAccentColor,
                        decoration: InputDecoration(
                          labelText: '接口 URL',
                          labelStyle: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.7),
                          ),
                          hintText: urlHint,
                          hintStyle: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.38),
                          ),
                          filled: true,
                          fillColor: colorScheme.onSurface.withOpacity(0.1),
                          border: const OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide:
                                BorderSide(color: _fluentAccentColor, width: 2),
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                        ),
                        style: TextStyle(color: colorScheme.onSurface),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _spoilerAiModelController,
                        autocorrect: false,
                        enableSuggestions: false,
                        cursorColor: _fluentAccentColor,
                        decoration: InputDecoration(
                          labelText: '模型',
                          labelStyle: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.7),
                          ),
                          hintText: modelHint,
                          hintStyle: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.38),
                          ),
                          filled: true,
                          fillColor: colorScheme.onSurface.withOpacity(0.1),
                          border: const OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide:
                                BorderSide(color: _fluentAccentColor, width: 2),
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                        ),
                        style: TextStyle(color: colorScheme.onSurface),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _spoilerAiApiKeyController,
                        autocorrect: false,
                        enableSuggestions: false,
                        cursorColor: _fluentAccentColor,
                        decoration: InputDecoration(
                          labelText: 'API Key',
                          labelStyle: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.7),
                          ),
                          hintText: '请输入你的 API Key',
                          hintStyle: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.38),
                          ),
                          filled: true,
                          fillColor: colorScheme.onSurface.withOpacity(0.1),
                          border: const OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide:
                                BorderSide(color: _fluentAccentColor, width: 2),
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                        ),
                        style: TextStyle(color: colorScheme.onSurface),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '温度：${_spoilerAiTemperatureDraft.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.7),
                          fontSize: 13,
                        ),
                      ),
                      fluent.FluentTheme(
                        data: fluent.FluentThemeData(
                          brightness: Theme.of(context).brightness,
                          accentColor: fluent.AccentColor.swatch({
                            'normal': _fluentAccentColor,
                            'default': _fluentAccentColor,
                          }),
                        ),
                        child: NipaplayLargeScreenEditableSlider(
                          min: 0.0,
                          max: 2.0,
                          divisions: 40,
                          value: _spoilerAiTemperatureDraft.clamp(0.0, 2.0),
                          onChanged: (value) {
                            setState(() {
                              _spoilerAiTemperatureDraft = value;
                            });
                          },
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: BlurButton(
                          icon: _isSavingSpoilerAiSettings
                              ? null
                              : Ionicons.checkmark_outline,
                          text: _isSavingSpoilerAiSettings ? '保存中...' : '保存配置',
                          onTap: _isSavingSpoilerAiSettings
                              ? () {}
                              : () => _saveSpoilerAiSettings(videoState),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          fontSize: 13,
                          iconSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widgets,
            );
          },
        ),
        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        Consumer<SettingsProvider>(
          builder: (context, settingsProvider, child) {
            return SettingsItem.toggle(
              title: '播放时自动匹配弹幕',
              subtitle: '关闭后播放时不再自动识别并加载弹幕，可在弹幕设置中手动匹配',
              icon: Ionicons.sync_outline,
              value: settingsProvider.autoMatchDanmakuOnPlay,
              onChanged: (bool value) {
                settingsProvider.setAutoMatchDanmakuOnPlay(value);
                if (context.mounted) {
                  BlurSnackBar.show(
                    context,
                    value ? '已开启播放时自动匹配弹幕' : '已关闭播放时自动匹配弹幕（可手动匹配）',
                  );
                }
              },
            );
          },
        ),
        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        Consumer<SettingsProvider>(
          builder: (context, settingsProvider, child) {
            return SettingsItem.toggle(
              title: '哈希匹配失败自动匹配弹幕',
              subtitle: '哈希匹配失败时，默认使用文件名搜索的第一个结果自动匹配；关闭后将弹出搜索弹幕菜单',
              icon: Ionicons.search_outline,
              value:
                  settingsProvider.autoMatchDanmakuFirstSearchResultOnHashFail,
              onChanged: (bool value) {
                settingsProvider
                    .setAutoMatchDanmakuFirstSearchResultOnHashFail(value);
                if (context.mounted) {
                  BlurSnackBar.show(
                    context,
                    value ? '已开启匹配失败自动匹配' : '已关闭匹配失败自动匹配（将弹出搜索弹幕菜单）',
                  );
                }
              },
            );
          },
        ),
        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
      ],
    );
  }
}
