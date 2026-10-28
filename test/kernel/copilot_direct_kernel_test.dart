import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/copilot/copilot_direct_kernel.dart';
import 'package:baocode/models/copilot_direct.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:baocode/chat/chat_models.dart';

void main() {
  test('Copilot native chat kernel completes turns and sends conversation history',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final conversations = <List<dynamic>>[];
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/chat') {
        final body = jsonDecode(await utf8.decodeStream(request)) as Map;
        conversations.add(body['messages'] as List);
        request.response.write(jsonEncode({
          'choices': [
            {'message': {'content': 'Reply ' + conversations.length.toString()}}
          ]
        }));
      } else {
        request.response.statusCode = 404;
        request.response.write('{}');
      }
      await request.response.close();
    });

    final secrets = MemorySecretStore();
    // flutter_test substitutes an HttpClient that responds HTTP 400 to
    // every request. Construct a genuine client explicitly for the loopback
    // mock server rather than disabling the test binding's global override.
    final localClient = _NativeTestHttpOverrides().createHttpClient(null);
    final provider = CopilotDirect(
      client: localClient,
      completionEndpoint: Uri.parse(
          'http://127.0.0.1:' + server.port.toString() + '/chat'),
    );
    await provider.save(CopilotAccount(
      githubToken: 'github-account-token',
      copilotToken: 'copilot-subscription-token',
      copilotExpiry: DateTime.now().add(const Duration(hours: 1)),
      login: 'test',
    ), secrets: secrets);

    const descriptor = KernelDescriptor(
      id: 'copilot-test',
      label: 'Copilot test',
      description: 'Mocked native model',
      icon: Icons.code,
      create: _cannotCreate,
    );
    final kernel = CopilotDirectKernel(
      descriptor, const KernelContext(),
      provider: provider, secrets: secrets,
    );
    final events = <KernelEvent>[];
    final subscription = kernel.events.listen(events.add);
    try {
      kernel.send(const KernelTurn(id: 'first', text: 'Hello'));
      await kernel.stopped;
      kernel.send(const KernelTurn(id: 'second', text: 'Continue'));
      await kernel.stopped;

      expect(conversations, hasLength(2));
      expect(conversations[0], hasLength(1));
      expect(conversations[1], hasLength(3));
      expect((conversations[1][1] as Map)['role'], 'assistant');
      expect(events.whereType<TurnStarted>().map((e) => e.turnId),
          ['first', 'second']);
      expect(events.whereType<TurnEnded>().map((e) => e.turnId),
          ['first', 'second']);
      expect(events.whereType<TurnEnded>().every((e) => !e.interrupted),
          isTrue);
      final text = events.whereType<ItemUpserted>()
          .map((e) => e.item)
          .whereType<AssistantTextItem>()
          .map((i) => i.text);
      expect(text, containsAll(['Reply 1', 'Reply 2']));
    } finally {
      kernel.dispose();
      await subscription.cancel();
      localClient.close(force: true);
      await server.close(force: true);
    }
  });
}

Never _cannotCreate(KernelContext context) =>
    throw UnsupportedError('test descriptor is a placeholder');

/// Bypasses Flutter's default HTTP-400 sandbox for the injected test-only
/// client. Production requests still use ordinary HttpClient security.
class _NativeTestHttpOverrides extends HttpOverrides {}
