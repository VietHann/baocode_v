# BaoCode account sign-in: Codex, OpenRouter, Qoder, OpenCode and Antigravity

This fork integrates *account-based* authentication. Qoder/OpenCode are native
coding-agent kernels and are **not** API endpoints masquerading as OAuth.
They use the official local CLI's saved OAuth session; BaoCode never opens
their credential file or collects a subscription token.

## Select a runtime

Start a **new chat**, open its coding-agent/kernel selector, and choose:
- Claude Code (existing BaoCode agent)
- Qoder (official signed-in local Qoder CLI)
- OpenCode (official signed-in local OpenCode CLI)
- Antigravity (community plugin installed by the user in OpenCode)

The model picker offers a default tier plus detected model IDs from
qoder --list-models or opencode models. For Antigravity only Google models
advertised by opencode models google are offered. Detection is opportunistic:
if no CLI or login is available, you will see the default/seed options and a
sign-in error when the first task runs.

Qoder/OpenCode sessions are separate coding agents, each with its own tools,
configuration, MCP, and tool permissions. Their conversation stream displays
in BaoCode, but tool approvals are not translated to BaoCode dialogs yet.
The upstream CLI keeps its default permission policy; BaoCode never sets
the OpenCode --auto flag or bypasses security dialogs. Run on a trusted,
local workspace. The integration currently does not run a remote agent on
an SSH host. Images are not forwarded to the CLI in this first version.

## Qoder OAuth login (official)

1. Install Qoder CLI following https://docs.qoder.com/cli/installation
2. Settings > Models > Qoder > Sign in with Qoder (Windows). This opens an
   interactive terminal running qoder. Finish the official account login.
3. Start a new BaoCode chat and choose the Qoder kernel.
4. Select the Qoder model from the model picker or leave Default.

The adapter launches qoder -p with --output-format stream-json and optionally
--model and --session-id. Qoder manages its own account authentication,
credit limits, command tools, and session storage.

References:
- https://docs.qoder.com/cli/run-in-scripts
- https://docs.qoder.com/cli/model
- https://docs.qoder.com/cli/sdk/authentication
- https://github.com/QoderAI/qoder-agent-sdk-samples
- https://github.com/QoderAI/Qoderian

The Agent SDK is another supported approach; this integration uses the
official CLI's documented headless JSON stream so no separate Node runtime
or SDK download is bundled into the Windows installer.

## OpenCode provider OAuth login (official client)

1. Install OpenCode: https://opencode.ai/docs
2. Settings > Models > OpenCode > Open OAuth login. The official command
   opencode auth login runs in an interactive terminal.
3. Pick a provider and its OAuth method if offered; some integrations only
   accept API keys, and this fork does not claim otherwise.
4. Check with opencode auth list and opencode models.
5. Start a BaoCode chat and choose the OpenCode kernel. The model picker
   picks IDs in provider/model form for the signed-in OpenCode account.

The adapter launches opencode run --format json with --model and --session
when a session has been returned. It does not copy or export OpenCode keys.
Never check auth files into Git.

References:
- https://dev.opencode.ai/docs/cli/
- https://dev.opencode.ai/docs/server/
- https://github.com/anomalyco/opencode

## Google Antigravity community OAuth — optional and risky

This is NOT an official Google sign-in for third-party apps. Community authors
warn that their plugin may violate Google's terms and accounts may be
suspended or shadow-banned. BaoCode DOES NOT automatically install the
plugin or copy/reuse Google's private credentials or endpoints. Only enable
this if you understand and accept the independent plugin's risks.

To opt in:
1. Install and sign in to the official OpenCode CLI.
2. Review the plugin source and installation instructions:
   https://github.com/zeklop/opencode-antigravity-auth
3. Add the plugin to your own ~/.config/opencode/opencode.json as
   documented by that plugin. Do not put tokens in BaoCode configuration.
4. Run opencode auth login, choose Google Antigravity from the plugin,
   finish browser OAuth, and configure the plugin's models.
5. Verify that opencode models google lists the Antigravity model IDs.
6. In BaoCode, choose the **Antigravity (community)** kernel and pick a
   Google model from the list. Its runtime is still OpenCode.

Original historical implementation:
https://github.com/NoeFabris/opencode-antigravity-auth (archived in 2026)
Community maintained alternatives:
https://github.com/vibheksoni/opencode-antigravity-auth
https://github.com/andyvandaric/opencode-ag-auth

These repositories are third parties; BaoCode does not endorse them.
Do not attempt to circumvent account bans, quotas, or provider restrictions.

## ChatGPT Codex and OpenRouter

- ChatGPT Codex: existing official browser OAuth PKCE in BaoCode
- OpenRouter: new official PKCE browser OAuth. It returns an account-scoped
  key, which BaoCode stores in the system keychain automatically after the
  login callback. No manual API key entry is required.

## Windows installer

The fork-specific GitHub Actions workflow builds a real Inno Setup EXE:
BaoCode-1.7.0-setup.exe (no signature). It uses the existing
tool/build_windows.dart packaging and downloads the official BaoCode remote
SSH helper metadata. Download from Actions > Artifacts; GitHub wraps the
installer in a ZIP for download. Extract and launch the setup.exe.

Qoder and OpenCode are external official CLIs and must be installed on the
user's machine to activate those kernels. They are not bundled into the EXE.

## Limits not covered by automated CI

CI tests parsing of documented JSON streams, arguments, session IDs and
OAuth callback security; it builds and packages the installer. It cannot
complete external browser OAuth or assert that a user account has paid model
quota. Test the real workflows on a Windows workstation before relying on
them for important coding changes.
