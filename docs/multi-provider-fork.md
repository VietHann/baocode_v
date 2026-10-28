# BaoCode — Account OAuth integration (fork)

This fork prioritizes account-based authentication, not API-provider preset lists.

## Integrated: ChatGPT Codex

Settings > Models > Sign in with an account > ChatGPT (Codex) > Add account.
This reuses the existing BaoCode native OAuth PKCE, refresh, account
switching and Codex proxy.

## Integrated: OpenRouter OAuth PKCE

Settings > Models > Sign in with an account > OpenRouter > Sign in.

- Launches the official OpenRouter authorization page in your browser.
- Uses random PKCE S256 verifier/challenge and an unpredictable state.
- Receives browser callback over IPv4 loopback on a dynamically assigned port.
- Rejects callbacks with mismatched state and exchanges the short-lived
  authorization code with the official HTTPS endpoint.
- Saves the issued account credential into the OS keychain automatically.
- Does not ask the user to copy/paste an API key.
- Opens the connected OpenRouter settings. Fetch models, enable desired
  ones, and test before using them in a BaoCode chat.
- Supports cancel, errors and timeout.

OpenRouter's officially documented OAuth produces a user-scoped,
revocable API key after authorization. This is NOT a ChatGPT-style
access/refresh-token grant. OpenRouter model usage requires account credits.

Source: https://openrouter.ai/docs/guides/overview/auth/oauth

The login handshake is covered by an offline integration test with a local
mock token endpoint. Live sign-in requires the user's own account.

## Not integrated yet

### Qoder account login

The Qoder CLI supports native browser login. Qoder's official Agent SDK
can reuse that exact signed-in session with qodercliAuth(), no API key.
However, it runs a full Qoder agent, rather than exposing an
OpenAI-compatible inference backend. BaoCode needs a separate agent
adapter supporting sessions, streaming events, permissions, and cancellation.

References:
- https://docs.qoder.com/cli/authentication
- https://docs.qoder.com/cli/sdk/authentication
- https://docs.qoder.com/cli/sdk/how-it-works

### OpenCode OAuth providers

OpenCode supports provider OAuth within its client and exposes an official
headless agent server with an HTTP/SDK interface. BaoCode would need an
OpenCode agent-runtime adapter; a generic OpenCode Zen/Go subscription
OAuth for arbitrary third-party model inference is not documented.

References:
- https://opencode.ai/docs/providers
- https://dev.opencode.ai/docs/server/

### Google Antigravity

Open-source third-party Antigravity OAuth plugins exist. Their authors
warn of unofficial endpoints, ToS restrictions and account suspensions.
This fork does not copy browser cookies or private API client tokens, and
does not claim authorized third-party account login.

References:
- https://github.com/NoeFabris/opencode-antigravity-auth
- https://github.com/JoshRob297/opencode-antigravity-auth

## Architecture follow-up

Do not conflate three separate concepts:

- AccountAuthAdapter: browser/device login, status, session lifecycle
- AgentRuntimeAdapter: agent streams, tools, approvals, resume and cancel
- ModelUpstreamAdapter: compatible inference endpoints and routing

Account login alone does not make a foreign agent run inside BaoCode.
Only surface an OAuth sign-in option after an authorized integration exists.

## Build

The fork-specific GitHub workflow Windows x64 (account OAuth fork) builds
and uploads a portable ZIP artifact named BaoCode-oauth-windows-x64.
Extract all files; baocode.exe alone lacks the required runtime.
No upstream publishing secrets, no installer-signing claims.
