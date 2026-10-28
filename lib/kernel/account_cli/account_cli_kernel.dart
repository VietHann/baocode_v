import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../chat/chat_models.dart';
import '../agent_kernel.dart';
import '../kernel_event.dart';
import '../kernel_types.dart';
import 'account_cli_protocol.dart';

/// Local authenticated Qoder/OpenCode runtime.
///
/// Unlike an API proxy, this executes the official coding agent on the
/// project's machine using that CLI's own logged-in account. Tool execution
/// is performed by the upstream agent; this adapter translates its JSONL
/// stream to BaoCode's UI. The credentials are never read by BaoCode.
///
/// For now this is local-only, with one process per turn and no forwarding
/// of interactive CLI tool-approval dialogs. Defaults do NOT auto-approve
/// operations (OpenCode --auto is intentionally not passed).
class AccountCliKernel
    with KernelEventSource
    implements AgentKernel, SelectsModel {
  AccountCliKernel(this.descriptor, this.context, this.kind) {
    final chosen = context.settings[KernelChoiceKind.model.name];
    model = LocalChoice(
      _initialModels,
      onChanged: (_) => emitInfoChanged(),
    );
    if (chosen != null && _initialModels.any((item) => item.id == chosen)) {
      model.select(chosen);
    }
  }

  @override
  final KernelDescriptor descriptor;
  final KernelContext context;
  final AccountCliKind kind;

  @override
  late final LocalChoice model;

  @override
  KernelHealth get health => _health;
  KernelHealth _health = KernelHealth.ready;

  @override
  String? get sessionId => _sessionId;
  String? _sessionId;

  Process? _process;
  Future<void>? _task;
  bool _disposed = false;
  String? _activeTurn;
  final Set<String> _sent = {};
  int _itemCounter = 0;
  int _offset = 0;
  String? _assistantItem;
  DateTime? _startedAt;

  @override
  Future<void> get stopped => _task ?? Future<void>.value();

  List<KernelOption> get _initialModels => [
    const KernelOption(
      'default', 'Default / account selection',
      Icons.auto_awesome_rounded, 'Use the model set by your logged-in CLI',
    ),
    if (kind == AccountCliKind.qoder) ...[
      const KernelOption('auto', 'Qoder Auto', Icons.bolt_rounded,
          'Let Qoder choose the model'),
      const KernelOption('efficient', 'Qoder Efficient',
          Icons.bolt_rounded, 'Qoder efficient tier'),
      const KernelOption('performance', 'Qoder Performance',
          Icons.bolt_rounded, 'Qoder performance tier'),
    ],
    if (kind == AccountCliKind.antigravity) ...[
      const KernelOption(
        'google/antigravity-gemini-3.1-pro',
        'Antigravity Gemini 3.1 Pro',
        Icons.auto_awesome_rounded,
        'Requires the optional OpenCode Antigravity OAuth plugin',
        caution: true,
      ),
      const KernelOption(
        'google/antigravity-claude-sonnet-4-6-thinking',
        'Antigravity Claude Sonnet 4.6',
        Icons.auto_awesome_rounded,
        'Unofficial Google plugin; account restriction risk',
        caution: true,
      ),
    ],
  ];

  /// Discover account-enabled models from the official CLIs. A failed
  /// discovery does not prevent the default model from being used.
  @override
  void prepare() {
    if (_disposed) return;
    unawaited(_discoverModels());
  }

  Future<void> _discoverModels() async {
    final command = accountCliExecutable(kind);
    final args = kind == AccountCliKind.qoder
        ? ['--list-models']
        : kind == AccountCliKind.antigravity
            ? ['models', 'google']
            : ['models'];
    try {
      final process = await Process.start(
        command, args,
        workingDirectory: _validCwd,
        runInShell: Platform.isWindows,
      );
      final output = StringBuffer();
      final reading = process.stdout.transform(utf8.decoder).listen((chunk) {
        if (output.length < 300000) output.write(chunk);
      });
      final errors = process.stderr.drain<void>();
      final code = await process.exitCode.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
      await reading.cancel();
      await errors;
      if (code != 0 || _disposed) return;
      final found = <KernelOption>[];
      final lines = output.toString().split('\n');
      for (final raw in lines) {
        final line = raw.trim().split(RegExp(r'\s+')).first;
        if (line.isEmpty || line.length > 150) continue;
        if (line.startsWith('{') || line.startsWith('[')) continue;
        if (kind == AccountCliKind.antigravity &&
            !line.contains('antigravity')) {
          continue;
        }
        if (kind != AccountCliKind.qoder && !line.contains('/')) continue;
        if (found.any((item) => item.id == line)) continue;
        found.add(KernelOption(
          line, line, Icons.bolt_rounded,
          'Available through your signed-in account',
          caution: kind == AccountCliKind.antigravity,
        ));
        if (found.length >= 80) break;
      }
      if (found.isEmpty || _disposed) return;
      final picked = model.selected;
      model.options = [
        _initialModels.first,
        ...found,
      ];
      if (picked != null &&
          model.options.any((item) => item.id == picked)) {
        model.reported = picked;
      }
      emitInfoChanged();
    } on ProcessException {
      // The login/configuration UI explains which CLI to install.
    } on Object {
      // Models are optional; the user can use the CLI default.
    }
  }

  String? get _validCwd => context.cwd case final dir?
      when Directory(dir).existsSync() => dir;

  @override
  void send(KernelTurn turn) {
    if (_disposed || !_sent.add(turn.id)) return;
    if (_activeTurn != null) {
      emit(ItemUpserted(
        nextSeq, 'busy-' + turn.id,
        const AssistantTextItem(
          'This account agent is still running. Stop it before '
          'sending another message.',
        ),
      ));
      return;
    }
    _activeTurn = turn.id;
    _startedAt = DateTime.now();
    _assistantItem = null;
    _offset = 0;
    emit(TurnStarted(nextSeq, turn.id));
    emit(ItemUpserted(
      nextSeq, turn.id,
      UserMessageItem(text: turn.text, images: turn.images),
    ));
    _task = _run(turn);
  }

  Future<void> _run(KernelTurn turn) async {
    final parser = AccountCliProtocol(kind);
    final text = [
      turn.text,
      ...turn.notes,
      if (turn.images.isNotEmpty)
        'Attached image bytes are not yet forwarded by this CLI adapter.',
    ].where((part) => part.trim().isNotEmpty).join('\n\n');
    final args = accountCliArguments(
      kind: kind,
      prompt: text,
      model: model.selected,
      sessionId: _sessionId,
    );
    var exit = -1;
    final errors = StringBuffer();
    try {
      final process = await Process.start(
        accountCliExecutable(kind), args,
        workingDirectory: _validCwd,
        runInShell: Platform.isWindows,
      );
      if (_disposed || _activeTurn != turn.id) {
        process.kill();
        await process.exitCode;
        return;
      }
      _process = process;
      final stderr = process.stderr.transform(utf8.decoder).listen((text) {
        // Do not copy full stderr; it could contain sensitive details.
        if (errors.length < 1000) errors.write(text);
      });
      final stdout = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in stdout) {
        if (_activeTurn != turn.id || _disposed) break;
        final event = parser.parseLine(line);
        if (event == null) continue;
        if (event.sessionId case final session? when session.isNotEmpty) {
          _sessionId = session;
        }
        if (event.tool case final tool?) {
          emit(ItemUpserted(
            nextSeq, 'tool-' + (++_itemCounter).toString(),
            ToolCallItem(kind: ToolKind.other, target: tool, label: tool),
          ));
          if (event.changedFiles) emit(FilesMayHaveChanged(nextSeq));
        }
        if (event.text case final fragment? when fragment.isNotEmpty) {
          _append(fragment);
        }
        if (event.error case final failure?) {
          _append('\n\nAgent reported: ' + failure);
        }
      }
      exit = await process.exitCode;
      await stderr.cancel();
      if (exit != 0 && _activeTurn == turn.id) {
        // Never expose raw stderr or serialized auth errors to chat.
        _append('\n\nThe ' + descriptor.label
            + ' command exited with code ' + exit.toString()
            + '. Check your CLI installation and account sign-in.');
      }
    } on ProcessException {
      _health = KernelHealth(
        KernelHealthStatus.failed,
        message: 'Cannot start ' + accountCliExecutable(kind),
        detail: 'Install the official CLI, then sign in using its '
            'own account login.',
      );
      emitInfoChanged();
      _append('\n\n' + descriptor.label +
          ' CLI was not found. Install it and sign in first.');
    } on Object {
      _append('\n\nThe authenticated CLI failed. Check its sign-in '
          'and model configuration in the terminal.');
    } finally {
      _process = null;
      if (_activeTurn == turn.id) {
        _finish(turn.id, interrupted: false);
      }
    }
  }

  void _append(String fragment) {
    if (_disposed) return;
    final id = _assistantItem ??=
        'reply-' + (++_itemCounter).toString();
    if (_offset == 0) {
      emit(ItemUpserted(
        nextSeq, id, const AssistantTextItem(''), streaming: true,
      ));
    }
    emit(TextDelta(nextSeq, id, _offset, fragment));
    _offset += fragment.length;
  }

  void _finish(String turn, {required bool interrupted}) {
    if (_activeTurn != turn) return;
    if (_assistantItem case final id?) {
      emit(ItemCompleted(nextSeq, id));
    }
    _activeTurn = null;
    emit(TurnEnded(
      nextSeq, turn,
      interrupted: interrupted,
      worked: DateTime.now().difference(_startedAt ?? DateTime.now()),
    ));
    emit(FilesMayHaveChanged(nextSeq));
  }

  @override
  void answer(String requestId, InteractionAnswer answer) {
    // Interactive tool approvals are not supported in headless CLI mode.
  }

  @override
  void cancel() {
    _process?.kill();
    if (_activeTurn case final turn?) {
      _finish(turn, interrupted: true);
    }
  }

  @override
  void restart() {
    _health = KernelHealth.ready;
    emitInfoChanged();
    prepare();
  }

  @override
  void release() {
    if (_activeTurn == null) _process?.kill();
  }

  @override
  void dispose() {
    if (_disposed) return;
    cancel();
    _disposed = true;
    closeEvents();
  }
}
