# Contributing

Thanks for helping. SRT Generator's core promise is that **your media never leaves your Mac**, so a few rules are
stricter than usual.

## Setup

Requirements: Apple Silicon Mac, macOS 26+, Xcode 26+ (Swift 6.2 tools).

```sh
git clone <your fork> && cd srtgenerator
make tools     # downloads pinned, checksum-verified swiftlint/swiftformat/actionlint into .tools/bin
make ci        # lint, build (warnings are errors), tests + coverage gate, network policy check
make app       # dist/SRT Generator.app
```

`make help` lists all targets. Tests use fakes and tiny generated fixtures. They never download models or use the
network, so `make ci` works offline once dependencies are resolved.

## Pull requests

- Keep PRs small and focused. Open an issue first for larger changes.
- `make ci` must pass. CI runs the same checks on every PR, including PRs from forks.
- Add or update tests for every behavior change. `SRTCore` stays at 100% line coverage, with tests that assert real
  behavior (see `CLAUDE.md` → Testing rules).
- Follow the architecture in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): MVVM, no logic in Views, dependencies
  injected through protocols, and concrete types only in `LiveDependencies.swift`. `Tests/ArchitectureTests`
  enforces most of it.
- Use imperative PR titles ("Add …", "Fix …", "Remove …"). They become CHANGELOG entries.

## Network policy

- The only network access allowed is downloading models from the built-in list, from the hosts in
  `config/allowed-hosts.txt`.
- No telemetry, analytics, crash reporting, update checks, accounts or remote config.
- Never send media, audio, transcripts, subtitles, file names or settings anywhere.
- New dependencies need a justification in the PR, must not access the network, and go in
  `config/allowed-dependencies.txt`.
- PRs that touch networking, entitlements, the model list or the `config/` allowlists need maintainer approval.
  Tick the box in the PR template.

`scripts/check-network-policy.sh` enforces this in CI.

## Releases

Maintainers only: see [docs/RELEASE.md](docs/RELEASE.md).
