import 'dart:convert';

/// Native coding-agent CLIs reuse their own interactive OAuth sessions.
enum AccountCliKind { qoder, opencode, antigravity }

class AccountCliEvent {
  const AccountCliEvent({
    this.text,
    this.tool,
    this.sessionId,
    this.error,
    this.changedFiles = false,
  });

  final String? text;
  final String? tool;
  final String? sessionId;
  final String? error;
  final bool changedFiles;
}

class AccountCliProtocol {
  AccountCliProtocol(this.kind);
  final AccountCliKind kind;
  final Map<String, String> _qoderText = {};

  /// Parse one JSONL event; never render raw JSON with possible credentials.
  AccountCliEvent? parseLine(String line) {
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final data = decoded;
    final type = data['type'];
    if (type == 'error') {
      final message = data['message'] ?? data['error'];
      return AccountCliEvent(
        error: message is String ? message : 'Agent error',
      );
    }
    if (kind == AccountCliKind.qoder) {
      if (type == 'result') {
        return AccountCliEvent(
          sessionId: data['session_id'] as String?,
          error: data['is_error'] == true
              ? (data['result'] ?? 'Qoder request failed').toString()
              : null,
        );
      }
      if (type != 'assistant') return null;
      final message = data['message'];
      if (message is! Map) return null;
      final id = (message['id'] ?? data['uuid'] ?? 'assistant').toString();
      final blocks = message['content'];
      if (blocks is! List) return null;
      final response = blocks
          .whereType<Map>()
          .where((block) => block['type'] == 'text')
          .map((block) => block['text'])
          .whereType<String>()
          .join();
      final before = _qoderText[id] ?? '';
      _qoderText[id] = response;
      final added = response.startsWith(before)
          ? response.substring(before.length) : response;
      final calls = blocks.whereType<Map>()
          .where((block) => block['type'] == 'tool_use');
      final tool = calls.isEmpty ? null
          : (calls.first['name'] ?? 'Tool').toString();
      return AccountCliEvent(
        text: added.isEmpty ? null : added,
        tool: tool,
        sessionId: data['session_id'] as String?,
        changedFiles: tool != null,
      );
    }

    // OpenCode JSON output: text, tool_use, step_start, step_finish.
    final sessionId = data['sessionID'] as String?;
    final part = data['part'];
    if (type == 'text' && part is Map) {
      return AccountCliEvent(
        text: part['text'] is String ? part['text'] as String : null,
        sessionId: sessionId,
      );
    }
    if (type == 'tool_use' && part is Map) {
      return AccountCliEvent(
        tool: (part['tool'] ?? 'Tool').toString(),
        sessionId: sessionId,
        changedFiles: true,
      );
    }
    if (type == 'step_finish' && part is Map && part['reason'] == 'error') {
      return AccountCliEvent(
        sessionId: sessionId, error: 'OpenCode step failed.',
      );
    }
    return sessionId == null ? null : AccountCliEvent(sessionId: sessionId);
  }
}

/// Prompt is one process argument, never interpolated into a shell string.
List<String> accountCliArguments({
  required AccountCliKind kind,
  required String prompt,
  String? model,
  String? sessionId,
}) {
  final selected = model == null || model == 'default' || model == 'auto'
      ? null : model;
  if (kind == AccountCliKind.qoder) {
    return [
      '-p', prompt, '--output-format', 'stream-json',
      if (selected != null) ...['--model', selected],
      if (sessionId != null && sessionId.isNotEmpty) ...[
        '--session-id', sessionId,
      ],
    ];
  }
  return [
    'run', '--format', 'json',
    if (selected != null) ...['--model', selected],
    if (sessionId != null && sessionId.isNotEmpty) ...[
      '--session', sessionId,
    ],
    prompt,
  ];
}

String accountCliExecutable(AccountCliKind kind) =>
    kind == AccountCliKind.qoder ? 'qoder' : 'opencode';
