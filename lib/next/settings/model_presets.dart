/// Codex 0.144.1 requires the Responses API, including streaming and tool calls.
/// DeepSeek's public Chat Completions endpoint needs a Responses gateway.
const hostModelPresets =
    <({String name, String baseUrl, String model, bool responses})>[
  (
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-5.4',
    responses: true
  ),
  (
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    model: 'deepseek-chat',
    responses: false
  ),
  (
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    model: 'openai/gpt-5.4',
    responses: true
  ),
  (name: '自定义（Responses API）', baseUrl: '', model: '', responses: true),
];
