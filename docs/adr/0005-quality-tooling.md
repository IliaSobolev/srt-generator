# 0005. Quality tooling: llvm-cov and scripted mutation testing

Date: 2026-11-05 · Status: accepted

## Context
The suggested tools were coverage via `xccov` on an `.xcresult` and mutation testing with Muter. SwiftPM's
`swift test` doesn't produce `.xcresult` bundles, and Muter has had no release since 2023.

## Decision
- Coverage: `scripts/coverage.sh` uses llvm-cov and gates **SRTCore at 100% line coverage**, the bar the project already
  met, instead of "current minus 2%". Views, the CLI, the composition root and the engine adapters aren't measured.
  CI uploads JUnit XML and the llvm-cov JSON instead of an `.xcresult`.
- Mutation testing: `scripts/mutate.py` (`make mutate`) applies one operator mutation at a time to a temporary copy of
  the repo and runs the tests. It's on-demand only.
- Tools (SwiftLint, SwiftFormat, actionlint, gitleaks) are pinned and SHA-256-verified by `scripts/bootstrap-tools.sh`
  into `.tools/bin`, so local runs and CI use identical versions without Homebrew.

## Consequences
No dependency on a stale tool or on an Xcode project. The mutation script only covers simple operators (comparison,
boolean, arithmetic, literals); that's enough to find assertion-free or weak tests.
