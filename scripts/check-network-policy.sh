#!/bin/zsh
# Enforces the network policy (CLAUDE.md, docs/adr/0002-network-policy.md). Exits 1 on any violation.
#
#  1. No networking APIs in Sources/. The app's own code never talks to the network; model downloads
#     happen inside WhisperKit/FluidAudio, which only Sources/SRTEngines may import.
#  2. Every URL or host literal in Sources/ is in config/allowed-hosts.txt.
#  3. Entitlements never grant network.server and never switch the sandbox off explicitly;
#     no App Transport Security exceptions.
#  4. Package.resolved holds only packages from config/allowed-dependencies.txt, and nothing that looks
#     like analytics, telemetry, crash reporting or auto-update.
#
# Exceptions live in config/network-exceptions.txt (path-glob|regex|reason), each with a reason.
# Usage: scripts/check-network-policy.sh [repo-root]
set -uo pipefail
setopt extended_glob null_glob
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 2

# The app currently runs unsandboxed so it can launch Homebrew's ffmpeg (docs/adr/0003-no-app-sandbox.md).
# Set to 1 once the sandbox is adopted; then a missing or disabled sandbox fails the check.
REQUIRE_SANDBOX=0

failures=()
fail() { failures+=("$1"); }

# Exceptions: parallel arrays of path glob and regex.
ex_paths=() ex_regex=()
while IFS='|' read -r p r reason; do
    [[ -z "$p" || "$p" == \#* ]] && continue
    if [[ -z "${reason// /}" ]]; then fail "config/network-exceptions.txt: exception for $p has no reason"; continue; fi
    ex_paths+=("$p") ex_regex+=("$r")
done < config/network-exceptions.txt

is_excepted() { # $1 = path, $2 = matched text
    local i
    for (( i = 1; i <= ${#ex_paths}; i++ )); do
        [[ "$1" == ${~ex_paths[i]} ]] && print -r -- "$2" | grep -qE -- "${ex_regex[i]}" && return 0
    done
    return 1
}

swift_files=(Sources/**/*.swift)

# 1a. Networking APIs anywhere in our sources.
NET_API='\b(URLSession|URLRequest|NWConnection|NWListener|NWBrowser|NWEndpoint|NWPathMonitor|CFSocket|CFStream|CFHTTPMessage|WKWebView|SFSafariViewController|ASWebAuthenticationSession|BSDSocket)\b|\b(socket|connect|getaddrinfo)\(|^[[:space:]]*(@preconcurrency[[:space:]]+)?import[[:space:]]+(Network|WebKit|SafariServices)\b|(Data|String)\(contentsOf:[[:space:]]*URL\(string:'
while IFS= read -r hit; do
    file="${hit%%:*}" text="${hit#*:*:}"
    is_excepted "$file" "$text" || fail "networking API outside the model-download dependencies: $hit"
done < <(grep -nE "$NET_API" -- $swift_files)

# 1b. Libraries that do networking may only be imported by the SRTEngines adapter module.
ENGINE_IMPORT='^[[:space:]]*(@preconcurrency[[:space:]]+)?import[[:space:]]+(WhisperKit|FluidAudio|Hub|ArgmaxCore|Transformers|Tokenizers)\b'
for f in $swift_files; do
    [[ "$f" == Sources/SRTEngines/* ]] && continue
    grep -nE "$ENGINE_IMPORT" -- "$f" | while IFS= read -r hit; do
        fail "network-capable library imported outside Sources/SRTEngines: $f:$hit"
    done
done

# 2. URL and host literals must be allowlisted.
allowed_hosts=(${(f)"$(grep -vE '^[[:space:]]*(#|$)' config/allowed-hosts.txt | awk '{print $1}')"})
host_allowed() {
    local h="${1:l}" a
    for a in $allowed_hosts; do
        if [[ "$a" == \*.* ]]; then [[ "$h" == *"${a#\*}" ]] && return 0
        else [[ "$h" == "$a" ]] && return 0; fi
    done
    return 1
}
URL_RE='[a-zA-Z][a-zA-Z0-9+.-]*://[^[:space:]"'"'"'<>)\\]+'
HOST_RE='"[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*\.(com|net|org|io|co|ai|app|dev|cloud|me|us|eu|de|ru|cn|xyz|tech|so|sh|ly|gg)(:[0-9]+)?(/[^"]*)?"'
while IFS= read -r hit; do
    file="${hit%%:*}" rest="${hit#*:}" line="${rest%%:*}" text="${rest#*:}"
    [[ "$text" == file://* ]] && continue
    if [[ "$text" == \"* ]]; then host="${${text//\"/}%%[:/]*}"
    else host="${${text#*://}%%[:/?#]*}"; host="${host##*@}"; fi
    host_allowed "$host" && continue
    is_excepted "$file" "$text" && continue
    fail "host '$host' is not in config/allowed-hosts.txt: $file:$line: $text"
done < <(grep -noE "$URL_RE|$HOST_RE" -- $swift_files)

# 3. Entitlements and ATS (repo files plus whatever build-app.sh generates or passes to codesign).
ent_files=(**/*.entitlements~(.build|.tools|dist)/**)
sandbox_found=0
for f in $ent_files; do
    grep -q 'com.apple.security.network.server' "$f" && fail "$f grants com.apple.security.network.server (incoming connections)"
    if grep -A1 'com.apple.security.app-sandbox' "$f" | grep -q '<false/>'; then
        fail "$f disables the App Sandbox"
    elif grep -A1 'com.apple.security.app-sandbox' "$f" | grep -q '<true/>'; then
        sandbox_found=1
    fi
done
(( REQUIRE_SANDBOX && !sandbox_found )) && fail "no entitlements file enables com.apple.security.app-sandbox"
grep -nE 'NSAppTransportSecurity|NSAllowsArbitraryLoads|NSExceptionDomains' -- build-app.sh scripts/*.sh $swift_files \
    2>/dev/null | grep -v '^scripts/check-network-policy.sh' | while IFS= read -r hit; do
    fail "App Transport Security exception: $hit"
done

# 4. Dependencies: allowlist plus a denylist of analytics, telemetry, crash-reporting and updater SDKs.
allowed_deps=(${(f)"$(grep -vE '^[[:space:]]*(#|$)' config/allowed-dependencies.txt | awk '{print $1}')"})
resolved_ids=(${(f)"$(grep -oE '"identity"[[:space:]]*:[[:space:]]*"[^"]+"' Package.resolved | sed -E 's/.*"([^"]+)"$/\1/')"})
for id in $resolved_ids; do
    (( ${allowed_deps[(Ie)$id]} )) || fail "dependency '$id' is not in config/allowed-dependencies.txt (justify it in the PR first)"
done
DENY='firebase|crashlytics|sentry|bugsnag|instabug|appcenter|app-center|mixpanel|amplitude|segment|analytics|posthog|datadog|newrelic|new-relic|telemetry|telemetrydeck|aptabase|countly|appmetrica|flurry|raygun|embrace|plcrashreporter|kscrash|heap-|launchdarkly|configcat|sparkle|devicecheck'
grep -inE "$DENY" -- Package.swift Package.resolved | while IFS= read -r hit; do
    fail "analytics/telemetry/crash-reporting/updater dependency: $hit"
done

if (( ${#failures} )); then
    print -u2 "Network policy check FAILED (${#failures} problem(s)):"
    for f in $failures; do print -u2 "  - $f"; done
    print -u2 "See CLAUDE.md > Network policy. Legitimate exceptions go in config/network-exceptions.txt with a reason."
    exit 1
fi
echo "Network policy check passed (${#swift_files} Swift files, ${#resolved_ids} dependencies, hosts: ${(j:, :)allowed_hosts})."
