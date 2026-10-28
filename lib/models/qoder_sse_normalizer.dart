/// Coalesces Qoder's nonstandard streamed finish/usage frames into OpenAI
/// completion chunks. Qoder often sends a finish-only delta first and usage
/// in a later choices:[] frame; forwarding them separately loses token data
/// in Claude/OpenAI translators. Reference: decolua/9router MIT qoder/sse.js.
library;

class QoderSseNormalizer {
  QoderSseNormalizer(this.model);

  final String model;
  bool _done = false;
  String? _pendingFinish;
  Map<String, Object?>? _pendingUsage;
  bool _finishForwarded = false;
  String? _lastId;
  int? _lastCreated;

  bool get isDone => _done;

  static num? _number(Object? value) => switch (value) {
    num n => n,
    String s => num.tryParse(s),
    _ => null,
  };

  static Map<String, Object?>? _usage(Object? value) {
    if (value is! Map) return null;
    final prompt = _number(value['prompt_tokens'] ?? value['input_tokens']);
    final completion = _number(
      value['completion_tokens'] ?? value['output_tokens'],
    );
    if (prompt == null && completion == null) return null;
    final details = <String, Object?>{};
    final supplied = value['prompt_tokens_details'];
    if (supplied is Map) {
      for (final e in supplied.entries) {
        if (e.key is String) details[e.key as String] = e.value;
      }
    }
    final cached = _number(details['cached_tokens'] ??
        value['cached_tokens'] ??
        value['prompt_cache_hit_tokens'] ??
        value['cache_read_input_tokens']);
    if (cached != null) details['cached_tokens'] = cached;
    final created = _number(details['cache_creation_tokens'] ??
        value['cache_creation_input_tokens']);
    if (created != null) details['cache_creation_tokens'] = created;
    final out = <String, Object?>{
      'prompt_tokens': prompt ?? 0,
      'completion_tokens': completion ?? 0,
      'total_tokens': _number(value['total_tokens']) ??
          ((prompt ?? 0) + (completion ?? 0)),
      if (cached != null) 'cached_tokens': cached,
      if (details.isNotEmpty) 'prompt_tokens_details': details,
    };
    if (value['completion_tokens_details'] is Map) {
      out['completion_tokens_details'] = value['completion_tokens_details'];
    }
    final reasoning = _number(value['reasoning_tokens'] ??
        (value['completion_tokens_details'] is Map
            ? (value['completion_tokens_details'] as Map)['reasoning_tokens']
            : null));
    if (reasoning != null) out['reasoning_tokens'] = reasoning;
    return out;
  }

  Map<String, Object?> _terminal() => {
    'id': _lastId ?? 'qoder-usage',
    'object': 'chat.completion.chunk',
    'created': _lastCreated ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'model': model,
    'choices': [
      {'index': 0, 'delta': <String, Object?>{},
       'finish_reason': _pendingFinish ?? 'stop'},
    ],
    if (_pendingUsage != null) 'usage': _pendingUsage,
  };

  /// Return zero or more normalized OpenAI-compatible chunks. The caller
  /// serializes each one as an SSE data line; no control frames are guessed.
  List<Map<String, Object?>> add(Map<dynamic, dynamic> raw) {
    if (_done) return const [];
    final chunk = <String, Object?>{
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    if (chunk['id'] is String) _lastId = chunk['id'] as String;
    if (chunk['created'] is num) {
      _lastCreated = (chunk['created'] as num).toInt();
    }
    final newUsage = _usage(chunk['usage']);
    if (newUsage != null) _pendingUsage = newUsage;
    final choices = chunk['choices'];
    final Map<dynamic, dynamic>? choice = choices is List &&
            choices.isNotEmpty &&
            choices.first is Map
        ? choices.first as Map
        : null;
    final Map<dynamic, dynamic>? delta =
        choice?['delta'] is Map ? choice!['delta'] as Map : null;
    final finish = choice?['finish_reason'] is String
        ? choice!['finish_reason'] as String
        : delta?['finish_reason'] is String
            ? delta!['finish_reason'] as String
            : chunk['finish_reason'] is String
                ? chunk['finish_reason'] as String
                : null;
    final valuable = delta != null &&
        ((delta['content'] is String &&
                (delta['content'] as String).isNotEmpty) ||
            (delta['reasoning_content'] is String &&
                (delta['reasoning_content'] as String).isNotEmpty) ||
            (delta['tool_calls'] is List &&
                (delta['tool_calls'] as List).isNotEmpty) ||
            delta['role'] != null);
    if (valuable) {
      if (finish != null) {
        choice!['finish_reason'] = finish;
        _finishForwarded = true;
        _pendingFinish = finish;
      }
      if (newUsage != null) {
        _pendingUsage = null; // usage was already attached to this chunk
      }
      return [chunk];
    }
    if (finish != null) _pendingFinish = finish;
    if (_pendingUsage != null &&
        (_pendingFinish != null || _finishForwarded)) {
      final terminal = _terminal();
      _pendingUsage = null;
      _pendingFinish = null;
      _done = true; // upstream often keeps its socket alive after usage
      return [terminal];
    }
    return const [];
  }

  /// Flush anything waiting for an end marker and stop the caller immediately.
  List<Map<String, Object?>> finish() {
    if (_done) return const [];
    _done = true;
    if (_pendingUsage == null &&
        (_pendingFinish == null || _finishForwarded)) {
      return const [];
    }
    return [_terminal()];
  }
}
