# 0002. Network policy

Date: 2026-11-05 · Status: accepted

## Context
The app transcribes the user's media on-device. Users must be able to trust that video, audio, transcripts and
subtitles never leave the Mac.

## Decision
- The only network use is downloading models from the built-in catalog (`ModelCatalog.swift`), plus the Whisper
  tokenizer that WhisperKit fetches on first load. Hosts are listed in `config/allowed-hosts.txt`:
  `huggingface.co` and its CDN `*.hf.co`.
- Our own sources never use networking APIs. Downloads go through `ModelProvider` → WhisperKit/FluidAudio, which only
  `SRTEngines` imports.
- No backend, accounts, telemetry, analytics, crash reporting, remote config or update checks.
- New dependencies are allowlisted in `config/allowed-dependencies.txt` with a justification, and must not add network
  access.
- Apple's Translation framework downloads its language packs through macOS itself, outside the app's process. Text is
  translated on-device.

## Enforcement
`scripts/check-network-policy.sh` (CI, Stop hook), SwiftLint `no_networking_apis`, `ArchitectureTests`, and Claude
Code permissions that require asking before edits to the allowlists, entitlements or the model list.

## Consequences
Hugging Face sees the requesting IP and which model files are downloaded. That's documented in the README Privacy
section. Users who set `HF_ENDPOINT`/`REGISTRY_URL` environment variables can redirect downloads; that's a deliberate
escape hatch of the libraries, not something the app sets.
