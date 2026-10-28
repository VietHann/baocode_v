/// GitHub Copilot account OAuth with native device authorization and direct
/// model requests. VietCode does not use the OpenCode/9Router/gh CLIs.
///
/// Based on decolua/9router's MIT GitHub provider and GitHub's public
/// OAuth device authorization specification. OAuth tokens go in SecretStore.
/// Copilot API integration is unofficial and may change or be restricted.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'secret_store.dart';

class CopilotDirectException implements Exception {
  const CopilotDirectException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CopilotDirectCancelled extends CopilotDirectException {
  const CopilotDirectCancelled() : super('GitHub sign-in cancelled.');
}

class CopilotAccount {
  const CopilotAccount({
    required this.githubToken,
    this.copilotToken = '',
    this.copilotExpiry,
    this.login = '',
  });
  final String githubToken;
  final String copilotToken;
  final DateTime? copilotExpiry;
  final String login;

  Map<String, Object?> toJson() => {
    'githubToken': githubToken,
    'copilotToken': copilotToken,
    'copilotExpiry': copilotExpiry?.toIso8601String(),
    'login': login,
  };

  factory CopilotAccount.fromJson(Map<String, dynamic> j) => CopilotAccount(
    githubToken: j['githubToken'] as String,
    copilotToken: (j['copilotToken'] ?? '').toString(),
    copilotExpiry:
        DateTime.tryParse((j['copilotExpiry'] ?? '').toString()),
    login: (j['login'] ?? '').toString(),
  );
}

class CopilotDirect {
  CopilotDirect({
    Uri? deviceEndpoint,
    Uri? tokenEndpoint,
    Uri? copilotTokenEndpoint,
    Uri? modelsEndpoint,
    Uri? completionEndpoint,
    Uri? profileEndpoint,
    HttpClient? client,
  }) : deviceEndpoint = deviceEndpoint ??
           Uri.parse('https://github.com/login/device/code'),
       tokenEndpoint = tokenEndpoint ??
           Uri.parse('https://github.com/login/oauth/access_token'),
       copilotTokenEndpoint = copilotTokenEndpoint ??
           Uri.parse('https://api.github.com/copilot_internal/v2/token'),
       modelsEndpoint = modelsEndpoint ??
           Uri.parse('https://api.githubcopilot.com/models'),
       completionEndpoint = completionEndpoint ??
           Uri.parse('https://api.githubcopilot.com/chat/completions'),
       profileEndpoint = profileEndpoint ??
           Uri.parse('https://api.github.com/user'),
       _client = client {
    for (final uri in [
      this.deviceEndpoint, this.tokenEndpoint, this.copilotTokenEndpoint,
      this.modelsEndpoint, this.completionEndpoint, this.profileEndpoint,
    ]) {
      if (uri.scheme != 'https' &&
          !(uri.scheme == 'http' && uri.host == '127.0.0.1')) {
        throw const CopilotDirectException(
          'GitHub OAuth and model endpoints must use HTTPS.',
        );
      }
    }
  }

  /// Public OAuth app identifier shared by the GitHub Copilot device flow.
  /// Reference: decolua/9router open-sse/providers/registry/github.js.
  static const clientId = 'Iv1.b507a08c87ecfe98';
  static const secretId = 'vietcode.oauth.github-copilot';

  final Uri deviceEndpoint;
  final Uri tokenEndpoint;
  final Uri copilotTokenEndpoint;
  final Uri modelsEndpoint;
  final Uri completionEndpoint;
  final Uri profileEndpoint;
  final HttpClient? _client;

  Future<CopilotAccount?> saved({SecretStore? secrets}) async {
    final json = await (secrets ?? SecretStore.instance).read(secretId);
    if (json == null) return null;
    try {
      final body = jsonDecode(json);
      return body is Map<String, dynamic>
          ? CopilotAccount.fromJson(body) : null;
    } on Object {
      return null;
    }
  }

  Future<void> save(CopilotAccount account, {SecretStore? secrets}) async =>
      (secrets ?? SecretStore.instance)
          .write(secretId, jsonEncode(account.toJson()));

  Future<void> signOut({SecretStore? secrets}) async =>
      (secrets ?? SecretStore.instance).delete(secretId);

  Future<CopilotDeviceLogin> begin() async {
    final http = _client ?? HttpClient();
    try {
      final device = await _postForm(http, deviceEndpoint, {
        'client_id': clientId, 'scope': 'read:user',
      });
      final code = device['device_code'];
      final userCode = device['user_code'];
      final url = device['verification_uri'];
      if (code is! String || code.isEmpty ||
          userCode is! String || userCode.isEmpty ||
          url is! String || url.isEmpty) {
        throw const CopilotDirectException(
          'GitHub did not return a device authorization code.',
        );
      }
      // Only display the actual GitHub device authorization page. A changed
      // or compromised upstream response must not send the user to an
      // unrelated site to enter a one-time code.
      final verifyUrl = Uri.tryParse(url);
      if (verifyUrl == null || verifyUrl.scheme != 'https' ||
          verifyUrl.host != 'github.com' ||
          !verifyUrl.path.startsWith('/login/device') ||
          verifyUrl.userInfo.isNotEmpty) {
        throw const CopilotDirectException(
          'GitHub returned an unexpected device verification URL.',
        );
      }
      final interval = (device['interval'] as num?)?.toInt() ?? 5;
      final expires = (device['expires_in'] as num?)?.toInt() ?? 900;
      return CopilotDeviceLogin._(
        owner: this,
        deviceCode: code,
        userCode: userCode,
        url: verifyUrl,
        interval: Duration(seconds: interval > 0 ? interval : 5),
        timeout: Duration(seconds: expires > 0 ? expires : 900),
      );
    } finally {
      if (_client == null) http.close(force: true);
    }
  }

  Future<CopilotAccount> ensureToken(CopilotAccount account,
      {SecretStore? secrets}) async {
    if (account.copilotToken.isNotEmpty &&
        account.copilotExpiry != null &&
        account.copilotExpiry!.isAfter(
          DateTime.now().add(const Duration(minutes: 3)))) {
      return account;
    }
    final http = _client ?? HttpClient();
    try {
      final request = await http.getUrl(copilotTokenEndpoint)
          .timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.authorizationHeader,
          'Bearer ' + account.githubToken);
      request.headers.set('Accept', 'application/json');
      request.headers.set('X-GitHub-Api-Version', '2022-11-28');
      request.headers.set('User-Agent', 'GitHubCopilotChat/0.26.7');
      final response = await request.close()
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        final code = response.statusCode;
        await response.drain<void>();
        throw CopilotDirectException(
          'GitHub Copilot account token rejected (HTTP ' +
              code.toString() + '). Check your Copilot subscription.',
        );
      }
      final body = jsonDecode(await utf8.decodeStream(response));
      if (body is! Map || body['token'] is! String) {
        throw const CopilotDirectException(
          'GitHub Copilot did not return a model credential.',
        );
      }
      final rawExpiry = body['expires_at'];
      final seconds = rawExpiry is num ? rawExpiry.toInt() :
          int.tryParse(rawExpiry?.toString() ?? '');
      final expiry = seconds == null ? DateTime.now().add(
          const Duration(minutes: 25)) :
          DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      final updated = CopilotAccount(
        githubToken: account.githubToken,
        copilotToken: body['token'] as String,
        copilotExpiry: expiry,
        login: account.login,
      );
      await save(updated, secrets: secrets);
      return updated;
    } finally {
      if (_client == null) http.close(force: true);
    }
  }

  Future<List<String>> models(CopilotAccount account,
      {SecretStore? secrets}) async {
    final current = await ensureToken(account, secrets: secrets);
    final http = _client ?? HttpClient();
    try {
      final req = await http.getUrl(modelsEndpoint)
          .timeout(const Duration(seconds: 12));
      _copilotHeaders(req, current.copilotToken);
      final res = await req.close()
          .timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) {
        final status = res.statusCode;
        await res.drain<void>();
        throw CopilotDirectException(
          'Copilot model discovery failed (HTTP ' + status.toString() + ').',
        );
      }
      final body = jsonDecode(
        await utf8.decodeStream(res).timeout(const Duration(seconds: 25)),
      );
      final data = body is Map ? body['data'] : null;
      if (data is! List) return const [];
      final ids = <String>{};
      for (final row in data.whereType<Map>()) {
        final id = row['id'];
        if (id is String && id.isNotEmpty && id.length < 200) ids.add(id);
      }
      return ids.toList()..sort();
    } finally {
      if (_client == null) http.close(force: true);
    }
  }

  Future<String> complete(CopilotAccount account, {
    required String model,
    required List<Map<String, Object?>> messages,
    SecretStore? secrets,
  }) async {
    final current = await ensureToken(account, secrets: secrets);
    final http = _client ?? HttpClient();
    try {
      final req = await http.postUrl(completionEndpoint)
          .timeout(const Duration(seconds: 15));
      _copilotHeaders(req, current.copilotToken);
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({
        'model': model,
        'messages': messages,
        'stream': false,
      })));
      final res = await req.close().timeout(const Duration(seconds: 90));
      if (res.statusCode != 200) {
        final status = res.statusCode;
        await res.drain<void>();
        throw CopilotDirectException(
          'Copilot model request failed (HTTP ' + status.toString() + ').',
        );
      }
      final body = jsonDecode(
        await utf8.decodeStream(res).timeout(const Duration(seconds: 90)),
      );
      final choices = body is Map ? body['choices'] : null;
      if (choices is List && choices.isNotEmpty &&
          choices.first is Map) {
        final message = (choices.first as Map)['message'];
        if (message is Map && message['content'] is String) {
          return message['content'] as String;
        }
      }
      throw const CopilotDirectException(
        'Copilot returned a response without text.',
      );
    } finally {
      if (_client == null) http.close(force: true);
    }
  }

  static void _copilotHeaders(HttpClientRequest request, String token) {
    request.headers.set(
        HttpHeaders.authorizationHeader, 'Bearer ' + token);
    request.headers.set('Accept', 'application/json');
    request.headers.set('copilot-integration-id', 'vscode-chat');
    request.headers.set('editor-version', 'vscode/1.110.0');
    request.headers.set('editor-plugin-version', 'copilot-chat/0.38.0');
    request.headers.set('openai-intent', 'conversation-panel');
    request.headers.set('X-Initiator', 'user');
    request.headers.set('User-Agent', 'GitHubCopilotChat/0.38.0');
  }

  Future<Map<String, dynamic>> _postForm(
    HttpClient http, Uri uri, Map<String, String> values,
  ) async {
    final request = await http.postUrl(uri)
        .timeout(const Duration(seconds: 12));
    request.headers.set('Accept', 'application/json');
    request.headers.contentType =
        ContentType('application', 'x-www-form-urlencoded');
    request.add(utf8.encode(values.entries.map((e) =>
        Uri.encodeQueryComponent(e.key) + '=' +
        Uri.encodeQueryComponent(e.value)).join('&')));
    final response = await request.close()
        .timeout(const Duration(seconds: 20));
    final status = response.statusCode;
    if (status != 200) {
      await response.drain<void>();
      throw CopilotDirectException(
        'GitHub device authorization failed (HTTP ' +
            status.toString() + ').',
      );
    }
    final value = jsonDecode(await utf8.decodeStream(response));
    if (value is! Map<String, dynamic>) {
      throw const CopilotDirectException('Invalid GitHub OAuth response.');
    }
    return value;
  }
}

class CopilotDeviceLogin {
  CopilotDeviceLogin._({
    required CopilotDirect owner, required this.deviceCode,
    required this.userCode, required this.url,
    required this.interval, required this.timeout,
  }) : _owner = owner;

  final CopilotDirect _owner;
  final String deviceCode;
  final String userCode;
  final Uri url;
  final Duration interval;
  final Duration timeout;

  final Completer<CopilotAccount> _completed = Completer<CopilotAccount>();
  bool _cancelled = false;
  bool _started = false;
  HttpClient? _ownedClient;
  Future<CopilotAccount> get result => _completed.future;

  void start() {
    if (_started) return;
    _started = true;
    unawaited(_run());
  }

  Future<void> cancel() async {
    _cancelled = true;
    _ownedClient?.close(force: true);
    if (!_completed.isCompleted) {
      _completed.completeError(const CopilotDirectCancelled());
    }
  }

  Future<void> _run() async {
    final client = _owner._client ?? HttpClient();
    if (_owner._client == null) _ownedClient = client;
    try {
      final deadline = DateTime.now().add(timeout);
      var delay = interval;
      while (!_cancelled && DateTime.now().isBefore(deadline)) {
        final body = await _owner._postForm(client, _owner.tokenEndpoint, {
          'client_id': CopilotDirect.clientId,
          'device_code': deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        });
        final token = body['access_token'];
        if (token is String && token.isNotEmpty) {
          String login = '';
          try {
            final req = await client.getUrl(_owner.profileEndpoint);
            req.headers.set(
                HttpHeaders.authorizationHeader, 'Bearer ' + token);
            req.headers.set('User-Agent', 'VietCode');
            final res = await req.close();
            if (res.statusCode == 200) {
              final profile = jsonDecode(await utf8.decodeStream(res));
              if (profile is Map) login = (profile['login'] ?? '').toString();
            } else {
              await res.drain<void>();
            }
          } on Object {
            // GitHub profile is optional.
          }
          if (!_completed.isCompleted) {
            _completed.complete(CopilotAccount(
              githubToken: token, login: login));
          }
          return;
        }
        final error = (body['error'] ?? '').toString();
        if (error == 'slow_down') {
          delay += const Duration(seconds: 5);
        } else if (error != 'authorization_pending') {
          throw CopilotDirectException(
            error == 'access_denied'
                ? 'GitHub authorization was declined.'
                : 'GitHub OAuth failed: ' + error,
          );
        }
        if (!_cancelled) await Future<void>.delayed(delay);
      }
      if (!_completed.isCompleted) {
        _completed.completeError(
          const CopilotDirectException('GitHub authorization timed out.'),
        );
      }
    } on Object catch (error) {
      if (!_completed.isCompleted) {
        _completed.completeError(error is CopilotDirectException
            ? error
            : const CopilotDirectException('GitHub OAuth failed.'));
      }
    } finally {
      _ownedClient?.close(force: true);
      _ownedClient = null;
    }
  }
}
