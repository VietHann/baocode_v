import 'model_provider.dart';

/// Official model endpoints only. This catalog never imports another
/// application's OAuth cookies or tokens. API keys use BaoCode's keychain.
enum ProviderPresetGroup { account, gateway, api, local }

class ProviderPreset {
  const ProviderPreset({
    required this.id,
    required this.name,
    required this.group,
    required this.protocol,
    this.baseUrl = '',
    this.credentialsUrl,
    this.models = const [],
    this.needsKey = true,
  });

  final String id;
  final String name;
  final ProviderPresetGroup group;
  final ProviderProtocol protocol;
  final String baseUrl;
  final String? credentialsUrl;
  final List<ProviderModel> models;
  final bool needsKey;

  ModelProvider create(String providerId) => ModelProvider(
    id: providerId,
    name: name,
    protocol: protocol,
    baseUrl: baseUrl,
    models: models,
    disableNonessentialTraffic: protocol != ProviderProtocol.codex,
    preserveThinking: protocol == ProviderProtocol.openaiChat,
  );

  static ProviderPreset? forProvider(ModelProvider provider) {
    for (final item in all) {
      if (item.name == provider.name &&
          item.protocol == provider.protocol &&
          item.baseUrl == provider.baseUrl) {
        return item;
      }
    }
    return null;
  }

  static ProviderPreset? byId(String id) {
    for (final item in all) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Seed models are only examples. Users can fetch/add models after sign-in.
  static const all = <ProviderPreset>[
    ProviderPreset(
      id: 'chatgpt-codex', name: 'ChatGPT (Codex)',
      group: ProviderPresetGroup.account,
      protocol: ProviderProtocol.codex, needsKey: false,
    ),
    ProviderPreset(
      id: 'opencode-zen', name: 'OpenCode Zen',
      group: ProviderPresetGroup.gateway,
      protocol: ProviderProtocol.openaiResponses,
      baseUrl: 'https://opencode.ai/zen/v1',
      credentialsUrl: 'https://opencode.ai/auth',
      models: [
        ProviderModel(id: 'gpt-5.6-sol'),
        ProviderModel(id: 'gpt-5.6-terra'),
      ],
    ),
    ProviderPreset(
      id: 'opencode-go', name: 'OpenCode Go',
      group: ProviderPresetGroup.gateway,
      protocol: ProviderProtocol.openaiChat,
      baseUrl: 'https://opencode.ai/zen/go/v1',
      credentialsUrl: 'https://opencode.ai/auth',
      models: [
        ProviderModel(id: 'kimi-k3'),
        ProviderModel(id: 'gpt-5.6-luna',
          protocol: ProviderProtocol.openaiResponses),
        ProviderModel(id: 'minimax-m3',
          protocol: ProviderProtocol.anthropic),
      ],
    ),
    ProviderPreset(
      id: 'openrouter', name: 'OpenRouter',
      group: ProviderPresetGroup.gateway,
      protocol: ProviderProtocol.openaiChat,
      baseUrl: 'https://openrouter.ai/api/v1',
      credentialsUrl: 'https://openrouter.ai/settings/keys',
    ),
    ProviderPreset(
      id: 'openai-api', name: 'OpenAI API',
      group: ProviderPresetGroup.api,
      protocol: ProviderProtocol.openaiResponses,
      baseUrl: 'https://api.openai.com/v1',
      credentialsUrl: 'https://platform.openai.com/api-keys',
    ),
    ProviderPreset(
      id: 'anthropic-api', name: 'Anthropic API',
      group: ProviderPresetGroup.api,
      protocol: ProviderProtocol.anthropic,
      baseUrl: 'https://api.anthropic.com',
      credentialsUrl: 'https://console.anthropic.com/settings/keys',
    ),
    ProviderPreset(
      id: 'gemini-api', name: 'Google Gemini API',
      group: ProviderPresetGroup.api,
      protocol: ProviderProtocol.openaiChat,
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      credentialsUrl: 'https://aistudio.google.com/apikey',
      models: [ProviderModel(id: 'gemini-3.8-flash')],
    ),
    ProviderPreset(
      id: 'deepseek-api', name: 'DeepSeek API',
      group: ProviderPresetGroup.api,
      protocol: ProviderProtocol.openaiChat,
      baseUrl: 'https://api.deepseek.com',
      credentialsUrl: 'https://platform.deepseek.com/api_keys',
      models: [
        ProviderModel(id: 'deepseek-flash'),
        ProviderModel(id: 'deepseek-v4-pro'),
      ],
    ),
    ProviderPreset(
      id: 'moonshot-api', name: 'Moonshot / Kimi API',
      group: ProviderPresetGroup.api,
      protocol: ProviderProtocol.openaiChat,
      baseUrl: 'https://api.moonshot.ai/v1',
      credentialsUrl: 'https://platform.moonshot.ai/console/api-keys',
    ),
    ProviderPreset(
      id: 'mistral-api', name: 'Mistral API',
      group: ProviderPresetGroup.api,
      protocol: ProviderProtocol.openaiChat,
      baseUrl: 'https://api.mistral.ai/v1',
      credentialsUrl: 'https://console.mistral.ai/api-keys',
    ),
    ProviderPreset(
      id: 'groq-api', name: 'Groq API',
      group: ProviderPresetGroup.api,
      protocol: ProviderProtocol.openaiChat,
      baseUrl: 'https://api.groq.com/openai/v1',
      credentialsUrl: 'https://console.groq.com/keys',
      models: [ProviderModel(id: 'openai/gpt-oss-20b')],
    ),
    ProviderPreset(
      id: 'cerebras-api', name: 'Cerebras API',
      group: ProviderPresetGroup.api,
      protocol: ProviderProtocol.openaiChat,
      baseUrl: 'https://api.cerebras.ai/v1',
      credentialsUrl: 'https://cloud.cerebras.ai/',
    ),
    ProviderPreset(
      id: 'xai-api', name: 'xAI / Grok API',
      group: ProviderPresetGroup.api,
      protocol: ProviderProtocol.openaiChat,
      baseUrl: 'https://api.x.ai/v1',
      credentialsUrl: 'https://console.x.ai/',
    ),
    ProviderPreset(
      id: 'together-api', name: 'Together AI',
      group: ProviderPresetGroup.api,
      protocol: ProviderProtocol.openaiChat,
      baseUrl: 'https://api.together.xyz/v1',
      credentialsUrl: 'https://api.together.ai/settings/api-keys',
    ),
    ProviderPreset(
      id: 'fireworks-api', name: 'Fireworks AI',
      group: ProviderPresetGroup.api,
      protocol: ProviderProtocol.openaiChat,
      baseUrl: 'https://api.fireworks.ai/inference/v1',
      credentialsUrl: 'https://fireworks.ai/account/api-keys',
    ),
    ProviderPreset(
      id: 'ollama-local', name: 'Ollama (local)',
      group: ProviderPresetGroup.local,
      protocol: ProviderProtocol.openaiChat,
      baseUrl: 'http://localhost:11434/v1', needsKey: false,
    ),
    ProviderPreset(
      id: 'lmstudio-local', name: 'LM Studio (local)',
      group: ProviderPresetGroup.local,
      protocol: ProviderProtocol.openaiChat,
      baseUrl: 'http://localhost:1234/v1', needsKey: false,
    ),
    ProviderPreset(
      id: 'vllm-local', name: 'vLLM (local)',
      group: ProviderPresetGroup.local,
      protocol: ProviderProtocol.openaiChat,
      baseUrl: 'http://localhost:8000/v1', needsKey: false,
    ),
  ];
}
