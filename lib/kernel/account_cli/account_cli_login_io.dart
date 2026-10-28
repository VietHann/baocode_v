import 'dart:io';

enum AccountLoginKind { qoder, opencode, antigravity }

String loginCommand(AccountLoginKind kind) => switch (kind) {
  AccountLoginKind.qoder => 'qoder',
  AccountLoginKind.opencode => 'opencode auth login',
  AccountLoginKind.antigravity => 'opencode auth login',
};

/// Opens the official CLI's own interactive account sign-in in a terminal.
/// BaoCode never intercepts OAuth tokens or reads local credential files.
///
/// Community Antigravity plugin installation must be an explicit manual
/// choice; this function does not install plugins or modify configuration.
Future<bool> openAccountLoginTerminal(AccountLoginKind kind) async {
  if (!Platform.isWindows) return false;
  final command = loginCommand(kind);
  try {
    // The only commands here are fixed constants above, never user input.
    // PowerShell starts a fresh interactive cmd window. The OAuth callback
    // remains owned by the respective official CLI/plugin.
    final script = 'Start-Process -FilePath cmd.exe '
        '-ArgumentList ' + _psQuoted('/k ' + command);
    final process = await Process.start(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-Command', script],
    );
    final status = await process.exitCode;
    return status == 0;
  } on ProcessException {
    return false;
  }
}

String _psQuoted(String text) => "'" + text.replaceAll("'", "''") + "'";
