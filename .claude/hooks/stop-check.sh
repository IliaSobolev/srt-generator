#!/bin/zsh
# Stop: block finishing while unit tests or the network policy check fail (exit 2 = keep working).
# Skips when nothing relevant changed, and never blocks twice in a row (stop_hook_active) to avoid loops.
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}" || exit 0
active=$(python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("stop_hook_active", False))' 2>/dev/null)
[[ "$active" == "True" ]] && exit 0
[[ -n "$(git status --porcelain -- Sources Tests Package.swift Package.resolved config scripts 2>/dev/null)" ]] || exit 0

problems=""
if ! policy=$(scripts/check-network-policy.sh 2>&1); then problems+="$policy"$'\n'; fi
log=$(swift test 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
if ! print -r -- "$log" | grep -q "Test run with .* passed" || print -r -- "$log" | grep -qE "✘|error:"; then
    problems+="Tests failed:"$'\n'"$(print -r -- "$log" | grep -E "✘|error:|Test run with" | head -30)"$'\n'
fi
if [[ -n "$problems" ]]; then
    print -u2 -r -- "Not done yet. Fix these before finishing:"$'\n'"$problems"
    exit 2
fi
exit 0
