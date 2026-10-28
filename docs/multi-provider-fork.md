# VietCode — Native account OAuth implementation

**Requirement:** VietCode connects to accounts and model services itself, with
no externally installed Qoder CLI, OpenCode CLI, Node.js, 9Router process or
third-party localhost gateway required for the native flows.

## Actual integration status (do not treat login as inference)

| Provider | Browser sign-in | Automatic account storage | Models / inference | Status |
| --- | --- | --- | --- | --- |
| ChatGPT Codex | Built-in OAuth PKCE | Existing OS keychain | Existing Codex proxy | Pre-existing functionality; verify live |
| OpenRouter | Official OAuth PKCE | OS keychain | Existing OpenAI-compatible proxy | Implemented; verify live |
| Qoder | Direct device OAuth PKCE; poll Qoder | OS keychain | **Not yet:** Qoder's proprietary COSY request signing / model and SSE protocols | Login implemented and unit-tested, model calls incomplete |
| GitHub Copilot | Native GitHub device OAuth | OS keychain | Native Copilot model catalog and chat completions (no external CLI) | Implemented and mock-tested, real subscription smoke test pending |
| OpenCode Zen / Go | **No documented subscription OAuth grant to third parties** | — | Official provider currently requires an API key | No misleading "OAuth" login |
| Google Antigravity | Community and 9Router Google OAuth experiments | — | Proprietary and unstable Google Cloud Code endpoints | **Not implemented natively**; account restriction risk |
| Qoder CLI / OpenCode CLI / Antigravity OpenCode plugin | External CLI/agent sessions | CLI-managed | Previously implemented but not native | Hidden from the default agent selector |

The GitHub Copilot direct kernel is an experimental chat-only provider (text,
model discovery, text replies, session conversation memory). It is *not* a
complete coding agent with file edits, shell tools, MCP or streaming tool
approvals; the user must not assume it has changed project files.

The new Qoder login is **genuinely native**: VietCode generates PKCE,
machine ID and nonce, navigates to qoder.com/device/selectAccounts, polls
openapi.qoder.sh/api/v1/deviceToken/poll, reads Qoder's profile and saves the
session in the OS keychain. It does not need an executable downloaded from
Qoder. The account session is NOT automatically compatible with BaoCode's
existing OpenAI/Anthropic upstream protocol. It is not exposed as a working
model until inference has been added and tested.

## Examined repositories and design rationale

1. **decolua/9router** — https://github.com/decolua/9router
   MIT License. Reviewed:
   - src/lib/oauth/services/qoder.js
   - src/lib/oauth/providers/qoder.js
   - src/lib/oauth/providers/github.js
   - src/lib/oauth/providers/antigravity.js
   - open-sse/executors/qoder.js
   - open-sse/executors/antigravity.js
   - open-sse/providers/registry/{qoder,github,antigravity,opencode}.js
   - open-sse/shared/qoder/{cosy,encoding,sse}.js

   **Only protocol behavior was ported to Dart. No 9Router server,
   credentials store, package, or hosted endpoint is called by VietCode.**
   License attribution remains in native provider source files.

2. **CLIProxyAPI / CLIProxyAPIPlus** — the Qoder COSY protocol research
   and signing details in 9Router trace back to these implementations.
   Before copying any future code, inspect the exact project's license.
3. **cubk1/qoder2api / Zhengyuuuui/qoder2api** — community work on
   Qoder's account protocol. These projects can break on upstream changes.
4. **anomalyco/opencode** — https://github.com/anomalyco/opencode
   Auth in OpenCode is per provider; the "OpenCode Zen" and "OpenCode Go"
   account flow currently gives a key to paste into the client.
5. **NoeFabris/opencode-antigravity-auth** and community forks — unofficial
   Google-account integration with notices about account restrictions.
   Authentication is not equivalent to a Google-approved third-party API.
6. **Qoder Agent SDK** — https://docs.qoder.com/cli/sdk/how-it-works
   Official embedding still runs a *local qodercli subprocess* internally,
   which would not meet the no-CLI dependency requirement.

## Security & compatibility

- OAuth tokens stored in SecretStore, never in settings.json.
- HTTP is allowed only for **127.0.0.1 mock test servers**; real provider
  API endpoints use HTTPS.
- Qoder device login has cancellation, poll timeout, and PKCE nonce.
- GitHub Copilot device OAuth verifies actual model-token exchange and
  lists account model IDs before the UI claims active model access.
- Never assume an OAuth login grants a paid plan or free model quota.
- GitHub Copilot uses unofficial model endpoints; they can change and may
  restrict third-party use.
- No provider should be presented as connected just because its login
  webpage opened.
- No 9Router process, request, config or localhost port 20128 is used.

## Build

GitHub Actions on feature/multi-provider-connect runs pure-Dart protocol
tests, Flutter adapter tests, dart analyzer, the Flutter Windows release
build, Python/Pillow branding conversion from the user's photo and an
Inno Setup installer:

    VietCode-1.7.0-setup.exe

VietCode.exe is the public-facing Windows shortcut; baocode.exe remains
inside for native browser bridge and auto-update compatibility.

Unverified: interactive Qoder and GitHub logins, live model quota, and
complete IDE coding tasks with the newly built native adapters. These
cannot be simulated by CI and require real user/account smoke tests.
