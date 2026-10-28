/// OpenRouter OAuth PKCE: browser authorization, loopback callback, and
/// official code exchange. Only the caller saves the returned credential.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'oauth_pkce.dart';

class OpenRouterAuthException implements Exception {
  const OpenRouterAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class OpenRouterAuthCancelled extends OpenRouterAuthException {
  const OpenRouterAuthCancelled() : super('Sign-in cancelled.');
}

abstract final class OpenRouterOAuth {
  static final Uri exchangeEndpoint =
      Uri.parse('https://openrouter.ai/api/v1/auth/keys');

  static Uri authorizeUrl({
    required Uri callback,
    required String challenge,
    required String state,
  }) => Uri.https('openrouter.ai', '/auth', {
    'callback_url': callback.toString(),
    'code_challenge': challenge,
    'code_challenge_method': 'S256',
    'state': state,
    'key_label': 'VietCode',
  });

  static Future<OpenRouterLogin> begin({
    Duration timeout = const Duration(minutes: 10),
    Uri? tokenEndpoint,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final pkce = OAuthPkce.generate();
    final state = oauthRandomState();
    final port = server.port;
    final callback = Uri.parse('http://127.0.0.1:$port/oauth/callback');
    final login = OpenRouterLogin._(
      server: server,
      verifier: pkce.verifier,
      state: state,
      tokenEndpoint: tokenEndpoint ?? exchangeEndpoint,
      url: authorizeUrl(
        callback: callback,
        challenge: pkce.challenge,
        state: state,
      ),
      timeout: timeout,
    );
    login._listen();
    return login;
  }

  /// Official POST /api/v1/auth/keys, without an app/client secret.
  /// The injectable endpoint exists only for local unit tests.
  static Future<String> exchange({
    required String code,
    required String verifier,
    Uri? endpoint,
    HttpClient? client,
  }) async {
    final uri = endpoint ?? exchangeEndpoint;
    if (uri.scheme != 'https' &&
        !(uri.scheme == 'http' && uri.host == '127.0.0.1')) {
      throw const OpenRouterAuthException('Invalid OAuth token endpoint.');
    }
    final owned = client == null;
    final http = client ?? HttpClient();
    try {
      final request = await http.postUrl(uri).timeout(
        const Duration(seconds: 15),
      );
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode({
        'code': code,
        'code_verifier': verifier,
        'code_challenge_method': 'S256',
      })));
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != HttpStatus.ok) {
        final status = response.statusCode;
        await response.drain<void>();
        throw OpenRouterAuthException(
          'OpenRouter sign-in failed (HTTP $status).',
        );
      }
      final body = await utf8.decodeStream(response);
      final Object? decoded;
      try {
        decoded = jsonDecode(body);
      } on FormatException {
        throw const OpenRouterAuthException(
          'OpenRouter returned an invalid authorization response.',
        );
      }
      final key = decoded is Map ? decoded['key'] : null;
      if (key is! String || key.isEmpty || key.length > 4096) {
        throw const OpenRouterAuthException(
          'OpenRouter did not return an account credential.',
        );
      }
      return key;
    } on SocketException {
      throw const OpenRouterAuthException('Cannot reach OpenRouter.');
    } on TimeoutException {
      throw const OpenRouterAuthException('OpenRouter did not respond in time.');
    } finally {
      if (owned) http.close(force: true);
    }
  }
}

class OpenRouterLogin {
  OpenRouterLogin._({
    required HttpServer server,
    required String verifier,
    required String state,
    required Uri tokenEndpoint,
    required this.url,
    required Duration timeout,
  }) : _server = server,
       _verifier = verifier,
       _state = state,
       _tokenEndpoint = tokenEndpoint,
       _timeout = timeout;

  final HttpServer _server;
  final String _verifier;
  final String _state;
  final Uri _tokenEndpoint;
  final Duration _timeout;

  final Uri url;
  final Completer<String> _completed = Completer<String>();
  StreamSubscription<HttpRequest>? _subscription;
  Timer? _timer;
  bool _exchanging = false;

  Future<String> get result => _completed.future;

  void _listen() {
    _subscription = _server.listen(
      (request) => unawaited(_accept(request)),
      onError: (Object error) {
        _completeError(
          const OpenRouterAuthException('OAuth callback listener failed.'),
        );
      },
    );
    _timer = Timer(_timeout, () {
      _completeError(
        const OpenRouterAuthException('OpenRouter sign-in timed out.'),
      );
    });
  }

  Future<void> _accept(HttpRequest request) async {
    final response = request.response;
    if (request.connectionInfo?.remoteAddress.isLoopback != true ||
        request.method != 'GET' ||
        request.uri.path != '/oauth/callback') {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    if (_completed.isCompleted || _exchanging) {
      response.statusCode = HttpStatus.conflict;
      await response.close();
      return;
    }
    if (request.uri.queryParameters['state'] != _state) {
      response.statusCode = HttpStatus.forbidden;
      await response.close();
      return;
    }
    if (request.uri.queryParameters.containsKey('error')) {
      _completeError(
        const OpenRouterAuthException('Authorization was declined.'),
      );
      response.statusCode = HttpStatus.badRequest;
      response.write('Authorization was declined. Return to VietCode.');
      await response.close();
      return;
    }
    final code = request.uri.queryParameters['code'];
    if (code == null || code.isEmpty || code.length > 4096) {
      response.statusCode = HttpStatus.badRequest;
      response.write('Missing authorization code.');
      await response.close();
      return;
    }
    _exchanging = true;
    try {
      final key = await OpenRouterOAuth.exchange(
        code: code,
        verifier: _verifier,
        endpoint: _tokenEndpoint,
      );
      response.headers.contentType = ContentType.html;
      response.headers.set('cache-control', 'no-store');
      response.headers.set('referrer-policy', 'no-referrer');
      response.headers.set('content-security-policy', "default-src 'none'");
      response.write(
        '<!doctype html><meta charset="utf-8">'
        '<title>VietCode connected</title>'
        '<p>OpenRouter authorized. Return to VietCode.</p>',
      );
      await response.close();
      _complete(key);
    } catch (error) {
      response.statusCode = HttpStatus.badGateway;
      response.write('Could not finish sign-in. Return to VietCode.');
      await response.close();
      _completeError(
        error is OpenRouterAuthException
            ? error
            : const OpenRouterAuthException('OpenRouter sign-in failed.'),
      );
    }
  }

  void _complete(String key) {
    if (_completed.isCompleted) return;
    _completed.complete(key);
    unawaited(_close());
  }

  void _completeError(OpenRouterAuthException error) {
    if (_completed.isCompleted) return;
    _completed.completeError(error);
    unawaited(_close());
  }

  Future<void> cancel() async {
    _completeError(const OpenRouterAuthCancelled());
    await _close();
  }

  Future<void> _close() async {
    _timer?.cancel();
    await _subscription?.cancel();
    await _server.close(force: true);
  }
}
