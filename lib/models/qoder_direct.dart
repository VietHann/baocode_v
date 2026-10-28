/// Experimental native Qoder model catalog and inference protocol.
/// No Node, Qoder CLI, 9Router runtime, API key or localhost gateway.
///
/// Reference protocol: decolua/9router (MIT), QoderExecutor / QoderModels.
/// This uses private, undocumented endpoints; login is not a guarantee of
/// subscription access. Only real catalog model IDs are exposed in VietCode.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

import 'qoder_cosy.dart';
import 'qoder_sse_normalizer.dart';
import 'qoder_direct_oauth.dart';

class QoderInferenceException implements Exception {
  const QoderInferenceException(this.message, {this.status});
  final String message;
  final int? status;

  @override
  String toString() => message;
}

class QoderRemoteModel {
  const QoderRemoteModel({
    required this.id, required this.name, required this.config,
    this.contextWindow, this.images = false,
  });
  final String id;
  final String name;
  final Map<String, dynamic> config;
  final int? contextWindow;
  final bool images;
}

class QoderDirect {
  QoderDirect({
    Uri? modelsEndpoint, Uri? chatEndpoint, HttpClient? client,
  }) : modelsEndpoint = modelsEndpoint ??
           Uri.parse('https://api3.qoder.sh/algo/api/v2/model/list'),
       chatEndpoint = chatEndpoint ??
           Uri.parse('https://api3.qoder.sh/algo/api/v2/service/pro/sse/'
               'agent_chat_generation?FetchKeys=llm_model_result'
               '&AgentId=agent_common&Encode=1'),
       _client = client {
    for (final url in [this.modelsEndpoint, this.chatEndpoint]) {
      if (url.scheme != 'https' &&
          !(url.scheme == 'http' && url.host == '127.0.0.1')) {
        throw const QoderInferenceException(
          'Qoder inference endpoints must use HTTPS.',
        );
      }
    }
  }

  final Uri modelsEndpoint;
  final Uri chatEndpoint;
  final HttpClient? _client;
  final Map<String, Map<String, QoderRemoteModel>> _catalog = {};
  final Map<String, DateTime> _expires = {};

  String _key(QoderAccount account) => account.userId;

  /// GET model list with COSY signature; do not inject guessed model IDs.
  Future<List<QoderRemoteModel>> models(
    QoderAccount account, {bool force = false}
  ) async {
    final key = _key(account);
    if (!force && _catalog.containsKey(key) &&
        DateTime.now().isBefore(_expires[key]!)) {
      return _catalog[key]!.values.toList();
    }
    final client = _client ?? HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(modelsEndpoint)
          .timeout(const Duration(seconds: 15));
      QoderCosy.headers(account, modelsEndpoint, const [])
          .forEach(request.headers.set);
      request.headers
        ..set('Accept', 'application/json')
        ..set('Accept-Encoding', 'identity');
      final response = await request.close()
          .timeout(const Duration(seconds: 20));
      final raw = await utf8.decodeStream(response)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw QoderInferenceException(
          'Qoder refused the signed model request (HTTP '
          '${response.statusCode}). Check device-token permissions, '
          'account region and subscription.', status: response.statusCode,
        );
      }
      final data = jsonDecode(raw);
      final chat = data is Map ? data['chat'] : null;
      if (chat is! List) {
        throw const QoderInferenceException(
          'Qoder returned no chat catalog; model execution was not verified.',
        );
      }
      final catalog = <String, QoderRemoteModel>{};
      for (final row in chat) {
        if (row is! Map) continue;
        final id = row['key'];
        if (id is! String || id.isEmpty || row['enable'] == false) continue;
        final rawConfig = Map<String, dynamic>.from(row);
        final name = row['display_name'];
        catalog[id] = QoderRemoteModel(
          id: id,
          name: name is String && name.isNotEmpty ? name : id,
          config: rawConfig,
          contextWindow: row['max_input_tokens'] is int
              ? row['max_input_tokens'] as int
              : null,
          images: row['is_vl'] == true,
        );
      }
      if (catalog.isEmpty) {
        throw const QoderInferenceException(
          'Qoder returned an empty enabled chat model catalog.',
        );
      }
      _catalog[key] = catalog;
      _expires[key] = DateTime.now().add(const Duration(minutes: 10));
      return catalog.values.toList();
    } on TimeoutException {
      throw const QoderInferenceException('Qoder catalog request timed out.');
    } finally {
      if (_client == null) client.close(force: true);
    }
  }

  /// A direct provider-authenticated streaming Qoder chat request.
  /// The outer {statusCodeValue, body} SSE envelope is converted to OpenAI
  /// completion chunks, allowing VietCode's existing Claude translator to
  /// preserve assistant text, usage and tool calls.
  Stream<String> stream(
    QoderAccount account, String model, Map<String, Object?> body,
  ) async* {
    final listed = await models(account);
    final selected = listed.where((m) => m.id == model).firstOrNull;
    if (selected == null) {
      throw QoderInferenceException(
        'Qoder model "$model" is not available on this account. '
        'Refresh models in Upstreams.',
      );
    }
    final payload = _requestBody(
      account, selected, body,
    );
    final jsonBody = utf8.encode(jsonEncode(payload));
    final encoded = QoderCosy.encodeBody(jsonBody);
    final wire = latin1.encode(encoded);
    final client = _client ?? HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.postUrl(chatEndpoint)
          .timeout(const Duration(seconds: 20));
      QoderCosy.headers(account, chatEndpoint, wire)
          .forEach(request.headers.set);
      request.headers
        ..set('Content-Type', 'application/json')
        ..set('Accept', 'text/event-stream')
        ..set('Accept-Encoding', 'identity')
        ..set('Cache-Control', 'no-cache')
        ..set('X-Model-Key', selected.id)
        ..set('X-Model-Source', selected.config['source'] ?? 'system');
      request.add(wire);
      final response = await request.close()
          .timeout(const Duration(seconds: 35));
      if (response.statusCode != 200) {
        final text = await utf8.decodeStream(response)
            .timeout(const Duration(seconds: 20));
        throw QoderInferenceException(
          'Qoder model call failed (HTTP ${response.statusCode}): '
          '${text.length <= 250 ? text : text.substring(0, 250)}',
          status: response.statusCode,
        );
      }
      final normalizer = QoderSseNormalizer(model);
      await for (final line in response
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 120))) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('data:')) continue;
        final data = trimmed.substring(5).trim();
        if (data == '[DONE]') {
          for (final chunk in normalizer.finish()) {
            yield 'data: ${jsonEncode(chunk)}';
          }
          yield 'data: [DONE]';
          return;
        }
        dynamic decoded;
        try {
          decoded = jsonDecode(data);
        } on FormatException {
          continue;
        }
        if (decoded is! Map) continue;
        final rawStatus = decoded['statusCodeValue'];
        final status = rawStatus is num
            ? rawStatus.toInt()
            : int.tryParse('${rawStatus ?? ''}');
        if (status != null && status != 200) {
          throw QoderInferenceException(
            'Qoder returned HTTP-like status $status inside its stream. '
            'Check account quota and model access.',
            status: status,
          );
        }
        dynamic inner = decoded.containsKey('statusCodeValue')
            ? decoded['body'] : decoded;
        if (inner is String) {
          if (inner == '[DONE]') {
            // Qoder can send DONE as the envelope body rather than as the
            // outer SSE data. Flush deferred finish/usage in either case.
            for (final chunk in normalizer.finish()) {
              yield 'data: ${jsonEncode(chunk)}';
            }
            yield 'data: [DONE]';
            return;
          }
          try {
            inner = jsonDecode(inner);
          } on FormatException {
            continue;
          }
        }
        if (inner is! Map) continue;
        if (inner['error'] != null) {
          throw QoderInferenceException('Qoder model stream error: '
              '${inner['error']}');
        }
        final code = '${inner['code'] ?? ''}';
        if (code == '110' || code == '112') {
          throw const QoderInferenceException(
            'Qoder account quota exhausted. Check your subscription.',
            status: 429,
          );
        }
        // Terminal and usage frames can arrive separately; never drop the
        // usage-only frame or wait indefinitely for an upstream keepalive.
        for (final chunk in normalizer.add(inner)) {
          yield 'data: ${jsonEncode(chunk)}';
        }
        if (normalizer.isDone) {
          yield 'data: [DONE]';
          return;
        }
      }
      for (final chunk in normalizer.finish()) {
        yield 'data: ${jsonEncode(chunk)}';
      }
      yield 'data: [DONE]';
    } on TimeoutException {
      throw const QoderInferenceException('Qoder request timed out.');
    } finally {
      if (_client == null) client.close(force: true);
    }
  }

  /// Aggregate streamed Qoder text/tool calls into OpenAI non-stream format.
  Future<String> complete(
    QoderAccount account, String model, Map<String, Object?> body,
  ) async {
    final text = StringBuffer();
    final calls = <int, Map<String, dynamic>>{};
    var finish = 'stop';
    await for (final line in stream(account, model, body)) {
      final payload = line.substring(6).trim();
      if (payload == '[DONE]') break;
      final chunk = jsonDecode(payload);
      if (chunk is! Map || chunk['choices'] is! List) continue;
      for (final choice in chunk['choices'] as List) {
        if (choice is! Map) continue;
        if (choice['finish_reason'] is String) {
          finish = choice['finish_reason'] as String;
        }
        final delta = choice['delta'];
        if (delta is! Map) continue;
        if (delta['content'] is String) {
          text.write(delta['content']);
        }
        if (delta['tool_calls'] is List) {
          for (final call in delta['tool_calls'] as List) {
            if (call is! Map) continue;
            final index = call['index'] is int ? call['index'] as int : 0;
            final saved = calls.putIfAbsent(index, () => {
              'id': call['id'] ?? 'tool-$index',
              'type': 'function',
              'function': {'name': '', 'arguments': ''},
            });
            if (call['id'] is String) saved['id'] = call['id'];
            final function = call['function'];
            if (function is Map) {
              final sf = saved['function'] as Map<String, dynamic>;
              if (function['name'] is String) sf['name'] = function['name'];
              if (function['arguments'] is String) {
                sf['arguments'] =
                    (sf['arguments'] as String) + function['arguments'];
              }
            }
          }
        }
      }
    }
    return jsonEncode({
      'id': 'qoder-${QoderCosy.uuid()}',
      'object': 'chat.completion',
      'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'model': model,
      'choices': [{
        'index': 0,
        'message': {
          'role': 'assistant',
          'content': text.toString(),
          if (calls.isNotEmpty) 'tool_calls': [
            for (final key in (calls.keys.toList()..sort())) calls[key],
          ],
        },
        'finish_reason': finish,
      }],
    });
  }

  Map<String, Object?> _requestBody(
    QoderAccount account,
    QoderRemoteModel selected,
    Map<String, Object?> body,
  ) {
    final rawMessages = body['messages'];
    final messages = <Map<String, Object?>>[];
    final system = <String>[];
    var lastUser = '';
    if (rawMessages is List) {
      for (final item in rawMessages) {
        if (item is! Map) continue;
        final role = item['role'];
        final source = item['content'];
        final content = source is String ? source : _flatten(source);
        if (role == 'system' || role == 'developer') {
          if (content.isNotEmpty) system.add(content);
          continue;
        }
        if (role is! String) continue;
        final m = Map<String, Object?>.from(item);
        m['content'] = content;
        messages.add(m);
        if (role == 'user') lastUser = content;
      }
    }
    final id = QoderCosy.uuid();
    final config = selected.config;
    final maxAllowed = config['max_output_tokens'];
    final requested = body['max_tokens'] ?? body['max_completion_tokens'];
    var maxTokens = maxAllowed is int && maxAllowed > 0 ? maxAllowed : 32768;
    if (requested is int && requested > 0 && requested < maxTokens) {
      maxTokens = requested;
    }
    // Stable session/record identifiers preserve queue and conversation state.
    final session = sha256.convert(utf8.encode(
      'qoder-session\u0000${account.userId}\u0000${selected.id}',
    )).toString().substring(0, 16);
    final recordParts = StringBuffer('qoder-record\u0000${selected.id}');
    for (final msg in messages) {
      recordParts.write('\u0000${msg['role']}');
      recordParts.write('\u0000${msg['content']}');
    }
    if (body['tools'] is List) {
      recordParts.write('\u0000${jsonEncode(body['tools'])}');
    }
    recordParts.write('\u0000mt=$maxTokens');
    final record = sha256.convert(
      utf8.encode(recordParts.toString()),
    ).toString().substring(0, 16);
    final modelConfig = <String, Object?>{
      ...config,
      'key': selected.id,
    };
    return {
      'request_id': id,
      'request_set_id': record,
      'chat_record_id': record,
      'session_id': session,
      'stream': true,
      'chat_task': 'FREE_INPUT',
      'is_reply': true,
      'is_retry': false,
      'source': 1,
      'version': '3',
      'session_type': 'qodercli',
      'agent_id': 'agent_common',
      'task_id': 'common',
      'code_language': '',
      'chat_prompt': '',
      'image_urls': null,
      'aliyun_user_type': '',
      'system': system.join('\n\n'),
      'messages': messages,
      'tools': body['tools'] is List ? body['tools'] : const [],
      'parameters': {'max_tokens': maxTokens},
      'chat_context': {
        'chatPrompt': '',
        'imageUrls': null,
        'extra': {
          'context': [],
          'modelConfig': {
            'key': selected.id,
            'is_reasoning': config['is_reasoning'] == true,
          },
          'originalContent': lastUser,
        },
        'features': [],
        'text': lastUser,
      },
      'model_config': modelConfig,
      'business': {
        'product': 'cli',
        'version': '1.0.0',
        'type': 'agent',
        'stage': 'start',
        'id': QoderCosy.uuid(),
        'name': lastUser.length > 30 ? lastUser.substring(0, 30) : lastUser,
        'begin_at': DateTime.now().millisecondsSinceEpoch,
      },
    };
  }

  String _flatten(Object? value) {
    if (value is! List) return value?.toString() ?? '';
    final parts = <String>[];
    for (final item in value) {
      if (item is Map && item['text'] is String) {
        parts.add(item['text'] as String);
      }
    }
    return parts.join('\n');
  }
}
