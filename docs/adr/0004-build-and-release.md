# 0004. SwiftPM-only build and unsigned DMG releases

Date: 2026-11-05 · Status: accepted

## Context
There's no Xcode project; `build-app.sh` assembles the `.app` from `swift build -c release`. The maintainer has no
paid Apple Developer account, so Developer ID signing and notarization aren't possible.

## Decision
- The version lives in the `VERSION` file (SemVer), which stands in for `MARKETING_VERSION`. `build-app.sh` writes it to
  `CFBundleShortVersionString`, and `CFBundleVersion` is the commit count, so it grows with every release.
- `make release VERSION=X.Y.Z` bumps `VERSION`, updates `CHANGELOG.md`, commits, tags `vX.Y.Z` and pushes after
  confirmation. `release.yml` builds an ad-hoc-signed app, wraps it in `SRTGenerator-X.Y.Z.dmg` (hdiutil) with a
  `.sha256`, and publishes a GitHub Release. Tags with a suffix (`-beta.1`) are pre-releases.
- Models aren't bundled; they're downloaded in-app.

## Consequences
Gatekeeper blocks the first launch. The README explains how to allow it and how to verify the checksum or build
from source. With a Developer ID later, add `codesign --options runtime` with an entitlements file, `notarytool` and
`stapler` to `release.yml` (secrets documented in `docs/RELEASE.md`).
