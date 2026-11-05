# SRT Generator: agent guide

macOS 26+ SwiftUI app (SwiftPM, no Xcode project) that turns audio or video into `.srt` subtitles with **local** speech
models (WhisperKit, FluidAudio/Parakeet). Swift 6.2 tools, Swift 5 language mode, Apple Silicon only.

## Commands

| Command | What it does |
|---|---|
| `make build` | Debug build of every target, including tests. Warnings are errors. |
| `make test` | Unit tests plus architecture tests (`swift test`) |
| `make lint` / `make format` | SwiftFormat and SwiftLint `--strict`: check / fix |
| `make coverage` | Tests plus the 100% SRTCore line-coverage gate (`scripts/coverage.sh --show-missing` lists gaps) |
| `make policy` | Network policy check (`scripts/check-network-policy.sh`) |
| `make ci` | All of the above, the same as CI |
| `make mutate` | Mutation testing (slow, on demand) |
| `make app` / `make dmg` | `dist/SRT Generator.app` / DMG plus `.sha256` |

Tools are pinned in `scripts/bootstrap-tools.sh` and live in `.tools/bin` (`make tools`). Don't use Homebrew versions.

## Architecture (details: docs/ARCHITECTURE.md, decisions: docs/adr/)

- `SRTCore`: domain, ViewModels (`AppState`, `ModelManager`, `JobQueue`) and services. Apple frameworks only; no SwiftUI/AppKit.
- `SRTEngines`: thin WhisperKit/FluidAudio adapters behind `ModelProvider` / `SpeechEngine`.
- `SRTGenerator`: Views, CLI, `TranslationBridge`, and `LiveDependencies.swift`, the **single composition root**.
- MVVM: no business logic in Views. ViewModels are `@MainActor @Observable` and don't import view types.
- Every dependency is a protocol in `SRTCore/Services/Protocols.swift`, injected through `AppDependencies`.
  No singletons; only `LiveDependencies` constructs concrete adapters.
- SRP means one reason to change per type, not one method per type.
- These rules are enforced by `Tests/ArchitectureTests` and SwiftLint custom rules. If a rule blocks you, ask; don't
  add exceptions.

## Network policy (non-negotiable)

- The **only** network use is downloading models from the built-in list (`ModelCatalog.swift`) from the hosts in
  `config/allowed-hosts.txt`. All processing is on-device.
- Video, audio, samples, transcripts, subtitles, file names and settings must **never** reach any network API.
- All networking stays inside the model-download dependencies (WhisperKit, FluidAudio), reached only through
  `ModelProvider` in `SRTEngines`. Our own code never uses URLSession, URLRequest, Network.framework, WebKit or sockets.
- Never add telemetry, analytics, crash reporting, remote config, update checks, accounts or any new network
  feature without explicit approval from the maintainer.
- New dependencies need a justification, must not access the network, and go in `config/allowed-dependencies.txt`.
- **Ask first** before editing entitlements, `config/allowed-hosts.txt`, `config/allowed-dependencies.txt`,
  `config/network-exceptions.txt` or `ModelCatalog.swift`.

## Model downloads

Target behavior (partly provided by WhisperKit/FluidAudio today; see the "Model storage" section in
docs/ARCHITECTURE.md for gaps): verify SHA-256 against the model list, resume interrupted downloads, check free disk
space first, store under Application Support, support cancel, and show clear user-facing errors. Changes here touch
user data and the model list, so propose them before implementing.

## Testing rules

- Swift Testing only (`@Test`, `#expect`, `#require`). Every test makes meaningful assertions about behavior, not
  implementation details.
- Use protocol-based fakes (`Tests/SRTCoreTests/Support/Fakes.swift`) and tiny generated fixtures (`MediaFixtures`).
- Tests **never** touch the real network or download real models. Use fakes or a `URLProtocol` stub serving local files.
- Deterministic: no new sleeps or timing assumptions. Make the fake hold the state you want to observe.
- Never force-unwrap in tests; use `try #require`. Never use `UserDefaults.standard`.
- SRTCore stays at 100% line coverage. Fill gaps with real tests, never with exclusions or tricks.

## Definition of done

`make ci` is green: build with no warnings, all tests pass, lint clean, coverage gate met, network policy passes.
Don't change app behavior unless asked; if a fix needs a production change, say so and ask.

## Workflow

- Plan before large or cross-module changes, and share the plan first.
- Small, focused commits and PRs. Branch off `main`; never force-push.
- Run `make test` (or `make ci`) before saying you're done. The Stop hook runs tests and the policy check too.
- Hooks: `.claude/hooks/` formats and lints each edited Swift file, and blocks finishing while tests or the policy check
  fail.

## Subagents (.claude/agents/)

- `swift-test-writer`: after changing anything in `Sources/SRTCore`, when a test fails or is flaky, or to add tests
  or close coverage gaps.
- `reviewer`: read-only review before opening a PR or after a non-trivial change. Covers architecture, bugs and
  concurrency, test quality, and privacy/network. It reports findings and never edits.

## Releases

`make release VERSION=X.Y.Z` (try `DRY_RUN=1` first). Version source of truth: `VERSION`. See docs/RELEASE.md.
