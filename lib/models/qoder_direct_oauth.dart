/// Native Qoder device OAuth (no CLI, external gateway or proxy).
/// Ported from MIT-licensed decolua/9router OAuth QoderService.
/// Attribution: https://github.com/decolua/9router/blob/master/LICENSE
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'oauth_pkce.dart';
import 'secret_store.dart';

class QoderAuthException implements Exception {
  const QoderAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class QoderAuthCancelled extends QoderAuthException {
  const QoderAuthCancelled() : super('Qoder sign-in cancelled.');
}

class QoderAccount {
  const QoderAccount({
    required this.token, required this.userId, required this.machineId,
    this.name = '', this.email = '', this.refreshToken = '',
    this.expiresAt,
  });
  final String token;
  final String userId;
  final String machineId;
  final String name;
  final String email;
  final String refreshToken;
  final DateTime? expiresAt;

  Map<String, Object?> toJson() => {
    'token': token, 'userId': userId, 'machineId': machineId,
    'name': name, 'email': email, 'refreshToken': refreshToken,
    'expiresAt': expiresAt?.toIso8601String(),
  };

  factory QoderAccount.fromJson(Map<String, dynamic> m) => QoderAccount(
    token: m['token'] as String,
    userId: (m['userId'] ?? '').toString(),
    machineId: (m['machineId'] ?? '').toString(),
    name: (m['name'] ?? '').toString(),
    email: (m['email'] ?? '').toString(),
    refreshToken: (m['refreshToken'] ?? '').toString(),
    expiresAt: DateTime.tryParse((m['expiresAt'] ?? '').toString()),
  );
}

class QoderDirectOAuth {
  QoderDirectOAuth({
    Uri? loginUri, Uri? pollUri, Uri? userInfoUri,
    HttpClient? client,
    this.interval = const Duration(seconds: 2),
    this.timeout = const Duration(minutes: 5),
  }) : loginUri = loginUri ??
           Uri.parse('https://qoder.com/device/selectAccounts'),
       pollUri = pollUri ??
           Uri.parse('https://openapi.qoder.sh/api/v1/deviceToken/poll'),
       userInfoUri = userInfoUri ??
           Uri.parse('https://openapi.qoder.sh/api/v1/userinfo'),
       _client = client {
    for (final uri in [this.loginUri, this.pollUri, this.userInfoUri]) {
      if (uri.scheme != 'https' &&
          !(uri.scheme == 'http' && uri.host == '127.0.0.1')) {
        throw const QoderAuthException(
          'OAuth requires HTTPS provider endpoints.',
        );
      }
    }
  }

  static const secretId = 'vietcode.oauth.qoder';
  final Uri loginUri;
  final Uri pollUri;
  final Uri userInfoUri;
  final HttpClient? _client;
  final Duration interval;
  final Duration timeout;

  Future<QoderAccount?> saved({SecretStore? secrets}) async {
    final raw = await (secrets ?? SecretStore.instance).read(secretId);
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) return null;
      final account = QoderAccount.fromJson(value);
      if (account.expiresAt != null &&
          DateTime.now().isAfter(account.expiresAt!)) return null;
      return account;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> save(QoderAccount account, {SecretStore? secrets}) async {
    await (secrets ?? SecretStore.instance)
        .write(secretId, jsonEncode(account.toJson()));
  }

  Future<void> signOut({SecretStore? secrets}) async =>
      (secrets ?? SecretStore.instance).delete(secretId);

  QoderDeviceLogin begin() {
    final source = Random.secure();
    String uuid() {
      final bytes = [for (var i = 0; i < 16; i++) source.nextInt(256)];
      bytes[6] = (bytes[6] & 15) | 64;
      bytes[8] = (bytes[8] & 63) | 128;
      final hex = bytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
      return hex.substring(0, 8) + '-' + hex.substring(8, 12) + '-' +
          hex.substring(12, 16) + '-' + hex.substring(16, 20) + '-' +
          hex.substring(20);
    }
    final pkce = OAuthPkce.generate();
    final nonce = uuid();
    final machineId = uuid();
    return QoderDeviceLogin._(
      owner: this, nonce: nonce, machineId: machineId,
      verifier: pkce.verifier,
      url: loginUri.replace(queryParameters: {
        'challenge': pkce.challenge,
        'challenge_method': 'S256',
        'machine_id': machineId,
        'nonce': nonce,
      }),
    );
  }
}

class QoderDeviceLogin {
  QoderDeviceLogin._({
    required QoderDirectOAuth owner, required this.nonce,
    required this.machineId, required String verifier, required this.url,
  }) : _owner = owner, _verifier = verifier;

  final QoderDirectOAuth _owner;
  final String nonce;
  final String machineId;
  final String _verifier;
  final Uri url;
  final Completer<QoderAccount> _completed = Completer<QoderAccount>();
  bool _cancelled = false;
  bool _started = false;
  HttpClient? _ownedClient;

  Future<QoderAccount> get result => _completed.future;

  void start() {
    if (_started) return;
    _started = true;
    unawaited(_run());
  }

  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    _ownedClient?.close(force: true);
    if (!_completed.isCompleted) {
      _completed.completeError(const QoderAuthCancelled());
    }
  }

  Future<void> _run() async {
    final client = _owner._client ?? HttpClient();
    if (_owner._client == null) _ownedClient = client;
    try {
      final deadline = DateTime.now().add(_owner.timeout);
      while (!_cancelled && DateTime.now().isBefore(deadline)) {
        final url = _owner.pollUri.replace(queryParameters: {
          ..._owner.pollUri.queryParameters,
          'nonce': nonce,
          'verifier': _verifier,
          'challenge_method': 'S256',
        });
        final request = await client.getUrl(url)
            .timeout(const Duration(seconds: 12));
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set('User-Agent', 'Go-http-client/2.0');
        final response = await request.close()
            .timeout(const Duration(seconds: 15));
        final status = response.statusCode;
        if (status == 202 || status == 404) {
          await response.drain<void>();
          if (!_cancelled) await Future<void>.delayed(_owner.interval);
          continue;
        }
        if (status != 200) {
          await response.drain<void>();
          throw QoderAuthException(
            'Qoder token endpoint returned HTTP ' + status.toString(),
          );
        }
        final decoded = jsonDecode(await utf8.decodeStream(response));
        if (decoded is! Map<String, dynamic>) {
          throw const QoderAuthException('Invalid device token response.');
        }
        final token = decoded['token'];
        if (token is! String || token.isEmpty) {
          throw const QoderAuthException('Qoder returned no account token.');
        }
        final profile = await _fetchProfile(client, token);
        if (_cancelled) return;
        final userId = (decoded['user_id'] ??
            profile['id'] ?? profile['user_id'] ?? '').toString();
        if (userId.isEmpty) {
          throw const QoderAuthException(
            'Qoder did not return a usable account ID.',
          );
        }
        final expiry = _expiry(decoded);
        if (!_completed.isCompleted) {
          _completed.complete(QoderAccount(
            token: token, userId: userId, machineId: machineId,
            refreshToken: (decoded['refresh_token'] ?? '').toString(),
            email: (profile['email'] ?? '').toString(),
            name: (profile['name'] ?? profile['username'] ?? '').toString(),
            expiresAt: expiry,
          ));
        }
        return;
      }
      if (!_cancelled && !_completed.isCompleted) {
        _completed.completeError(
          const QoderAuthException('Qoder OAuth sign-in timed out.'),
        );
      }
    } on Object catch (error) {
      if (!_completed.isCompleted) {
        _completed.completeError(
          error is QoderAuthException
              ? error
              : const QoderAuthException(
                  'Qoder login failed. Check network and account.',
                ),
        );
      }
    } finally {
      _ownedClient?.close(force: true);
      _ownedClient = null;
    }
  }

  static DateTime? _expiry(Map<String, dynamic> body) {
    final ms = int.tryParse((body['expires_at'] ?? '').toString());
    if (ms != null && ms > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    final iso = DateTime.tryParse((body['expires_at'] ?? '').toString());
    if (iso != null) return iso;
    final sec = int.tryParse((body['expires_in'] ?? '').toString());
    return DateTime.now().add(
      Duration(seconds: sec != null && sec > 0 ? sec : 2592000),
    );
  }

  Future<Map<String, dynamic>> _fetchProfile(
    HttpClient http, String token,
  ) async {
    try {
      final request = await http.getUrl(_owner.userInfoUri)
          .timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ' + token);
      final response = await request.close()
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        await response.drain<void>();
        return {};
      }
      final json = jsonDecode(await utf8.decodeStream(response));
      return json is Map<String, dynamic> ? json : {};
    } on Object {
      return {};
    }
  }
}
