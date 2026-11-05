# 0001. Keep three modules

Date: 2026-11-05 · Status: accepted

## Context
A split into Domain, ModelDownload, Transcription, Persistence and UI modules was proposed so the compiler enforces
the boundaries. The code is about 1,500 lines. It's already split by dependency direction: `SRTCore` holds pure logic
and protocols, `SRTEngines` holds the third-party adapters, and `SRTGenerator` holds the UI and composition root.

## Decision
Keep `SRTCore` / `SRTEngines` / `SRTGenerator`. Enforce the remaining rules with `Tests/ArchitectureTests` and
SwiftLint custom rules instead of more modules. Downloads already sit behind `ModelProvider`, and only `SRTEngines`
can reach a network-capable library.

## Consequences
Fewer targets and faster builds. The ViewModels (`AppState`, `ModelManager`, `JobQueue`) share a module with domain
types. If SRTCore grows past ~3k lines, or a second UI appears, split `SRTPresentation` (ViewModels) from
`SRTDomain` first.
