#!/bin/zsh
# Scans all of git history for secrets (gitleaks) and blobs over 5 MB. Run before the first public push.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -x .tools/bin/gitleaks ]] || scripts/bootstrap-tools.sh gitleaks
.tools/bin/gitleaks git --no-banner --redact --log-opts="--all" .
large=$(git rev-list --objects --all | git cat-file --batch-check='%(objecttype) %(objectsize) %(rest)' \
    | awk '$1 == "blob" && $2 > 5242880 { printf "%8.1f MB  %s\n", $2 / 1048576, $3 }')
if [[ -n "$large" ]]; then print -u2 "Blobs over 5 MB in history:\n$large"; exit 1; fi
echo "History scan passed: no secrets found, no blobs over 5 MB."
