import 'model_provider.dart';
import 'model_providers.dart';
import 'copilot_direct.dart';
import 'qoder_direct_oauth.dart';
import 'qoder_direct.dart';

/// Distinct built-in OAuth upstreams, not CLI gateways or manually entered
/// API keys. A provider is only selectable after its real model catalog has
/// been obtained from the corresponding signed-in account.
const nativeCopilotProviderId = 'vietcode-copilot-oauth';
const nativeQoderProviderId = 'vietcode-qoder-oauth';

bool isNativeCopilot(ModelProvider provider) =>
    provider.id == nativeCopilotProviderId;

bool isNativeQoder(ModelProvider provider) =>
    provider.id == nativeQoderProviderId;

abstract final class NativeAccountUpstreams {
  /// Store real model IDs, preserving enable state and custom model
  /// preferences on refresh. No model IDs are guessed or seeded.
  static Future<ModelProvider> upsertCopilot(
    ModelProviders store,
    CopilotAccount account,
    List<String> available,
  ) async {
    final ids = available.where((id) => id.trim().isNotEmpty).toSet().toList()
      ..sort();
    if (ids.isEmpty) {
      throw const CopilotDirectException(
        'Copilot did not return any usable models. '
        'An account login alone does not grant model access.',
      );
    }
    final existing = store.provider(nativeCopilotProviderId);
    final old = {
      if (existing != null)
        for (final model in existing.models) model.id: model,
    };
    final provider = ModelProvider(
      id: nativeCopilotProviderId,
      name: existing?.name ?? 'GitHub Copilot',
      protocol: ProviderProtocol.openaiChat,
      baseUrl: 'https://api.githubcopilot.com',
      enabled: existing?.enabled ?? true,
      disableNonessentialTraffic: true,
      promptCacheKey: false,
      preserveThinking: false,
      models: [
        for (final id in ids)
          old[id]?.copyWith(missing: false) ??
              ProviderModel(id: id, enabled: true),
      ],
      accounts: [
        ProviderAccount(
          id: account.login.isNotEmpty ? account.login : 'github-copilot',
          email: account.login.isNotEmpty ? account.login : null,
        ),
      ],
      roles: existing?.roles ?? const ProviderRoles(),
      balance: existing?.balance ?? AccountBalance.roundRobin,
      icon: existing?.icon,
    );
    await store.save(provider);
    return provider;
  }

  /// Show a successfully authorized GitHub account even if its model
  /// catalog is unavailable (network error, expired subscription, etc.).
  /// The upstream remains INCOMPLETE until real model IDs are fetched; no
  /// fake default model is added to the global picker.
  static Future<ModelProvider> upsertCopilotAccountOnly(
    ModelProviders store,
    CopilotAccount account,
  ) async {
    final existing = store.provider(nativeCopilotProviderId);
    final provider = ModelProvider(
      id: nativeCopilotProviderId,
      name: existing?.name ?? 'GitHub Copilot',
      protocol: ProviderProtocol.openaiChat,
      baseUrl: 'https://api.githubcopilot.com',
      enabled: existing?.enabled ?? true,
      disableNonessentialTraffic: true,
      promptCacheKey: false,
      models: existing?.models ?? const [],
      accounts: [
        ProviderAccount(
          id: account.login.isNotEmpty ? account.login : 'github-copilot',
          email: account.login.isNotEmpty ? account.login : null,
        ),
      ],
      roles: existing?.roles ?? const ProviderRoles(),
      icon: existing?.icon,
    );
    await store.save(provider);
    return provider;
  }

  /// A signed Qoder account with a live catalog (not static guesses).
  /// Refreshing preserves the user's model enablement selection.
  static Future<ModelProvider> upsertQoderModels(
    ModelProviders store,
    QoderAccount account,
    List<QoderRemoteModel> models,
  ) async {
    if (models.isEmpty) {
      throw const QoderInferenceException(
        'Qoder did not return any enabled models for this account.',
      );
    }
    final existing = store.provider(nativeQoderProviderId);
    final previous = <String, ProviderModel>{
      if (existing != null)
        for (final m in existing.models) m.id: m,
    };
    final provider = ModelProvider(
      id: nativeQoderProviderId,
      name: 'Qoder',
      protocol: ProviderProtocol.openaiChat,
      baseUrl: 'https://api3.qoder.sh',
      enabled: true,
      disableNonessentialTraffic: true,
      promptCacheKey: false,
      models: [
        for (final remote in models)
          ProviderModel(
            id: remote.id,
            label: remote.name,
            contextWindow: remote.contextWindow,
            images: remote.images,
            enabled: previous[remote.id]?.enabled ?? true,
          ),
      ],
      accounts: [
        ProviderAccount(
          id: account.userId,
          email: account.email.isNotEmpty ? account.email : null,
        ),
      ],
      roles: existing?.roles ?? const ProviderRoles(),
      icon: existing?.icon,
    );
    await store.save(provider);
    return provider;
  }

  /// Qoder's device OAuth succeeded. Show the account even when catalog
  /// fetching is offline, denied by the provider, or out of quota.
  /// Only upsertQoderModels may make real models selectable.
  static Future<ModelProvider> upsertQoder(
    ModelProviders store, QoderAccount account,
  ) async {
    final existing = store.provider(nativeQoderProviderId);
    final provider = ModelProvider(
      id: nativeQoderProviderId,
      name: 'Qoder',
      protocol: ProviderProtocol.openaiChat,
      enabled: false,
      baseUrl: '',
      models: const [],
      accounts: [
        ProviderAccount(
          id: account.userId,
          email: account.email.isNotEmpty ? account.email : null,
        ),
      ],
      disableNonessentialTraffic: true,
      promptCacheKey: false,
    );
    await store.save(provider);
    return provider;
  }
}
