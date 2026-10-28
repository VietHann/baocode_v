import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/native_account_upstreams.dart';
import 'package:baocode/models/proxy/model_proxy.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:baocode/models/qoder_direct.dart';
import 'package:baocode/models/qoder_direct_oauth.dart';

void main() {
  test('Signed Qoder Upstream supports Claude model request via native COSY '
      'and embedded proxy without a Qoder CLI or 9Router', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seen = <Map<String, String?>>[];
    upstream.listen((request) async {
      try {
        final body = await utf8.decodeStream(request);
        seen.add({
          'path': request.uri.path,
          'auth': request.headers.value('authorization'),
          'model': request.headers.value('x-model-key'),
          'sigPath': request.headers.value('cosy-sigpath'),
          'body': body,
        });
        if (request.method == 'GET') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'chat': [
              {
                'key': 'qmodel', 'display_name': 'Qoder live model',
                'enable': true, 'source': 'system',
                'max_output_tokens': 400,
              }
            ],
          }));
        } else {
          request.response.headers.contentType =
              ContentType('text', 'event-stream');
          request.response.write('data: ' + jsonEncode({
            'statusCodeValue': 200,
            'body': jsonEncode({
              'id': 'chatcmpl-1',
              'choices': [
                {'index': 0, 'delta': {'content': 'Qoder native works.'},
                 'finish_reason': 'stop'}
              ],
            }),
          }) + '\n\n');
          request.response.write('data: [DONE]\n\n');
        }
      } finally {
        await request.response.close();
      }
    });
    final secrets = MemorySecretStore();
    const account = QoderAccount(
      token: 'dt-mocked', userId: 'test-user',
      machineId: 'test-machine', email: 'test@example.com',
    );
    await QoderDirectOAuth().save(account, secrets: secrets);
    final client = _DirectHttp().createHttpClient(null);
    final qoder = QoderDirect(
      modelsEndpoint:
          Uri.parse('http://127.0.0.1:${upstream.port}/model/list'),
      chatEndpoint:
          Uri.parse('http://127.0.0.1:${upstream.port}/chat?Encode=1'),
      client: client,
    );
    final providers = ModelProviders.memory(secrets: secrets);
    final catalog = await qoder.models(account);
    await NativeAccountUpstreams.upsertQoderModels(
      providers, account, catalog,
    );
    expect(providers.resolve(modelRef(nativeQoderProviderId, 'qmodel')),
        isNotNull);
    final proxy = ModelProxy(
      provider: providers.provider,
      key: providers.key,
      qoder: qoder,
      qoderOAuth: QoderDirectOAuth(),
      copilotSecrets: secrets,
      token: 'proxy-passphrase',
    );
    final caller = _DirectHttp().createHttpClient(null);
    try {
      final endpoint = await proxy.endpoint(nativeQoderProviderId);
      final request = await caller.postUrl(
        Uri.parse('${endpoint.baseUrl}/v1/messages'),
      );
      request.headers.set('authorization', 'Bearer proxy-passphrase');
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode({
        'model': 'qmodel',
        'max_tokens': 30,
        'stream': false,
        'messages': [
          {'role': 'user', 'content': 'Hi'},
        ],
      })));
      final response = await request.close();
      final text = await utf8.decodeStream(response);
      expect(response.statusCode, 200, reason: text);
      final answer = jsonDecode(text);
      expect((answer['content'] as List).first['text'],
          'Qoder native works.');
      expect(seen.where((m) => m['path'] == '/model/list'), hasLength(1));
      final calls = seen.where((m) => m['path'] == '/chat').toList();
      expect(calls, hasLength(1));
      expect(calls.single['model'], 'qmodel');
      expect(calls.single['auth'], startsWith('Bearer COSY.'));
      expect(calls.single['sigPath'], '/chat');
    } finally {
      caller.close(force: true);
      client.close(force: true);
      await proxy.close();
      await upstream.close(force: true);
    }
  });
}
class _DirectHttp extends HttpOverrides {}
