# Multi-provider quick connect (VietHann fork)

BaoCode now offers Settings > Models > Connect AI service. It creates regular
upstreams using the existing Anthropic and OpenAI proxy, rather than scraping
browser cookies, borrowing auth files from another app, or imitating unofficial
subscription clients.

## Authentication supported

| Type | Services | Login |
| --- | --- | --- |
| Account OAuth | ChatGPT (Codex) | Existing native sign-in and account management |
| Provider-issued API key | OpenCode Zen, OpenCode Go, OpenRouter, OpenAI API, Anthropic API, Gemini API, DeepSeek, Moonshot/Kimi, Mistral, Groq, Cerebras, xAI, Together AI, Fireworks AI | Open the provider's console, create an API key, enter it in BaoCode |
| Local, no key | Ollama, LM Studio, vLLM | Start the local server and fetch its models |

The key is stored in the OS keychain by the existing SecretStore, not in
settings.json. Each preset only saves a public base URL, the protocol and
optional starter model IDs.

To connect:

1. Open Settings > Models > Connect AI service > Choose service.
2. Choose an account, gateway, direct API or local server.
3. For ChatGPT choose Add account. For another provider click Open provider
   website, issue an API key, paste it into the provider page and save.
4. Fetch models or add models manually; test a model and select it.

OpenCode Zen uses the OpenAI Responses API. OpenCode Go supports OpenAI Chat
Completions, Responses and Anthropic Messages, with per-model protocols
configured for its starter models. New models may need their protocol edited
after import. Starter model IDs can change or be excluded from your plan.

## Explicit limitations

- Qoder Personal Access Tokens authenticate the official Qoder CLI, not a
  documented third-party inference API. Qoder model subscription sign-in
  inside BaoCode is NOT implemented.
- Antigravity third-party OAuth is NOT implemented. Community clients often
  use unofficial endpoints and may conflict with Google's terms.
- OpenCode is a client. This integration uses the documented OpenCode
  Zen/Go API keys, not arbitrary OpenCode local sessions or auth tokens.
- Having a ChatGPT/Claude consumer subscription does not automatically
  confer API key access. Provider billing, availability and limits apply.

## Sources

BaoCode upstream implementation:
- lib/models/upstream.dart
- lib/models/model_provider.dart
- lib/models/proxy/
- lib/models/codex/

Vendor documentation:
- https://opencode.ai/docs/zen/
- https://opencode.ai/docs/go/
- https://opencode.ai/docs/providers/
- https://docs.qoder.com/cli/authentication
- https://ai.google.dev/gemini-api/docs/openai
- https://api-docs.deepseek.com/
- https://openrouter.ai/developers
- https://docs.mistral.ai/
- https://console.groq.com/docs

## Windows executable

The fork-specific GitHub Actions workflow named Windows x64
(multi-provider fork) builds a Windows release bundle on a Windows runner.
Download the workflow artifact ZIP, unzip everything and run baocode.exe.
Keep the data folder and flutter_windows.dll alongside the executable.
This is a portable bundle, NOT a signed Windows installer.

To build locally on Windows:

    flutter pub get
    flutter test test/models/provider_presets_test.dart
    flutter build windows --release

The original release workflow requires BaoCode upstream publishing secrets.
This fork does not publish into BaoCode's release or update infrastructure.
