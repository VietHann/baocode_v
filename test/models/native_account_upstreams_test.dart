import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/models/copilot_direct.dart';
import 'package:baocode/models/qoder_direct_oauth.dart';
import 'package:baocode/models/native_account_upstreams.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';

void main() {
  test('Copilot OAuth account appears in Upstreams with real model IDs', () async {
    final store = ModelProviders.memory();
    const account = CopilotAccount(
      githubToken: 'fake-gh',
      login: 'github-user',
    );
    final upstream = await NativeAccountUpstreams.upsertCopilot(
      store, account, ['model-z', 'model-a', 'model-z'],
    );
    expect(upstream.id, nativeCopilotProviderId);
    expect(upstream.accounts.single.displayName, 'github-user');
    expect(upstream.models.map((m) => m.id), ['model-a', 'model-z']);
    expect(upstream.enabledModels.length, 2);
    expect(upstream.connected, isTrue);
    expect(store.enabled.any((p) => p.id == nativeCopilotProviderId), isTrue);
    expect(store.resolve(modelRef(nativeCopilotProviderId, 'model-a')), isNotNull);

    // The user unchecks a model in Settings; a catalog refresh must not
    // re-enable it or reintroduce models that are no longer available.
    await store.save(upstream.withModel(
      upstream.models.first.copyWith(enabled: false),
    ));
    final refreshed = await NativeAccountUpstreams.upsertCopilot(
      store, account, ['model-a', 'model-new'],
    );
    expect(refreshed.model('model-a')?.enabled, isFalse);
    expect(refreshed.model('model-new')?.enabled, isTrue);
    expect(refreshed.model('model-z'), isNull);
    expect(refreshed.accounts, hasLength(1));
  });

  test('No fabricated Copilot model if OAuth gave zero accessible models',
      () async {
    final store = ModelProviders.memory();
    await expectLater(
      NativeAccountUpstreams.upsertCopilot(
        store,
        const CopilotAccount(githubToken: 'test'),
        const [],
      ),
      throwsA(isA<CopilotDirectException>()),
    );
    expect(store.providers, isEmpty);
  });

  test('Qoder OAuth account appears in Upstreams but cannot be selected',
      () async {
    final store = ModelProviders.memory();
    const account = QoderAccount(
      token: 'test-token',
      machineId: 'machine',
      userId: 'qoder-user',
      email: 'test@example.com',
    );
    final upstream = await NativeAccountUpstreams.upsertQoder(store, account);
    expect(upstream.accounts.single.email, account.email);
    expect(upstream.models, isEmpty);
    expect(upstream.enabled, isFalse);
    expect(upstream.connected, isFalse);
    expect(store.enabled.where((p) => p.id == nativeQoderProviderId), isEmpty);
    expect(store.provider(nativeQoderProviderId), isNotNull);
  });
}
