import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Adapts VietCode to an authenticated loopback 9Router instance.
/// 9Router handles its providers' OAuth logins and refresh lifecycle.
/// VietCode automatically provisions an independent local routing key;
/// it never reads a provider's OAuth tokens or asks for their API keys.
class NineRouterException implements Exception {
  const NineRouterException(this.message);
  final String message;
  @override
  String toString() => message;
}

class NineRouterAccount {
  const NineRouterAccount({required this.key, required this.models});
  final String key;
  final List<String> models;
}

class NineRouterBridge {
  NineRouterBridge({Uri? server, HttpClient? client})
      : server = server ?? Uri.parse('http://127.0.0.1:20128'),
        _externalClient = client {
    if (this.server.scheme != 'http' ||
        this.server.host != '127.0.0.1' ||
        this.server.userInfo.isNotEmpty ||
        (this.server.path.isNotEmpty && this.server.path != '/') ||
        this.server.hasQuery ||
        this.server.hasFragment) {
      throw const NineRouterException(
        'Only a 9Router instance on 127.0.0.1 is supported.',
      );
    }
  }

  final Uri server;
  final HttpClient? _externalClient;
  Uri _at(String path) => server.replace(path: path);
  static const _keyName = 'vietcode-desktop';

  Future<NineRouterAccount> connect(String password) async {
    if (password.isEmpty) {
      throw const NineRouterException('Enter the 9Router dashboard password.');
    }
    final http = _externalClient ?? HttpClient();
    http.connectionTimeout = const Duration(seconds: 6);
    try {
      final login = await _request(
        http, 'POST', '/api/auth/login',
        json: {'password': password},
      );
      if (login.status != 200 || login.body['success'] != true) {
        throw const NineRouterException(
          '9Router dashboard sign-in failed. Check the password.',
        );
      }
      final cookie = login.authCookie;
      if (cookie == null) {
        throw const NineRouterException(
          '9Router did not return a dashboard login session.',
        );
      }
      final list = await _request(http, 'GET', '/api/keys', cookie: cookie);
      if (list.status != 200) {
        throw const NineRouterException('Cannot access 9Router local keys.');
      }
      String? key;
      final keys = list.body['keys'];
      if (keys is List) {
        for (final item in keys.whereType<Map>()) {
          if (item['name'] == _keyName &&
              item['isActive'] != false &&
              item['key'] is String) {
            key = item['key'] as String;
            break;
          }
        }
      }
      if (key == null) {
        final created = await _request(
          http, 'POST', '/api/keys',
          cookie: cookie, json: {'name': _keyName},
        );
        if (created.status != HttpStatus.created ||
            created.body['key'] is! String) {
          throw const NineRouterException(
            'Could not provision VietCode local router access.',
          );
        }
        key = created.body['key'] as String;
      }
      if (key.isEmpty || key.length > 4096) {
        throw const NineRouterException('Invalid 9Router credential.');
      }
      final response = await _request(
        http, 'GET', '/v1/models', bearer: key,
      );
      if (response.status != 200) {
        throw const NineRouterException(
          '9Router rejected model discovery. Verify OAuth '
          'accounts and their model quotas in the dashboard.',
        );
      }
      final seen = <String>{};
      final models = <String>[];
      final entries = response.body['data'];
      if (entries is List) {
        for (final entry in entries.whereType<Map>()) {
          final id = entry['id'];
          if (id is String && id.isNotEmpty &&
              id.length <= 200 && seen.add(id)) {
            models.add(id);
          }
          if (models.length >= 500) break;
        }
      }
      if (models.isEmpty) {
        throw const NineRouterException(
          'No models available. Connect an account in the 9Router dashboard.',
        );
      }
      models.sort();
      return NineRouterAccount(key: key, models: models);
    } on SocketException {
      throw const NineRouterException(
        '9Router is offline at 127.0.0.1:20128. Start 9router first.',
      );
    } on TimeoutException {
      throw const NineRouterException('9Router did not answer in time.');
    } finally {
      if (_externalClient == null) http.close(force: true);
    }
  }

  Future<_GatewayResponse> _request(
    HttpClient http, String method, String path, {
    Map<String, Object?>? json,
    String? cookie,
    String? bearer,
  }) async {
    final request = await http.openUrl(method, _at(path))
        .timeout(const Duration(seconds: 8));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (json != null) {
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(json)));
    }
    if (cookie != null) request.headers.set('cookie', cookie);
    if (bearer != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ' + bearer);
    }
    final response = await request.close().timeout(
      const Duration(seconds: 12),
    );
    final text = await utf8.decodeStream(response);
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const NineRouterException('9Router returned invalid JSON.');
    }
    final headers =
        response.headers[HttpHeaders.setCookieHeader] ?? const <String>[];
    String? authCookie;
    for (final header in headers) {
      final match = RegExp(r'(?:^|,\s*)auth_token=([^;,\s]+)')
          .firstMatch(header);
      if (match != null) {
        authCookie = 'auth_token=' + match.group(1)!;
        break;
      }
    }
    return _GatewayResponse(
      response.statusCode,
      decoded is Map<String, dynamic> ? decoded : const {},
      authCookie,
    );
  }
}

class _GatewayResponse {
  const _GatewayResponse(this.status, this.body, this.authCookie);
  final int status;
  final Map<String, dynamic> body;
  final String? authCookie;
}
