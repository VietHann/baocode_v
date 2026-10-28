import 'dart:convert';
import 'dart:io';

import 'package:baocode/models/qoder_direct_oauth.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:test/test.dart';

void main() {
  test('Qoder device URL has PKCE, random nonce and machine ID', () {
    final login = QoderDirectOAuth().begin();
    expect(login.url.host, 'qoder.com');
    expect(login.url.path, '/device/selectAccounts');
    expect(login.url.queryParameters['challenge_method'], 'S256');
    expect(login.url.queryParameters['challenge'], isNotEmpty);
    expect(login.nonce, isNotEmpty);
    expect(login.machineId, isNotEmpty);
    expect(login.nonce, isNot(login.machineId));
  });

  test('Direct OAuth polls Qoder provider and stores its account in keychain',
      () async {
    final mock = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var polls = 0;
    String? expectedNonce;
    String? expectedVerifier;
    mock.listen((request) async {
      if (request.uri.path == '/poll') {
        polls++;
        expectedNonce = request.uri.queryParameters['nonce'];
        expectedVerifier = request.uri.queryParameters['verifier'];
        request.response.headers.contentType = ContentType.json;
        if (polls < 2) {
          request.response.statusCode = HttpStatus.accepted;
        } else {
          request.response.write(jsonEncode({
            'token': 'dt-verified',
            'user_id': 'user-42',
            'refresh_token': 'refresh-123',
            'expires_in': 3600,
          }));
        }
      } else if (request.uri.path == '/userinfo') {
        expect(request.headers.value('authorization'),
            'Bearer dt-verified');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
            '{"name":"Test Qoder","email":"test@example.com"}');
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });

    try {
      final oauth = QoderDirectOAuth(
        loginUri: Uri.parse('http://127.0.0.1:' +
            mock.port.toString() + '/login'),
        pollUri: Uri.parse('http://127.0.0.1:' +
            mock.port.toString() + '/poll'),
        userInfoUri: Uri.parse('http://127.0.0.1:' +
            mock.port.toString() + '/userinfo'),
        interval: const Duration(milliseconds: 1),
        timeout: const Duration(seconds: 5),
      );
      final login = oauth.begin();
      login.start();
      final account = await login.result;
      expect(polls, 2);
      expect(expectedNonce, login.nonce);
      expect(expectedVerifier, isNotEmpty);
      expect(account.token, 'dt-verified');
      expect(account.userId, 'user-42');
      expect(account.machineId, login.machineId);
      expect(account.email, 'test@example.com');
      final keychain = MemorySecretStore();
      await oauth.save(account, secrets: keychain);
      expect((await oauth.saved(secrets: keychain))?.token, 'dt-verified');
      await oauth.signOut(secrets: keychain);
      expect(await oauth.saved(secrets: keychain), isNull);
    } finally {
      await mock.close(force: true);
    }
  });

  test('Qoder request cancellation completes pending login', () async {
    final mock = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    mock.listen((request) async {
      request.response.statusCode = 202;
      await request.response.close();
    });
    try {
      final oauth = QoderDirectOAuth(
        pollUri: Uri.parse('http://127.0.0.1:' +
            mock.port.toString() + '/poll'),
        interval: const Duration(seconds: 10),
      );
      final login = oauth.begin();
      final pending = expectLater(
          login.result, throwsA(isA<QoderAuthCancelled>()));
      login.start();
      await login.cancel();
      await pending;
    } finally {
      await mock.close(force: true);
    }
  });
}
