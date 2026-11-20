part of 'chat_host.dart';

extension SessionModels on ChatHost {
  UiAgentRuntimeKind get _modelRuntime =>
      dsh == null ? UiAgentRuntimeKind.codex : UiAgentRuntimeKind.dsh;

  ChatMessage get _threadModelDefaults => {..._modelDefaults}..remove('effort');

  File _modelFile(String id) {
    final key = sha256.convert(utf8.encode(jsonEncode([_sessionKey, id])));
    return File(
        '${endpoint.seedRepository.parent.path}/session-models/$key.json');
  }

  Future<List<UiModelChoice>> runtimeModels() async {
    final choices = <UiModelChoice>[];
    String? cursor;
    final seen = <String>{};
    do {
      final result = await _request(
          dsh == null ? 'model/list' : 'nipa/model/list',
          {if (cursor != null) 'cursor': cursor});
      for (final entry in (result['data'] as List).cast<Map>()) {
        final choice = _decodeModel(entry);
        if (choice.model != null) choices.add(choice);
        if (dsh == null &&
            entry['model'] == _modelDefaults['model'] &&
            _modelDefaults['effort'] == null) {
          _modelDefaults['effort'] = choice.reasoning;
        }
      }
      if (choices.isEmpty &&
          (result['failures'] as List?)?.isNotEmpty == true) {
        throw StateError('无法读取运行器的模型目录');
      }
      cursor = result['nextCursor'] as String?;
    } while (cursor != null && seen.add(cursor));
    return choices;
  }

  UiModelChoice _decodeModel(Map value) => UiModelChoice(
          catalog: _modelRuntime,
          source: _modelRuntime == UiAgentRuntimeKind.codex
              ? UiModelSource.codex
              : UiModelSource.nipaplay,
          model: value['model'] as String?,
          label: value['displayName'] as String?,
          provider: value['provider'] as String?,
          providerLabel: value['providerName'] as String?,
          reasoning: (value['reasoning'] ?? value['defaultReasoningEffort'])
              as String?,
          reasoningLevels: [
            for (final effort
                in (value['supportedReasoningEfforts'] as List? ?? const []))
              if (effort is String)
                effort
              else if (effort is Map && effort['reasoningEffort'] is String)
                effort['reasoningEffort'] as String,
          ]);

  Future<UiModelChoice?> _savedModel(String id) async {
    final file = _modelFile(id);
    if (!await file.exists()) return null;
    return _decodeModel(jsonDecode(await file.readAsString()) as Map);
  }

  Future<UiModelChoice?> sessionModel() async {
    final id = threadId;
    return id == null ? null : _savedModel(id);
  }

  UiModelChoice? get nextTurnModel => _nextModels[threadId];

  Future<void> selectSessionModel(UiModelChoice choice, {bool once = false}) =>
      _control(() async {
        if (choice.catalog != _modelRuntime) throw StateError('运行器已切换');
        final id = threadId ?? (await _mainSession())['thread']['id'] as String;
        if (once) {
          _nextModels[id] = choice;
          return;
        }
        final file = _modelFile(id);
        await file.parent.create(recursive: true);
        final staging = File('${file.path}.pending');
        await staging.writeAsString(
            jsonEncode({
              'model': choice.model,
              'provider': choice.provider,
              'displayName': choice.label,
              'providerName': choice.providerLabel,
              'reasoning': choice.reasoning,
              'supportedReasoningEfforts': choice.reasoningLevels,
            }),
            flush: true);
        await staging.rename(file.path);
        _nextModels.remove(id);
      });

  ChatMessage _turnModelParams(UiModelChoice? selected) => {
        if (selected?.model ?? _modelDefaults['model'] case final String name)
          'model': name,
        if (dsh != null)
          'modelProvider': selected?.provider ?? _modelDefaults['modelProvider']
        else
          'effort': selected?.reasoning ?? _modelDefaults['effort'] ?? 'medium',
      };
}
