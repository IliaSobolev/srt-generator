# Architecture

SRT Generator is a SwiftPM package with three source modules. Dependencies point inward: the app and the engine
adapters depend on `SRTCore`, and `SRTCore` depends on nothing but Apple system frameworks.

```
                ┌──────────────────────────────────────────────┐
                │ SRTGenerator  (executable: SwiftUI app + CLI)│
                │  Views, CLI, TranslationBridge, PanelPicker  │
                │  LiveDependencies = composition root         │
                └───────────────┬───────────────┬──────────────┘
                                │               │
                                ▼               ▼
┌───────────────────────────────────┐   ┌──────────────────────────────────────┐
│ SRTCore  (pure logic, 100% tested)│◀──│ SRTEngines  (adapters)               │
│  Domain: ModelCatalog, Job,       │   │  WhisperProvider  → WhisperKit       │
│    TranscriptionSettings, …       │   │  ParakeetProvider → FluidAudio       │
│  ViewModels (@MainActor           │   │  The only module that may import     │
│    @Observable): AppState,        │   │  network-capable libraries.          │
│    ModelManager, JobQueue         │   └──────────────────┬───────────────────┘
│  Services: TranscriptionService,  │                      │ model downloads only
│    AudioLoader, SRTWriter, …      │                      ▼
│  Protocols.swift: every external  │             huggingface.co, *.hf.co
│    capability as a protocol       │
└───────────────────────────────────┘
```

| Module | May import | Must not |
|---|---|---|
| `SRTCore` | Foundation, Observation, AVFoundation, NaturalLanguage, Synchronization, UniformTypeIdentifiers, CoreMedia | SwiftUI/AppKit, networking, third-party packages |
| `SRTEngines` | SRTCore, WhisperKit, FluidAudio, CoreML | UI frameworks; app state |
| `SRTGenerator` | everything above, SwiftUI, AppKit, Translation | WhisperKit/FluidAudio directly; business logic in Views |

## Rules

1. **MVVM.** Views (`*View.swift`) render state and forward user intent. Logic lives in SRTCore ViewModels
   (`AppState`, `ModelManager`, `JobQueue`), which are `@MainActor @Observable` and never import UI frameworks.
2. **Dependency injection.** Every external capability is a protocol in `SRTCore/Services/Protocols.swift`
   (`ModelProvider`, `SpeechEngine`, `AudioDecoding`, `Translating`, `SubtitleWriting`, `FilePicking`, `Sleeper`),
   passed in through `AppDependencies`. Only `LiveDependencies.swift` constructs concrete adapters, and only the app and
   CLI entry points call it. No singletons (`static let shared`) anywhere.
3. **Networking** happens only inside WhisperKit/FluidAudio, which only `SRTEngines` imports. `ModelProvider` is the
   download boundary (`download`, `isDownloaded`, `delete`). See [ADR 0002](adr/0002-network-policy.md).
4. **Single responsibility** means one reason to change per type, not one method per type. Don't split a cohesive
   type just to make it shorter; split it when two unrelated concerns change for different reasons.

## How the rules are enforced

| Rule | Enforced by |
|---|---|
| SRTCore framework imports, engine libraries only in SRTEngines, `@MainActor` observables, composition root, no logic in Views, offline tests | `Tests/ArchitectureTests` (source scanning, runs with `swift test`) |
| No UI imports in SRTCore, no networking APIs, no singletons, size/complexity limits | `.swiftlint.yml` custom rules + limits (`make lint`) |
| Networking APIs, hosts, entitlements, dependencies | `scripts/check-network-policy.sh` (`make policy`) |
| No warnings | `.treatAllWarnings(as: .error)` in `Package.swift` |
| SRTCore fully tested | `scripts/coverage.sh` (100% line coverage gate) |
| Mixed responsibilities, leaky abstractions, wrong module placement | `reviewer` subagent (judgement; it proposes new automated rules) |

Size limits in `.swiftlint.yml` were set from the code as it was in Nov 2026 (largest file: `ContentView.swift`,
~450 lines). Tighten them over time; loosening one needs a reason in the PR.

Known, baselined violations live in the tests themselves (for example the `FileManager` call in `SettingsView` in
`ArchitectureTests.viewsHaveNoBusinessLogic`). Remove an entry when you fix it; don't add new ones.

## Model storage

| Engine | Location | Integrity today |
|---|---|---|
| Whisper | `~/Library/Application Support/SRTGenerator/models/argmaxinc/whisperkit-coreml/<variant>` plus tokenizer in `…/models/openai/whisper-*` | Hugging Face etag and size checks by swift-transformers; revision `main` |
| Parakeet | `~/Library/Application Support/FluidAudio/Models/…` (FluidAudio default) | FluidAudio's own checks; revision `main` |

Planned hardening (needs approval because it changes behavior and the model list): pin a revision per model, verify
SHA-256 manifests, check free disk space before downloading, store Parakeet under the app's folder, and show
user-friendly download errors.

## Decisions

- [0001 Keep three modules](adr/0001-module-structure.md)
- [0002 Network policy](adr/0002-network-policy.md)
- [0003 No App Sandbox for now](adr/0003-no-app-sandbox.md)
- [0004 SwiftPM-only build and unsigned DMG releases](adr/0004-build-and-release.md)
- [0005 Quality tooling: llvm-cov, scripted mutation testing](adr/0005-quality-tooling.md)
