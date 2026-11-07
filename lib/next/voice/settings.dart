import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';

import '../settings/registry.dart';
import 'model_store.dart';
import 'models.dart';

List<SettingEntry> voiceSettings({VoiceModelStore? modelStore}) {
  final store = modelStore ?? VoiceModelStore.instance;
  SettingEntry entry(
          String key,
          String title,
          String description,
          Schema schema,
          Object? fallback,
          String storageKey,
          Object? Function() read,
          Future<void> Function(Object?) write,
          {bool writable = true}) =>
      SettingEntry(
        key: key,
        title: title,
        description: description,
        schema: schema,
        defaultValue: fallback,
        storageKey: storageKey,
        scope: 'device',
        reader: 'lib/next/voice/model_store.dart',
        writer: 'lib/next/voice/model_store.dart',
        decodeStorage: (v) => v ?? fallback,
        read: () async {
          await store.load();
          return read();
        },
        write: write,
        writable: writable,
        appliesTo: const {
          'platforms': ['macos', 'windows', 'linux', 'ios']
        },
        appliesNow: () => VoiceModelStore.supported,
        appliesReason: () => '语音输入支持桌面端、iPhone 和 iPad。',
      );
  return [
    entry(
        'labs.voiceEnabled',
        '语音输入',
        '实验功能：为梨花对话输入文字。用户要求开启时可设置 true：本机模式后台下载所选模型，云端模式使用 voice.configure 中保存的服务；false 停止录音和下载，保留已下载模型。不自动发送、不启动麦克风。写入成功只表示开关保存；读取 labs.voiceStatus 确认模型 ready 或查看原始错误。',
        const BooleanSchema(),
        false,
        VoiceModelStore.enabledKey,
        () => store.enabled,
        (v) => store.setEnabled(v as bool)),
    entry(
        'labs.voiceModel',
        '语音识别模型',
        '本机离线模型：xasr-zh-en 为中英双语含标点（约 128 MiB）；zipformer-zh-small 为中文轻量（约 20 MiB）。选择模型会停止当前录音；已开启时后台下载，关闭时只保存选择。录音不上传。',
        StringSchema(values: voiceModels.map((m) => m.id).toList()),
        VoiceModelStore.defaultModelId,
        VoiceModelStore.modelKey,
        () => store.modelId,
        (v) => store.select(v as String)),
    entry(
        'labs.voiceModelDownload',
        '下载所选语音模型',
        'true 开始或重试所选模型下载，后台进行；该开关为 true 表示已下载或已请求准备，不代表就绪；读取 labs.voiceStatus 查看进度。false 关闭语音输入并删除所选模型，不影响其他模型。开启后无需重复下载。',
        const BooleanSchema(),
        false,
        '@runtime:voiceModelDownload',
        () => store.installed || store.downloadRequested, (v) async {
      await store.load();
      if (v == true) {
        store.prepare();
      } else {
        await store.remove();
      }
    }),
    entry(
        'labs.voiceStatus',
        '语音模型状态',
        '只读 JSON：supported、enabled、model、phase（本机模型 not_downloaded/downloading/installing/ready/failed）、configuration、ready（配置就绪，非连通测试）、recordingPhase、receivedAudioBytes、recordingError、installed、downloadRequested、downloadedBytes、downloadBytes、error、recording。Agent 不能通过设置开始录音；用户在本机输入框点击麦克风，文字确认后发送。',
        const StringSchema(),
        '{}',
        '@runtime:voiceStatus',
        () => jsonEncode(store.status),
        (_) async {},
        writable: false),
  ];
}
