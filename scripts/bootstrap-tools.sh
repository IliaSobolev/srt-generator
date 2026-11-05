#!/bin/zsh
# Downloads pinned dev tools into .tools/bin and verifies each archive's SHA-256.
# Usage: scripts/bootstrap-tools.sh [tool…]   (default: swiftlint swiftformat actionlint gitleaks)
# Used locally and in CI so everyone runs the same versions. Needs no Homebrew.
set -euo pipefail
cd "$(dirname "$0")/.."

BIN=.tools/bin
mkdir -p "$BIN" .tools/dl

# name  version  url  sha256  path-inside-archive
typeset -A URL SHA INNER VER
VER[swiftlint]=0.65.1
URL[swiftlint]="https://github.com/realm/SwiftLint/releases/download/0.65.1/portable_swiftlint.zip"
SHA[swiftlint]=c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0
INNER[swiftlint]=swiftlint

VER[swiftformat]=0.64.5
URL[swiftformat]="https://github.com/nicklockwood/SwiftFormat/releases/download/0.64.5/swiftformat.zip"
SHA[swiftformat]=ec017c91fdd46233e5a22dc43ff9564a3cc4b37023d3b4681b6c7d7b781de113
INNER[swiftformat]=swiftformat

VER[actionlint]=1.7.12
URL[actionlint]="https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_darwin_arm64.tar.gz"
SHA[actionlint]=aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f
INNER[actionlint]=actionlint

VER[gitleaks]=8.30.1
URL[gitleaks]="https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_darwin_arm64.tar.gz"
SHA[gitleaks]=b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5
INNER[gitleaks]=gitleaks

VER[gh]=2.103.3
URL[gh]="https://github.com/cli/cli/releases/download/v2.103.3/gh_2.103.3_macOS_arm64.zip"
SHA[gh]=d700207eae9ae98fe2b89535c2c087c07823d4628c56364695a5a07ef311c062
INNER[gh]=gh_2.103.3_macOS_arm64/bin/gh

tools=("$@")
(( ${#tools} )) || tools=(swiftlint swiftformat actionlint gitleaks)

for t in $tools; do
    stamp="$BIN/.$t-${VER[$t]}"
    [[ -x "$BIN/$t" && -f "$stamp" ]] && continue
    archive=".tools/dl/${URL[$t]:t}"
    echo "Fetching $t ${VER[$t]}"
    curl -fsSL --retry 3 -o "$archive" "${URL[$t]}"
    actual=$(shasum -a 256 "$archive" | cut -d' ' -f1)
    if [[ "$actual" != "${SHA[$t]}" ]]; then
        echo "SHA-256 mismatch for $t: expected ${SHA[$t]}, got $actual" >&2
        rm -f "$archive"
        exit 1
    fi
    out=".tools/dl/$t"
    rm -rf "$out" && mkdir -p "$out"
    case "$archive" in
        *.zip) unzip -q "$archive" -d "$out" ;;
        *.tar.gz) tar -xzf "$archive" -C "$out" ;;
    esac
    install -m 0755 "$out/${INNER[$t]}" "$BIN/$t"
    rm -f "$BIN"/.$t-*(N) && touch "$stamp"
done
