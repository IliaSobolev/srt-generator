# Releasing

Versions follow [SemVer](https://semver.org/). The single source of truth is the `VERSION` file (this SwiftPM
project has no `MARKETING_VERSION`). `build-app.sh` writes it to `CFBundleShortVersionString`, and `CFBundleVersion`
is the git commit count, so it grows with every release. Tags are `vX.Y.Z`; a suffix such as `v1.2.0-beta.1` makes a
GitHub pre-release.

## Cutting a release

```sh
make release VERSION=1.1.0 DRY_RUN=1   # report checks, preview the changelog, build dist/SRTGenerator-1.1.0.dmg; changes nothing
make release VERSION=1.1.0             # the real thing
```

The real run:
1. Refuses unless you're on a clean `main` identical to `origin/main`, `make ci` passes, and the version is valid
   SemVer greater than the latest tag.
2. Writes `VERSION` and adds a `CHANGELOG.md` section built from the merged PR titles since the last tag
   ("Add …" goes under Added, "Fix …" under Fixed, and so on). Edit the section afterwards if needed.
3. Commits `Release vX.Y.Z` and creates an annotated tag, then shows a summary and asks before pushing.

Pushing the tag triggers `.github/workflows/release.yml`. It checks that the tag matches `VERSION`, runs the tests
and the network policy check, builds the app, makes `SRTGenerator-X.Y.Z.dmg` with an Applications shortcut and a
`.sha256`, and publishes a GitHub Release with the notes from `CHANGELOG.md`. Only that job has `contents: write`.
Models are never bundled; users download them in the app.

## Signing

Releases are **ad-hoc signed** (no Apple Developer ID), so Gatekeeper blocks the first launch. The README explains
how to open the app and verify the checksum.

To switch to Developer ID later (needs a paid Apple Developer account):
1. Add repository secrets: `DEVELOPER_ID_P12_BASE64` and `DEVELOPER_ID_P12_PASSWORD` (Developer ID Application
   certificate), and `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_APP_PASSWORD` (an app-specific password).
2. In `release.yml`, import the certificate into a temporary keychain, then sign with
   `codesign --force --options runtime --timestamp --entitlements <file> --sign "Developer ID Application: …"`.
   Notarize with `xcrun notarytool submit SRTGenerator-X.Y.Z.dmg --wait` and staple with `xcrun stapler staple`.
3. The entitlements file must pass `scripts/check-network-policy.sh` (no `network.server`). See
   `docs/adr/0003-no-app-sandbox.md` before enabling the sandbox.
