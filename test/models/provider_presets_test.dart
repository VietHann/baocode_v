import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/provider_presets.dart';
import 'package:baocode/models/upstream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preset ids and names are unique', () {
    final presets = ProviderPreset.all;
    expect({for (final preset in presets) preset.id}.length, presets.length);
    expect({for (final preset in presets) preset.name}.length, presets.length);
    expect(presets.length, greaterThanOrEqualTo(15));
  });

  test('API-key presets use documented HTTPS endpoints', () {
    for (final preset in ProviderPreset.all) {
      if (!preset.needsKey) continue;
      final uri = Uri.parse(preset.baseUrl);
      expect(uri.scheme, 'https', reason: preset.id);
      expect(uri.host, isNotEmpty, reason: preset.id);
      expect(Uri.parse(preset.credentialsUrl!).scheme, 'https');
    }
  });

  test('ChatGPT uses existing account login without API key', () {
    final preset = ProviderPreset.byId('chatgpt-codex')!;
    final provider = preset.create('chatgpt');
    expect(preset.needsKey, false);
    expect(provider.protocol, ProviderProtocol.codex);
    expect(provider.protocol.usesAccounts, true);
    expect(provider.baseUrl, isEmpty);
  });

  test('OpenCode Go models route to three distinct APIs', () {
    final provider = ProviderPreset.byId('opencode-go')!.create('go');
    expect(provider.protocolOf(provider.model('kimi-k3')!),
        ProviderProtocol.openaiChat);
    expect(provider.protocolOf(provider.model('gpt-5.6-luna')!),
        ProviderProtocol.openaiResponses);
    expect(provider.protocolOf(provider.model('minimax-m3')!),
        ProviderProtocol.anthropic);
    expect(
      UpstreamUrls.conversation(provider.speakingFor('gpt-5.6-luna'))
          .toString(),
      'https://opencode.ai/zen/go/v1/responses',
    );
    expect(
      UpstreamUrls.anthropicBase(provider.baseUrl),
      'https://opencode.ai/zen/go',
    );
  });

  test('Gemini compatible endpoint retains the v1beta path', () {
    final provider = ProviderPreset.byId('gemini-api')!.create('gemini');
    expect(
      UpstreamUrls.conversation(provider).toString(),
      'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
    );
    expect(
      UpstreamUrls.models(provider).single.toString(),
      'https://generativelanguage.googleapis.com/v1beta/openai/models',
    );
  });

  test('model-level protocols survive serialization', () {
    for (final preset in ProviderPreset.all) {
      final original = preset.create(preset.id);
      final restored = ModelProvider.fromJson(original.toJson());
      expect(restored, isNotNull, reason: preset.id);
      expect(restored!.protocol, original.protocol);
      expect(restored.baseUrl, original.baseUrl);
      expect(
        restored.models.map((model) => model.protocol).toList(),
        original.models.map((model) => model.protocol).toList(),
      );
    }
  });

  test('adding presets never replaces an existing upstream', () async {
    final providers = ModelProviders.memory();
    await providers.save(
      const ModelProvider(id: 'my-provider', name: 'My provider'),
    );
    for (final preset in ProviderPreset.all) {
      await providers.save(preset.create(providers.newId(preset.name)));
    }
    expect(providers.provider('my-provider')?.name, 'My provider');
    expect(providers.providers.length, ProviderPreset.all.length + 1);
    providers.dispose();
  });
}
