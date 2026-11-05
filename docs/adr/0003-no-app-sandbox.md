# 0003. No App Sandbox for now

Date: 2026-11-05 · Status: accepted (revisit when signing is available)

## Context
`AudioLoader` runs the user's Homebrew `ffmpeg` (for MKV, WebM, OGG, …). Child processes of a sandboxed app inherit
its sandbox, and an external binary without the `com.apple.security.inherit` entitlement is killed. Sandboxing would
also move model storage into the container and require security-scoped bookmarks for output folders.

## Decision
Ship unsandboxed for now. The policy check still forbids `com.apple.security.network.server` and an explicit
`app-sandbox = false` in any entitlements file. `REQUIRE_SANDBOX` in `scripts/check-network-policy.sh` flips this
to "sandbox required".

## Consequences
The privacy guarantees rest on code review and the automated checks, not on the OS. Revisit if we drop external ffmpeg
(for example by bundling a sandbox-compatible decoder) or move to Mac App Store distribution.
