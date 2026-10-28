import 'dart:async';

import 'package:flutter/material.dart';

import '../../chat/chat_models.dart';
import '../../models/copilot_direct.dart';
import '../agent_kernel.dart';
import '../kernel_event.dart';
import '../kernel_types.dart';

/// Direct GitHub Copilot model kernel. Auth and calls are owned by VietCode:
/// no OpenCode/9Router/gh/Node executable is launched.
/// Unlike a full coding agent, this initial kernel offers chat only.
/// It never claims to have edited local project files or executed commands.
class CopilotDirectKernel
    with KernelEventSource
    implements AgentKernel, SelectsModel {
  CopilotDirectKernel(this.descriptor, this.context) {
    model = LocalChoice(
      [
        const KernelOption(
          'gpt-5-mini',
          'GPT-5 Mini',
          Icons.bolt_rounded,
          'GitHub Copilot subscription model',
        ),
      ],
      onChanged: (_) => emitInfoChanged(),
    );
  }

  @override
  final KernelDescriptor descriptor;
  final KernelContext context;
  final CopilotDirect _provider = CopilotDirect();

  @override
  late final LocalChoice model;

  KernelHealth _health = KernelHealth.ready;
  @override
  KernelHealth get health => _health;
  @override
  String? get sessionId => null;

  bool _disposed = false;
  String? _activeTurn;
  Future<void>? _task;
  final _sent = <String>{};
  final List<Map<String, Object?>> _messages = [];
  int _itemCounter = 0;
  DateTime? _startedAt;

  @override
  Future<void> get stopped => _task ?? Future<void>.value();

  @override
  void prepare() {
    if (!_disposed) unawaited(_loadModels());
  }

  Future<void> _loadModels() async {
    try {
      final account = await _provider.saved();
      if (account == null || _disposed) return;
      final discovered = await _provider.models(account);
      if (discovered.isEmpty || _disposed) return;
      final selected = model.selected;
      model.options = [
        for (final id in discovered)
          KernelOption(
            id, id, Icons.auto_awesome_rounded,
            'Available on signed-in GitHub Copilot account',
          ),
      ];
      if (selected != null &&
          model.options.any((item) => item.id == selected)) {
        model.reported = selected;
      }
      emitInfoChanged();
    } on Object {
      // Lack of quota/model discovery must not crash the app.
    }
  }

  @override
  void send(KernelTurn turn) {
    if (_disposed || _sent.contains(turn.id)) return;
    if (_activeTurn != null) {
      // An overlapping turn must have a matching start/end event, not an
      // orphan message that leaves its user bubble spinning indefinitely.
      _sent.add(turn.id);
      emit(TurnStarted(nextSeq, turn.id));
      final noticeId = 'busy-' + turn.id;
      emit(ItemUpserted(
        nextSeq, noticeId,
        const AssistantTextItem(
          'Copilot is still answering. Stop the active reply first.',
        ),
      ));
      emit(ItemCompleted(nextSeq, noticeId));
      emit(TurnEnded(nextSeq, turn.id, interrupted: true));
      return;
    }
    _sent.add(turn.id);
    _activeTurn = turn.id;
    _startedAt = DateTime.now();
    emit(TurnStarted(nextSeq, turn.id));
    emit(ItemUpserted(
      nextSeq, turn.id,
      UserMessageItem(text: turn.text, images: turn.images),
    ));
    _task = _run(turn);
  }

  Future<void> _run(KernelTurn turn) async {
    final messageId = 'copilot-' + (++_itemCounter).toString();
    try {
      final account = await _provider.saved();
      if (account == null) {
        throw const CopilotDirectException(
          'GitHub Copilot is not connected. Open Settings → Models '
          'and sign in with GitHub using the device OAuth code.',
        );
      }
      // Never silently discard an attachment while presenting a normal
      // answer. This text-only adapter has no image transport yet.
      if (turn.images.isNotEmpty) {
        throw const CopilotDirectException(
          'GitHub Copilot Direct currently supports text only. '
          'Remove image attachments to send this turn.',
        );
      }
      final user = [
        turn.text,
        ...turn.notes,
      ].where((s) => s.trim().isNotEmpty).join('\n\n');
      final messages = [
        ..._messages,
        <String, Object?>{'role': 'user', 'content': user},
      ];
      final text = await _provider.complete(
        account,
        model: model.selected ?? 'gpt-5-mini',
        messages: messages,
      );
      if (_disposed || _activeTurn != turn.id) return;
      emit(ItemUpserted(
        nextSeq, messageId, AssistantTextItem(text),
      ));
      emit(ItemCompleted(nextSeq, messageId));
      _messages
        ..add(<String, Object?>{'role': 'user', 'content': user})
        ..add(<String, Object?>{'role': 'assistant', 'content': text});
    } on Object catch (error) {
      if (_disposed || _activeTurn != turn.id) return;
      final message = error is CopilotDirectException
          ? error.message
          : 'Copilot request failed. Check account and network.';
      emit(ItemUpserted(
        nextSeq, messageId, AssistantTextItem(message),
      ));
      emit(ItemCompleted(nextSeq, messageId));
    } finally {
      if (!_disposed && _activeTurn == turn.id) {
        _finish(turn.id, interrupted: false);
      }
    }
  }

  void _finish(String turn, {required bool interrupted}) {
    if (_activeTurn != turn) return;
    _activeTurn = null;
    emit(TurnEnded(
      nextSeq, turn,
      interrupted: interrupted,
      worked: DateTime.now().difference(_startedAt ?? DateTime.now()),
    ));
  }

  @override
  void answer(String requestId, InteractionAnswer answer) {}

  @override
  void cancel() {
    if (_activeTurn case final id?) _finish(id, interrupted: true);
    // The response is discarded on cancellation. HTTP requests may still
    // complete because this experimental adapter uses non-streaming calls.
  }

  @override
  void restart() {
    _health = KernelHealth.ready;
    emitInfoChanged();
    prepare();
  }

  @override
  void release() {}

  @override
  void dispose() {
    if (_disposed) return;
    cancel();
    _disposed = true;
    closeEvents();
  }
}
