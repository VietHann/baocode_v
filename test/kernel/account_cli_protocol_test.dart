import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/kernel/account_cli/account_cli_protocol.dart';

void main() {
  test('Qoder CLI uses headless JSONL and reuses local account', () {
    expect(
      accountCliArguments(
        kind: AccountCliKind.qoder,
        prompt: 'Inspect the project',
        model: 'performance',
        sessionId: 'session-1',
      ),
      [
        '-p', 'Inspect the project',
        '--output-format', 'stream-json',
        '--model', 'performance',
        '--session-id', 'session-1',
      ],
    );
    expect(accountCliExecutable(AccountCliKind.qoder), 'qoder');
  });

  test('OpenCode and Antigravity use native OpenCode authenticated CLI', () {
    final args = accountCliArguments(
      kind: AccountCliKind.antigravity,
      prompt: 'Describe the files',
      model: 'google/antigravity-gemini-3.1-pro',
      sessionId: 'ses_123',
    );
    expect(args, [
      'run', '--format', 'json',
      '--model', 'google/antigravity-gemini-3.1-pro',
      '--session', 'ses_123',
      'Describe the files',
    ]);
    expect(accountCliExecutable(AccountCliKind.antigravity), 'opencode');
    expect(accountCliArguments(
      kind: AccountCliKind.opencode, prompt: 'Hello',
    ), ['run', '--format', 'json', 'Hello']);
  });

  test('Qoder cumulative assistant events are deduplicated', () {
    final reader = AccountCliProtocol(AccountCliKind.qoder);
    final first = reader.parseLine(
      '{"type":"assistant","message":{"id":"a","content":'
      '[{"type":"text","text":"Hello"}]}}',
    );
    final second = reader.parseLine(
      '{"type":"assistant","message":{"id":"a","content":'
      '[{"type":"text","text":"Hello world"}]}}',
    );
    final duplicate = reader.parseLine(
      '{"type":"assistant","message":{"id":"a","content":'
      '[{"type":"text","text":"Hello world"}]}}',
    );
    expect(first?.text, 'Hello');
    expect(second?.text, ' world');
    expect(duplicate?.text, isNull);
  });

  test('Qoder tool and session updates have structured events', () {
    final reader = AccountCliProtocol(AccountCliKind.qoder);
    final event = reader.parseLine(
      '{"type":"assistant","message":{"id":"a","content":'
      '[{"type":"tool_use","name":"Read","input":{"path":"a.dart"}}]}}',
    );
    expect(event?.tool, 'Read');
    expect(event?.changedFiles, true);
    expect(reader.parseLine(
      '{"type":"result","session_id":"abc","is_error":false}',
    )?.sessionId, 'abc');
  });

  test('OpenCode JSON output translates text, tools and session ID', () {
    final reader = AccountCliProtocol(AccountCliKind.opencode);
    expect(reader.parseLine(
      '{"type":"text","sessionID":"ses_1",'
      '"part":{"type":"text","text":"Hello"}}',
    )?.text, 'Hello');
    expect(reader.parseLine(
      '{"type":"tool_use","sessionID":"ses_1",'
      '"part":{"type":"tool","tool":"bash","state":'
      '{"input":{"command":"git status"}}}}',
    )?.tool, 'bash');
    expect(reader.parseLine('not json'), isNull);
  });

  test('Prompt is a data argument, never a shell interpolation', () {
    const hostile = 'hello & del C:\\test & echo done';
    final args = accountCliArguments(
      kind: AccountCliKind.qoder,
      prompt: hostile,
    );
    expect(args[1], hostile);
    expect(args.length, 4);
  });
}
