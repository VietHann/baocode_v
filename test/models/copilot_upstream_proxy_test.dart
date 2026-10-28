import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/models/copilot_direct.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/native_account_upstreams.dart';
import 'package:baocode/models/proxy/model_proxy.dart';
import 'package:baocode/models/secret_store.dart';

void main() {
  test('Signed-in Copilot Upstream forwards Claude messages to Copilot '
       'with a refreshed account credential (without CLI or 9Router)',
      () async {
    final mock = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seen = <Map<String, dynamic>>[];
    mock.listen((request) async {
      expect(request.uri.path, '/chat');
      expect(request.headers.value('authorization'),
          'Bearer fresh-copilot-model-token');
      final body = jsonDecode(await utf8.decodeStream(request)) as Map<String, dynamic>;
      seen.add(body);
      expect(body['model'], 'copilot-model-from-server');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'id': 'chatcmpl-1',
        'object': 'chat.completion',
        'created': 1700000000,
        'model': 'copilot-model-from-server',
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': 'It works through VietCode Upstreams.',
            },
            'finish_reason': 'stop',
          }
        ],
        'usage': {
          'prompt_tokens': 4,
          'completion_tokens': 8,
          'total_tokens': 12,
        },
      }));
      await request.response.close();
    });

    final nativeClient = _RealHttpOverrides().createHttpClient(null);
    final secrets = MemorySecretStore();
    final oauth = CopilotDirect(
      completionEndpoint: Uri.parse('http://127.0.0.1:' +
          mock.port.toString() + '/chat'),
    );
    await oauth.save(CopilotAccount(
      githubToken: 'github-oauth-token',
      copilotToken: 'fresh-copilot-model-token',
      copilotExpiry: DateTime.now().add(const Duration(hours: 1)),
      login: 'dev-account',
    ), secrets: secrets);
    final providers = ModelProviders.memory(secrets: secrets);
    final saved = await NativeAccountUpstreams.upsertCopilot(
      providers,
      (await oauth.saved(secrets: secrets))!,
      ['copilot-model-from-server'],
    );
    expect(saved.enabledModels.single.id, 'copilot-model-from-server');

    final proxy = ModelProxy(
      provider: providers.provider,
      key: providers.key,
      copilot: oauth,
      copilotSecrets: secrets,
      upstreamClient: nativeClient,
      token: 'local-proxy-access',
    );
    final requesting = _RealHttpOverrides().createHttpClient(null);
    try {
      final endpoint = await proxy.endpoint(nativeCopilotProviderId);
      final uri = Uri.parse(endpoint.baseUrl + '/v1/messages');
      final req = await requesting.postUrl(uri);
      req.headers.set('authorization', 'Bearer local-proxy-access');
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({
        'model': 'copilot-model-from-server',
        'messages': [
          {'role': 'user', 'content': 'Hello VietCode'}
        ],
        'max_tokens': 50,
        'stream': false,
      })));
      final res = await req.close();
      final body = jsonDecode(await utf8.decodeStream(res)) as Map;
      expect(res.statusCode, 200);
      expect((body['content'] as List).first['text'],
          contains('It works through VietCode Upstreams'));
      expect(seen, hasLength(1));
      expect(seen.single['model'], 'copilot-model-from-server');
    } finally {
      requesting.close(force: true);
      await proxy.close();
      await mock.close(force: true);
    }
  });
}

class _RealHttpOverrides extends HttpOverrides {}
