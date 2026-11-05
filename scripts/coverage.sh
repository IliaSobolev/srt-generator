#!/bin/zsh
# Runs the Swift Testing suite with coverage and gates SRTCore line coverage.
# Usage: scripts/coverage.sh [--show-missing]
#   COVERAGE_MIN  minimum SRTCore line coverage in percent (default 100: the bar the project already meets).
# Only SRTCore is measured: Views, the CLI and the composition root (Sources/SRTGenerator) and the thin engine
# adapters (Sources/SRTEngines, which need multi-GB models) are excluded on purpose.
# Writes .build/reports/{tests.xml,coverage.json} for CI artifacts.
set -euo pipefail
cd "$(dirname "$0")/.."
MIN="${COVERAGE_MIN:-100}"
REPORTS=.build/reports
mkdir -p "$REPORTS"

if ! swift test --enable-code-coverage --xunit-output "$REPORTS/tests.xml" > "$REPORTS/test-output.log" 2>&1; then
    sed 's/\x1b\[[0-9;]*m//g' "$REPORTS/test-output.log" | grep -E "✘|error:|Test run with" >&2 || tail -40 "$REPORTS/test-output.log" >&2
    exit 1
fi
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

xcrun llvm-cov export "$BINARY" -instr-profile "$PROFDATA" "${FILTER[@]}" Sources/SRTCore -summary-only > "$REPORTS/coverage.json"
python3 - "$REPORTS/coverage.json" "$MIN" <<'EOF'
import json, sys
t = json.load(open(sys.argv[1]))["data"][0]["totals"]["lines"]
pct, need = 100.0 * t["covered"] / max(t["count"], 1), float(sys.argv[2])
print(f"SRTCore line coverage: {t['covered']}/{t['count']} = {pct:.2f}% (minimum {need:g}%)")
sys.exit(0 if pct + 1e-9 >= need else 1)
EOF
