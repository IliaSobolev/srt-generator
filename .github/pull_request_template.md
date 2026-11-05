## What and why

<!-- One or two sentences. Link the issue: Fixes #123 -->

## Checklist

- [ ] `make ci` passes locally
- [ ] Tests added or updated for changed behavior (they assert behavior, don't hit the network, and don't sleep)
- [ ] No new logic in Views; dependencies injected via protocols
- [ ] PR title is imperative ("Add …", "Fix …"); it becomes the CHANGELOG entry

## Network and privacy

- [ ] **This PR touches networking, entitlements, the model list (`ModelCatalog.swift`), `config/` allowlists or dependencies.**
      If checked, explain what is contacted and why, and wait for maintainer approval.
- [ ] Media, transcripts, subtitles and file names still never leave the device
