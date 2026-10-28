# VietCode — QA & release-readiness audit

Audit date: 2026-10-28 (Vietnam). Branch:
feature/multi-provider-connect. Target: Windows x64, source-based OAuth
integrations, no 9Router/proxy/CLI external runtime dependency for native
providers.

## Acceptance criteria and observed scope

| Criterion | Status | Evidence / caveat |
|---|---|---|
| Windows VietCode installer | CI-gated | Flutter Windows release + Inno Setup EXE, packed as GitHub Actions artifact |
| Portrait on Windows app/installer | CI-gated | ICO generated at build time from assets/branding/vietcode_photo.jpg |
| Portrait in Flutter interface | Addressed | BaoCodeLogo widget uses VietCode app_icon.png; About dialog and Settings use same image |
| Portrait in website/PWA | Addressed | all four web/icons PNGs, favicon; manifest and tab title are VietCode |
| About branding and GitHub links | Addressed | About page/dialog display VietCode; repo and Star links target VietHann/baocode_v |
| Existing OAuth Codex / OpenRouter | Existing + added tests | Code and mocked callback tests exist; no live-account validation in CI |
| Qoder OAuth (no external CLI) | Implemented login + Upstreams account | PKCE device URL + direct Qoder polling + keychain. Linked account is visible in Upstreams but no model is selectable |
| Qoder model calls (no external CLI) | **Not complete** | COSY signing, authenticated model catalog, response stream and quotas not integrated in native kernel |
| GitHub Copilot OAuth (no external CLI) | Implemented | Browser device code, Copilot token exchange, model discovery, keychain, mocked HTTP tests |
| GitHub Copilot upstream and model selection | Implemented in source, real-account check pending | Account and actual discovered models populate Upstreams; enable/disable model toggles; shared model proxy forwards requests with refreshed OAuth token |
| Google Antigravity OAuth and inference | **Not complete** | Community flows use unofficial OAuth clients/private API; potential account restrictions |
| OpenCode Zen/Go account OAuth | **Not supported** | No verified subscription OAuth endpoint for third-party native use; product requires API-key workflows |
| No 9Router gateway | Satisfied | 9Router experiment bridge was deleted, release workflow fails if it reappears |
| No Qoder/OpenCode CLI runtime in default picker | Satisfied | Earlier CLI kernels remain in source but are not offered by KernelRegistry.all |
| Actual paid quota / live token validity | **Manual testing required** | GitHub CI has no users' accounts, cannot perform interactive browser authorization |

## Where signed-in accounts and models appear

**Settings → Models → Sign in with an account (OAuth)** starts a provider's
browser flow. On completion, VietCode opens that provider's **Upstreams**
detail page.

- **GitHub Copilot:** Under **Upstreams → GitHub Copilot**, its GitHub account
  is listed and **Models** shows the actual IDs returned by the authenticated
  catalog. Enable a model checkbox to expose it in the global model picker.
  Refresh models in the account section to obtain a current catalog. The
  shared model proxy automatically refreshes the short-lived Copilot model
  token and calls `api.githubcopilot.com` directly. No external CLI/gateway.
  If the account has no models/quota or discovery failed, the account still
  appears but **no fabricated model** is offered.
- **Qoder:** Under **Upstreams → Qoder (account only)**, the signed-in email
  or account ID is visible, while model selection stays disabled until the
  proprietary COSY transport has a working integration. Having a Qoder
  OAuth token does *not* enable model requests.
- **OpenRouter:** OAuth sign-in now attempts to fetch real model IDs
  immediately. Models are initially unchecked; use Upstreams → OpenRouter
  to enable the ones required. A failure leaves Fetch available to retry.
- **Codex:** Continues using its original integrated account/model UI.

The old standalone `GitHub Copilot (Direct)` agent is removed from the
default kernel picker to avoid two conflicting places for the same account.
The existing Copilot standalone kernel source is retained only for
compatibility and tests.

## Automated release gate

The Windows pipeline must complete **all** of the following before shipping:
1. Flutter pub dependencies resolve
2. OpenRouter/Qoder/GitHub device OAuth and direct HTTP transport tests
3. Flutter kernel event lifecycle and conversation tests
4. Dart analyzer on modified authentication, settings and branding sources
5. Portrait source converted to Windows, About, macOS, PWA icons
6. Explicit assertions that the experimental 9Router gateway was not included
7. Flutter x64 release build, Windows executable and Inno Setup installer
8. Upload installer artifact, verify it is not expired, inspect actual PE EXE

**Important:** CI green means the packaged code compiles and the injected HTTP
contract tests pass. It does NOT certify a user subscription, unofficial
upstream compatibility, Qoder model execution, Antigravity or a complete
file-editing coding agent.

## Manual release checklist (needs a consenting test account)

- Install on a clean Windows x64 machine (not only an upgrade).
- Check app and installer icons, Start Menu, taskbar and desktop shortcuts,
  browser-host integration and context-menu commands.
- Verify no Qoder, OpenCode, Node.js or 9Router process is required to reach
  Qoder device login or Copilot login.
- GitHub Copilot: use a throwaway/authorized test account; finish device
  authorization; verify account has paid/free Copilot eligibility, load the
  current model catalog, click "Test model (uses quota)", select the direct
  kernel, run two text turns, stop a long turn, sign out.
- Qoder: verify native device browser flow and encrypted token persistence;
  **do not advertise Qoder model usage** until signed inference is available.
- Codex / OpenRouter: test real sign-in, callback, fail/cancel and one model
  request, since these can regress independently of this fork.
- Verify token files cannot be read from settings.json, and that no OAuth
  callback/token appears in application debug logs.
- Remove or expire a user's session to check errors are explicit and
  recoverable.
- Run real Windows installer upgrade/uninstall and verify compatibility
  with original BaoCode browser host and URL scheme.

## Remaining release blockers for the *full requested scope*

1. Native Qoder model protocol (COSY header signing, catalog and SSE parsing).
2. Native Antigravity OAuth plus authenticated inference, with user-visible
   warning on unofficial Google account-access risk and real tests.
3. OpenCode Zen/Go do not offer the kind of publicly documented subscription
   OAuth integration originally requested; cannot honestly claim support.
4. The direct Copilot kernel cannot edit files, run commands or use MCP;
   those capabilities need a separate, permission-aware IDE agent layer.
5. No real OAuth/account smoke tests have run in CI. Real end-to-end tests
   must be performed before the draft PR is merged as production-ready.

## References and licensing

- https://github.com/decolua/9router (MIT); the license notice was added in
  docs/licenses/9router-MIT.txt. Its code was a *reference*, not a bundled
  9Router service.
- https://github.com/anomalyco/opencode
- https://github.com/cubk1/qoder2api
- https://github.com/NoeFabris/opencode-antigravity-auth
- https://docs.qoder.com/cli/sdk/how-it-works

The client-identification values used by community integrations may be
restricted/changed by providers. Never treat another product's OAuth
client ID or secret as a stable, officially sanctioned VietCode API grant.
