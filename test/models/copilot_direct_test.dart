import 'dart:convert';
import 'dart:io';

import 'package:baocode/models/copilot_direct.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:test/test.dart';

void main() {
  test('GitHub Copilot browser device OAuth leads to direct model calls',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seenPaths = <String>[];
    server.listen((req) async {
      seenPaths.add(req.uri.path);
      req.response.headers.contentType = ContentType.json;
      switch (req.uri.path) {
        case '/device':
          final body = await utf8.decodeStream(req);
          expect(body, contains('client_id='));
          req.response.write(jsonEncode({
            'device_code': 'device-secret',
            'user_code': 'ABCD-EFGH',
            'verification_uri': 'https://github.com/login/device',
            'interval': 1,
            'expires_in': 30,
          }));
        case '/token':
          final body = await utf8.decodeStream(req);
          expect(body, contains('device_code=device-secret'));
          req.response.write('{"access_token":"ghu-oauth-token"}');
        case '/user':
          expect(req.headers.value('authorization'),
              'Bearer ghu-oauth-token');
          req.response.write('{"login":"test-vietcode"}');
        case '/copilot-token':
          expect(req.headers.value('authorization'),
              'Bearer ghu-oauth-token');
          req.response.write(jsonEncode({
            'token': 'copilot-model-credential',
            'expires_at': DateTime.now().add(
              const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
          }));
        case '/models':
          expect(req.headers.value('authorization'),
              'Bearer copilot-model-credential');
          req.response.write('{"data":[{"id":"gpt-5-mini"}]}');
        case '/chat':
          expect(req.headers.value('authorization'),
              'Bearer copilot-model-credential');
          final body = jsonDecode(await utf8.decodeStream(req));
          expect(body['model'], 'gpt-5-mini');
          expect(body['messages'][0]['content'], 'Hello');
          req.response.write(jsonEncode({
            'choices': [
              {'message': {'role': 'assistant', 'content': 'Hello from model'}}
            ],
          }));
        default:
          req.response.statusCode = 404;
          req.response.write('{}');
      }
      await req.response.close();
    });
    try {
      Uri loc(String path) => Uri.parse('http://127.0.0.1:' +
          server.port.toString() + path);
      final provider = CopilotDirect(
        deviceEndpoint: loc('/device'),
        tokenEndpoint: loc('/token'),
        copilotTokenEndpoint: loc('/copilot-token'),
        modelsEndpoint: loc('/models'),
        completionEndpoint: loc('/chat'),
        profileEndpoint: loc('/user'),
      );
      final login = await provider.begin();
      expect(login.userCode, 'ABCD-EFGH');
      expect(login.url.host, 'github.com');
      login.start();
      final account = await login.result;
      expect(account.githubToken, 'ghu-oauth-token');
      expect(account.login, 'test-vietcode');

      final store = MemorySecretStore();
      final authorized = await provider.ensureToken(
          account, secrets: store);
      expect(authorized.copilotToken, 'copilot-model-credential');
      expect((await provider.saved(secrets: store))?.githubToken,
          account.githubToken);
      final models = await provider.models(authorized, secrets: store);
      expect(models, contains('gpt-5-mini'));
      final reply = await provider.complete(authorized,
        model: 'gpt-5-mini',
        messages: [{'role': 'user', 'content': 'Hello'}],
        secrets: store,
      );
      expect(reply, 'Hello from model');
      expect(seenPaths, containsAll([
        '/device', '/token', '/user', '/copilot-token', '/models', '/chat',
      ]));
      await provider.signOut(secrets: store);
      expect(await provider.saved(secrets: store), isNull);
    } finally {
      await server.close(force: true);
    }
  });

  test('GitHub token endpoint does not accept unencrypted external HTTP',
      () {
    expect(
      () => CopilotDirect(tokenEndpoint:
          Uri.parse('http://remote-provider.example.com/token')),
      throwsA(isA<CopilotDirectException>()),
    );
  });

  test('Rejects OAuth device verification pages outside github.com',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'device_code': 'device-1',
        'user_code': '1234',
        'verification_uri': 'https://github-attacker.example/login/device',
      }));
      await request.response.close();
    });
    try {
      final provider = CopilotDirect(
        deviceEndpoint: Uri.parse(
          'http://127.0.0.1:' + server.port.toString() + '/device',
        ),
      );
      await expectLater(
        provider.begin(), throwsA(isA<CopilotDirectException>()),
      );
    } finally {
      await server.close(force: true);
    }
  });

  test('OAuth token expiry information is retained in encrypted storage',
      () async {
    final store = MemorySecretStore();
    final provider = CopilotDirect();
    final expiry = DateTime.utc(2030, 1, 1);
    await provider.save(CopilotAccount(
      githubToken: 'test-secret',
      copilotToken: 'short-lived',
      copilotExpiry: expiry,
      login: 'user',
    ), secrets: store);
    final account = await provider.saved(secrets: store);
    expect(account?.githubToken, 'test-secret');
    expect(account?.copilotToken, 'short-lived');
    expect(account?.copilotExpiry, expiry);
    await provider.signOut(secrets: store);
    expect(await provider.saved(secrets: store), isNull);
  });

}
