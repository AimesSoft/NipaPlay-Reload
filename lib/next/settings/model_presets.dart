/// Codex 0.144.1 requires the Responses API, including streaming and tool calls.
/// Editable fill-in templates only; none is a default route or a URL allowlist.
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
    baseUrl: 'https://api.deepseek.com/',
    model: 'deepseek-flash',
    responses: true
  ),
  (
    name: '智谱',
    baseUrl: 'https://open.bigmodel.cn/api/v1',
    model: 'glm-5.3-flash',
    responses: true
  ),
  (
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    model: 'openai/gpt-5.4',
    responses: true
  ),
  (name: '自定义（Responses API）', baseUrl: '', model: '', responses: true),
];
