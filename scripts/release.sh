#!/bin/zsh
# Cuts a release: make release VERSION=X.Y.Z [DRY_RUN=1]
#  - refuses unless on a clean main that is up to date with origin and `make ci` passes
#  - VERSION must be SemVer and greater than the latest vX.Y.Z tag
#  - bumps VERSION, adds a CHANGELOG.md section (Keep a Changelog) from merged PR titles since the last tag
#  - commits "Release vX.Y.Z", creates an annotated tag, and pushes both only after you confirm
# DRY_RUN=1 changes nothing in git: it reports the checks, previews the changelog and builds the DMG locally.
set -euo pipefail
cd "$(dirname "$0")/.."
NEW="${1:-}"
DRY="${DRY_RUN:-0}"
say() { print -P "%B==>%b $*"; }
die() { print -u2 "error: $*"; exit 1; }
problem() { if (( DRY )); then print -u2 "warning (ignored in dry run): $*"; else die "$*"; fi; }

SEMVER='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?$'
[[ "$NEW" =~ $SEMVER ]] || die "usage: make release VERSION=X.Y.Z[-pre]   (got '${NEW}')"

# SemVer precedence (major.minor.patch, then a pre-release sorts before the release).
semver_gt() { python3 -I - "$1" "$2" <<'PY'
import sys
def key(v):
    core, _, pre = v.partition("-")
    nums = [int(x) for x in core.split(".")]
    ids = [(0, int(p), "") if p.isdigit() else (1, 0, p) for p in pre.split(".")] if pre else []
    return nums, (1,) if not pre else (0, ids)
sys.exit(0 if key(sys.argv[1]) > key(sys.argv[2]) else 1)
PY
}

say "Checking repository state"
branch=$(git rev-parse --abbrev-ref HEAD)
[[ "$branch" == main ]] || problem "on branch '$branch', not main"
[[ -z "$(git status --porcelain)" ]] || problem "working tree is not clean"
if git remote get-url origin >/dev/null 2>&1; then
    git fetch --quiet --tags origin main || problem "could not fetch origin"
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main 2>/dev/null)" ]] || problem "main is not identical to origin/main"
else
    problem "no 'origin' remote"
fi

LAST_TAG=$(git tag --list 'v[0-9]*' --sort=-v:refname | head -1)
if [[ -n "$LAST_TAG" ]]; then
    semver_gt "$NEW" "${LAST_TAG#v}" || die "$NEW is not greater than the latest tag $LAST_TAG"
fi
git rev-parse -q --verify "refs/tags/v$NEW" >/dev/null && die "tag v$NEW already exists"

say "Running make ci"
make ci >/dev/null 2>&1 || { make ci 2>&1 | tail -30 >&2; die "make ci failed"; }

say "Collecting merged PRs since ${LAST_TAG:-the first commit}"
range="${LAST_TAG:+$LAST_TAG..}HEAD"
typeset -A sections
for c in ${(f)"$(git rev-list --first-parent --reverse "$range")"}; do
    subject=$(git log -1 --format=%s "$c")
    if [[ "$subject" =~ '^Merge pull request #([0-9]+)' ]]; then
        title="$(git log -1 --format=%b "$c" | head -1) (#${match[1]})"
    else
        title="$subject"
    fi
    [[ "$title" == Release\ v* || -z "$title" ]] && continue
    case "$title" in
        Add*|Introduce*|Support*) s=Added ;;
        Fix*|Correct*) s=Fixed ;;
        Remove*|Drop*|Delete*) s=Removed ;;
        Deprecate*) s=Deprecated ;;
        *ecurity*) s=Security ;;
        *) s=Changed ;;
    esac
    sections[$s]+="- $title"$'\n'
done
DATE=$(date +%Y-%m-%d)
notes="## [$NEW] - $DATE"$'\n'
for s in Added Changed Deprecated Removed Fixed Security; do
    [[ -n "${sections[$s]:-}" ]] && notes+=$'\n'"### $s"$'\n'"${sections[$s]}"
done
print -r -- "$notes"

if (( DRY )); then
    say "Dry run: building the DMG for $NEW (no files, commits or tags are changed)"
    APP_VERSION="$NEW" ./build-app.sh | tail -1
    scripts/make-dmg.sh "$NEW"
    say "Dry run complete. Nothing was committed, tagged or pushed."
    exit 0
fi

say "Updating VERSION and CHANGELOG.md"
print -r -- "$NEW" > VERSION
python3 -I - "$notes" <<'PY'
import sys, pathlib
p = pathlib.Path("CHANGELOG.md")
text, notes = p.read_text(), sys.argv[1].rstrip() + "\n\n"
marker = "## [Unreleased]"
i = text.find(marker)
if i < 0:
    sys.exit("CHANGELOG.md has no '## [Unreleased]' section")
j = text.find("\n", i) + 1
p.write_text(text[:j] + "\n" + notes + text[j:].lstrip("\n"))
PY
git add VERSION CHANGELOG.md
git commit -q -m "Release v$NEW"
git tag -a "v$NEW" -m "Release v$NEW"

say "Ready to push:"
git log --oneline -1
print "  tag:     v$NEW ($(git rev-parse --short "v$NEW"))"
print "  remote:  $(git remote get-url origin)"
print "  GitHub Actions will build SRTGenerator-$NEW.dmg and publish the release."
read -r "answer?Push commit and tag to origin? [y/N] "
if [[ "$answer" == [yY]* ]]; then
    git push origin main
    git push origin "v$NEW"
    say "Pushed. Watch the release workflow on GitHub."
else
    say "Not pushed. To undo locally: git tag -d v$NEW && git reset --hard HEAD~1"
fi
