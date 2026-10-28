import 'package:baocode/models/qoder_sse_normalizer.dart';
import 'package:test/test.dart';

void main() {
  test('Qoder content, finish and later usage become valid terminal SSE', () {
    final parser = QoderSseNormalizer('model-live');
    final content = parser.add({
      'id': 'reply-1',
      'created': 1720000000,
      'model': 'model-live',
      'choices': [
        {'index': 0, 'delta': {'content': 'Hi'}, 'finish_reason': null}
      ],
    });
    expect(content, hasLength(1));
    expect(content.single['choices'], isNotEmpty);

    // Qoder sometimes sends finish_reason inside delta, without text.
    expect(parser.add({
      'choices': [
        {'index': 0, 'delta': {'finish_reason': 'stop'}}
      ],
    }), isEmpty);
    expect(parser.isDone, isFalse);

    // Usage-only choices:[] event arrives after the finish frame.
    final end = parser.add({
      'choices': [],
      'usage': {
        'input_tokens': 9,
        'output_tokens': 4,
        'cache_read_input_tokens': 3,
      },
    });
    expect(end, hasLength(1));
    final finalChunk = end.single;
    expect(finalChunk['id'], 'reply-1');
    expect(finalChunk['model'], 'model-live');
    final choices = finalChunk['choices'] as List;
    expect((choices.single as Map)['finish_reason'], 'stop');
    final usage = finalChunk['usage'] as Map;
    expect(usage['prompt_tokens'], 9);
    expect(usage['completion_tokens'], 4);
    expect(usage['total_tokens'], 13);
    expect((usage['prompt_tokens_details'] as Map)['cached_tokens'], 3);
    expect(parser.isDone, isTrue);
    expect(parser.finish(), isEmpty); // no second stop chunk
  });

  test('Terminal finish without usage is flushed when upstream says DONE', () {
    final parser = QoderSseNormalizer('model-live');
    expect(parser.add({
      'choices': [
        {'index': 0, 'delta': {}, 'finish_reason': 'length'}
      ],
    }), isEmpty);
    final end = parser.finish();
    expect(end, hasLength(1));
    expect(((end.single['choices'] as List).single as Map)['finish_reason'],
        'length');
    expect(parser.finish(), isEmpty);
  });

  test('Content-bearing terminal chunk is not replayed on DONE', () {
    final parser = QoderSseNormalizer('model-live');
    final chunks = parser.add({
      'choices': [
        {
          'index': 0,
          'delta': {'content': 'OK', 'finish_reason': 'stop'},
          'finish_reason': null,
        },
      ],
    });
    expect(chunks, hasLength(1));
    expect(((chunks.single['choices'] as List).single as Map)['finish_reason'],
        'stop');
    expect(parser.finish(), isEmpty);
  });

  test('Usage-only chunk without finish is preserved on upstream EOF', () {
    final parser = QoderSseNormalizer('model-live');
    expect(parser.add({
      'choices': [],
      'usage': {'prompt_tokens': 8, 'completion_tokens': 2},
    }), isEmpty);
    final chunks = parser.finish();
    expect(chunks, hasLength(1));
    expect((chunks.single['usage'] as Map)['total_tokens'], 10);
  });
}
