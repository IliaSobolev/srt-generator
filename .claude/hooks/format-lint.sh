#!/bin/zsh
# PostToolUse (Edit|Write|MultiEdit): format the edited Swift file, then lint it and run the network policy check.
# Exit 2 sends the problems back to Claude so it fixes them right away.
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}" || exit 0
file=$(python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null)
[[ "$file" == *.swift && -f "$file" ]] || exit 0
[[ "$file" == */.build/* || "$file" == */.tools/* ]] && exit 0
[[ -x .tools/bin/swiftformat && -x .tools/bin/swiftlint ]] || scripts/bootstrap-tools.sh swiftlint swiftformat >/dev/null 2>&1

.tools/bin/swiftformat --quiet "$file" 2>&1 | grep -v '^$' >&2
lint=$(.tools/bin/swiftlint lint --quiet --strict "$file" 2>&1)
policy=$(scripts/check-network-policy.sh 2>&1)
policy_status=$?
if [[ -n "$lint" || $policy_status -ne 0 ]]; then
    {
        echo "Problems in $file (formatting was applied automatically):"
        [[ -n "$lint" ]] && echo "$lint"
        (( policy_status )) && echo "$policy"
    } >&2
    exit 2
fi
exit 0
