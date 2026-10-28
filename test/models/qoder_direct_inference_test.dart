import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:baocode/models/qoder_cosy.dart';
import 'package:baocode/models/qoder_direct.dart';
import 'package:baocode/models/qoder_direct_oauth.dart';

void main() {
  const account = QoderAccount(
    token: 'dt-test-device-token',
    userId: 'test-user',
    machineId: 'test-machine-uuid',
    email: 'test@example.com',
  );

  test('COSY custom WAF encoder and signed request integrity', () {
    expect(QoderCosy.encodeBody(utf8.encode('hello')), 'q\$FruHPH');
    final uri = Uri.parse('https://api3.qoder.sh/algo/api/v2/model/list?Encode=1');
    final wire = latin1.encode('abc-xyz');
    final headers = QoderCosy.headers(
      account, uri, wire,
      now: DateTime.utc(2026, 10, 28),
      requestId: 'test-request-id',
      aesKey: '12345678-abcdefg',
    );
    expect(headers['Authorization'], startsWith('Bearer COSY.'));
    expect(headers['Cosy-Key'], isNotEmpty);
    expect(headers['Cosy-Bodyhash'], md5.convert(wire).toString());
    expect(headers['Cosy-Bodylength'], wire.length.toString());
    expect(headers['Cosy-Sigpath'], '/api/v2/model/list');
    expect(headers['Cosy-Machineid'], 'test-machine-uuid');
    final sections = headers['Authorization']!.split('.');
    expect(sections.length, 3);
    final payload = jsonDecode(utf8.decode(base64Decode(sections[1])));
    expect(payload['version'], 'v1');
    expect(payload['requestId'], 'test-request-id');
    expect(payload['info'], isNotEmpty);
  });

  test('Direct COSY catalog excludes disabled models and unwraps SSE',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seen = <Map<String, Object?>>[];
    server.listen((req) async {
      try {
        final body = await req.fold<List<int>>(<int>[], (a, v) => a..addAll(v));
        seen.add({
          'path': req.uri.path,
          'method': req.method,
          'model': req.headers.value('x-model-key'),
          'machine': req.headers.value('cosy-machineid'),
          'auth': req.headers.value('authorization'),
          'sigPath': req.headers.value('cosy-sigpath'),
          'bodyHash': req.headers.value('cosy-bodyhash'),
          'bodyLength': req.headers.value('cosy-bodylength'),
          'wireHash': md5.convert(body).toString(),
          'wireLength': body.length.toString(),
          'body': latin1.decode(body),
        });
        if (req.uri.path == '/model/list') {
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({
            'chat': [
              {
                'key': 'qmodel', 'display_name': 'Qwen real catalog',
                'max_input_tokens': 131072,
                'max_output_tokens': 500, 'is_reasoning': true,
                'source': 'system',
                'enable': true,
              },
              {'key': 'hidden', 'enable': false},
            ],
          }));
        } else {
          req.response.headers.contentType =
              ContentType('text', 'event-stream');
          final inner = jsonEncode({
            'id': 'cmpl',
            'choices': [
              {
                'index': 0,
                'delta': {'content': 'Qoder answered', 'finish_reason': 'stop'},
              }
            ]
          });
          req.response.write('data: ' + jsonEncode({
            'statusCodeValue': 200, 'body': inner,
          }) + '\n\n');
          req.response.write('data: [DONE]\n\n');
        }
      } finally {
        await req.response.close();
      }
    });
    try {
      final base = 'http://127.0.0.1:${server.port}';
      final provider = QoderDirect(
        modelsEndpoint: Uri.parse('$base/model/list?Encode=1'),
        chatEndpoint: Uri.parse('$base/chat?Encode=1'),
      );
      final models = await provider.models(account);
      expect(models, hasLength(1));
      expect(models.single.id, 'qmodel');
      expect(models.single.name, 'Qwen real catalog');
      final raw = await provider.complete(account, 'qmodel', {
        'model': 'qmodel',
        'messages': [
          {'role': 'system', 'content': 'Use Vietnamese'},
          {'role': 'user', 'content': 'Hi'},
        ],
        'max_tokens': 64,
      });
      final result = jsonDecode(raw);
      expect(result['choices'][0]['message']['content'], 'Qoder answered');
      expect(seen, hasLength(2));
      expect(seen[0]['path'], '/model/list');
      expect(seen[1]['path'], '/chat');
      expect(seen[1]['method'], 'POST');
      expect(seen[1]['model'], 'qmodel');
      expect(seen[1]['machine'], 'test-machine-uuid');
      expect(seen[1]['sigPath'], '/chat');
      expect(seen[1]['bodyHash'], seen[1]['wireHash']);
      expect(seen[1]['bodyLength'], seen[1]['wireLength']);
      expect(seen[1]['auth'], startsWith('Bearer COSY.'));
      expect(seen[1]['body'].toString(), isNot(contains('"messages":')));
      await expectLater(
        provider.complete(account, 'invalid-model', {
          'messages': [],
        }),
        throwsA(isA<QoderInferenceException>()),
      );
    } finally {
      await server.close(force: true);
    }
  });
}
