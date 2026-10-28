import 'dart:convert';
import 'dart:io';

import 'package:baocode/models/oauth_pkce.dart';
import 'package:baocode/models/openrouter_oauth.dart';
import 'package:test/test.dart';

void main() {
  test('OAuth authorization is state-bound and uses S256 PKCE', () {
    const callback = 'http://127.0.0.1:49101/oauth/callback';
    final uri = OpenRouterOAuth.authorizeUrl(
      callback: Uri.parse(callback),
      challenge: OAuthPkce.challengeOf('verifier'),
      state: 'random-state',
    );
    expect(uri.scheme, 'https');
    expect(uri.host, 'openrouter.ai');
    expect(uri.path, '/auth');
    expect(uri.queryParameters['callback_url'], callback);
    expect(uri.queryParameters['code_challenge_method'], 'S256');
    expect(uri.queryParameters['code_challenge'], isNotEmpty);
    expect(uri.queryParameters['state'], 'random-state');
  });

  test('token exchange sends verifier and parses credential', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, dynamic>? posted;
    server.listen((request) async {
      posted = jsonDecode(await utf8.decodeStream(request))
          as Map<String, dynamic>;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"key":"test-key","user_id":"usr_1"}');
      await request.response.close();
    });
    try {
      final url = Uri.parse(
        'http://127.0.0.1:' + server.port.toString() + '/api/v1/auth/keys',
      );
      final value = await OpenRouterOAuth.exchange(
        code: 'test-code', verifier: 'local-verifier', endpoint: url,
      );
      expect(value, 'test-key');
      expect(posted, {
        'code': 'test-code',
        'code_verifier': 'local-verifier',
        'code_challenge_method': 'S256',
      });
    } finally {
      await server.close(force: true);
    }
  });

  test('wrong OAuth state is rejected without ending valid login', () async {
    final tokenServer =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    tokenServer.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"key":"authorized-key"}');
      await request.response.close();
    });
    final login = await OpenRouterOAuth.begin(
      tokenEndpoint: Uri.parse(
        'http://127.0.0.1:' + tokenServer.port.toString()
            + '/api/v1/auth/keys',
      ),
      timeout: const Duration(seconds: 10),
    );
    final browser = HttpClient();
    try {
      final callback =
          Uri.parse(login.url.queryParameters['callback_url']!);
      final invalid = callback.replace(queryParameters: {
        'state': 'wrong-state', 'code': 'bad-code',
      });
      final rejected = await (await browser.getUrl(invalid)).close();
      expect(rejected.statusCode, HttpStatus.forbidden);
      await rejected.drain<void>();

      final valid = callback.replace(queryParameters: {
        'state': login.url.queryParameters['state']!,
        'code': 'good-code',
      });
      final accepted = await (await browser.getUrl(valid)).close();
      expect(accepted.statusCode, HttpStatus.ok);
      await accepted.drain<void>();
      expect(await login.result, 'authorized-key');
    } finally {
      browser.close(force: true);
      await login.cancel();
      await tokenServer.close(force: true);
    }
  });

  test('cancellation ends pending OAuth login', () async {
    final login =
        await OpenRouterOAuth.begin(timeout: const Duration(seconds: 20));
    final failed = expectLater(
      login.result,
      throwsA(isA<OpenRouterAuthCancelled>()),
    );
    await login.cancel();
    await failed;
  });
}
