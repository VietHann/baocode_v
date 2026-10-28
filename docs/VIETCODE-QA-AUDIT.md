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
| Qoder OAuth (no external CLI) | Implemented login | PKCE device URL + direct Qoder polling + keychain storage, tested with HTTP mock |
| Qoder model calls (no external CLI) | **Not complete** | COSY signing, authenticated model catalog, response stream and quotas not integrated in native kernel |
| GitHub Copilot OAuth (no external CLI) | Implemented | Browser device code, Copilot token exchange, model discovery, keychain, mocked HTTP tests |
| GitHub Copilot model chat (no external CLI) | Implemented **text-only** | Native kernel, multi-turn and error handling tests; no IDE tools and no real user smoke test |
| Google Antigravity OAuth and inference | **Not complete** | Community flows use unofficial OAuth clients/private API; potential account restrictions |
| OpenCode Zen/Go account OAuth | **Not supported** | No verified subscription OAuth endpoint for third-party native use; product requires API-key workflows |
| No 9Router gateway | Satisfied | 9Router experiment bridge was deleted, release workflow fails if it reappears |
| No Qoder/OpenCode CLI runtime in default picker | Satisfied | Earlier CLI kernels remain in source but are not offered by KernelRegistry.all |
| Actual paid quota / live token validity | **Manual testing required** | GitHub CI has no users' accounts, cannot perform interactive browser authorization |

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
