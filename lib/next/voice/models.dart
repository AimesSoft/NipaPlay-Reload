/// Pinned, independently downloadable offline dictation models.
class VoiceModel {
  const VoiceModel(
      this.id, this.label, this.archive, this.bytes, this.sha256, this.files,
      {this.ctc = false});
  final String id, label, archive, sha256;
  final int bytes;
  final List<String> files;
  final bool ctc;
  String get url =>
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$archive.tar.bz2';
}

const voiceModels = [
  VoiceModel(
    'xasr-zh-en',
    '中英双语 · X-ASR（含标点，约 128 MiB）',
    'sherpa-onnx-x-asr-480ms-streaming-zipformer-transducer-zh-en-punct-int8-2026-06-05',
    133895136,
    'fa5f63d618e5a01526e275a358bb7772e403f84808a4769fba52cffd8160bf74',
    ['encoder.int8.onnx', 'decoder.onnx', 'joiner.int8.onnx', 'tokens.txt'],
  ),
  VoiceModel(
    'zipformer-zh-small',
    '中文轻量 · Zipformer CTC（约 20 MiB）',
    'sherpa-onnx-streaming-zipformer-small-ctc-zh-int8-2025-04-01',
    21264113,
    'b3b309f7ce4a737195fcc6963ea19b0653a7d3401580af5ae0d3e284cbb71f0b',
    ['model.int8.onnx', 'tokens.txt'],
    ctc: true,
  ),
];

VoiceModel voiceModel(String id) => voiceModels.firstWhere((m) => m.id == id);
