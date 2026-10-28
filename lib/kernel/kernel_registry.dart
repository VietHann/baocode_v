import 'package:flutter/material.dart';

import 'agent_kernel.dart';
import 'account_cli/account_cli_kernel.dart';
import 'account_cli/account_cli_protocol.dart';
import 'claude_code/claude_code_kernel.dart';
import '../remote/remote_claude.dart';

/// The kernels the user can pick from. Another kernel is an adapter and a
/// line here.
abstract final class KernelRegistry {
  static final KernelDescriptor claudeCode = KernelDescriptor(
    id: 'claude-code',
    label: 'Claude Code',
    icon: Icons.auto_awesome_rounded,
    description: 'Anthropic’s coding agent',
    create: (context) => ClaudeCodeKernel(
      claudeCode,
      context,
      // On the project's host: this machine, or a remote one's.
      start: startClaude,
      readHistoryPage: readClaudeHistoryPage,
      readGoal: readClaudeGoal,
      forkSession: forkClaudeSession,
      usageOffBy: () => claudeUsageOffByAt(context.cwd),
      rejectTooOld: rejectTooOldClaude,
    ),
    catalog: const ClaudeCatalog(),
  );

  /// These agents reuse the local CLI's own OAuth/subscription login.
  /// They run as independent kernels, not pretend API-model upstreams.
  static final KernelDescriptor qoder = KernelDescriptor(
    id: 'qoder-cli',
    label: 'Qoder',
    icon: Icons.code_rounded,
    description: 'Qoder Agent (signed in using qoder CLI)',
    create: (context) => AccountCliKernel(qoder, context, AccountCliKind.qoder),
  );

  static final KernelDescriptor openCode = KernelDescriptor(
    id: 'opencode-cli',
    label: 'OpenCode',
    icon: Icons.terminal_rounded,
    description: 'OpenCode Agent (uses local provider OAuth sessions)',
    create: (context) => AccountCliKernel(
      openCode, context, AccountCliKind.opencode,
    ),
  );

  /// Optional community OpenCode OAuth integration; not a Google-approved
  /// Antigravity API. Requires explicit plugin setup in the user's CLI.
  static final KernelDescriptor antigravity = KernelDescriptor(
    id: 'antigravity-opencode',
    label: 'Antigravity (community)',
    icon: Icons.warning_amber_rounded,
    description: 'Unofficial OpenCode Google OAuth plugin — account risk',
    create: (context) => AccountCliKernel(
      antigravity, context, AccountCliKind.antigravity,
    ),
  );

  static List<KernelDescriptor> _all = [
    claudeCode, qoder, openCode, antigravity,
  ];

  static List<KernelDescriptor> get all => _all;

  /// Replaces the kernels on offer, e.g. with mock ones under test.
  static void use(List<KernelDescriptor> kernels) => _all = kernels;
}
