#!/bin/zsh
# Runs the Swift Testing suite with coverage and reports line coverage for SRTCore.
# Usage: scripts/coverage.sh [--show-missing]   Exits non-zero if SRTCore is below 100% line coverage.
set -euo pipefail
cd "$(dirname "$0")/.."

swift test --enable-code-coverage >/dev/null
BIN_DIR="$(swift build --show-bin-path)"
PROFDATA="$(find "$BIN_DIR" .build -name default.profdata -path '*codecov*' 2>/dev/null | head -1)"
XCTEST="$(find "$BIN_DIR" -name 'SRTCoreTests.xctest' -maxdepth 2 | head -1)"
BINARY="$XCTEST/Contents/MacOS/SRTCoreTests"
FILTER=(-ignore-filename-regex='(\.build|Tests)/')

xcrun llvm-cov report "$BINARY" -instr-profile "$PROFDATA" "${FILTER[@]}" Sources/SRTCore
if [[ "${1:-}" == "--show-missing" ]]; then
    xcrun llvm-cov show "$BINARY" -instr-profile "$PROFDATA" "${FILTER[@]}" Sources/SRTCore \
        -show-line-counts-or-regions -format=text | grep -E '^[[:space:]]+[0-9]+\|[[:space:]]+0\||^\/' || true
fi

RESULT=$(xcrun llvm-cov export "$BINARY" -instr-profile "$PROFDATA" "${FILTER[@]}" Sources/SRTCore -summary-only \
    | python3 -c 'import json,sys; t=json.load(sys.stdin)["data"][0]["totals"]["lines"]; print(t["covered"], t["count"])')
read covered total <<< "$RESULT"
echo "SRTCore line coverage: $covered/$total"
[[ "$covered" == "$total" ]]
