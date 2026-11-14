#!/usr/bin/bash
# Set the repository and maintainer identity everywhere before publishing.
#
#   tools/set-publisher.sh --repo <github-user>/<repo> --maintainer "Full Name <email@example.org>"
#   tools/set-publisher.sh --check      exit 1 while any placeholder remains (release workflow)
#
# Placeholders replaced: https://github.com/OWNER/aetheros-dotfiles and
# "AetherOS Maintainer <maintainer@REPLACE.ME>" (README, docs, issue
# templates, systemd units, RPM spec, PKGBUILD).
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
URL_PH="https://github.com/OWNER/aetheros-dotfiles"
MAINT_PH="AetherOS Maintainer <maintainer@REPLACE.ME>"

# grep exits 1 when nothing matches — that's the "no placeholders" answer.
find_ph() { grep -rlF --exclude-dir=.git --exclude-dir=dist --exclude=set-publisher.sh --exclude=set-repo-url.sh --exclude=test_release_metadata.sh -e "$URL_PH" -e "$MAINT_PH" "$REPO_DIR" || true; }

if [ "${1:-}" = "--check" ]; then
    files="$(find_ph)"
    if [ -n "$files" ]; then
        echo "Placeholders remain (run tools/set-publisher.sh --repo … --maintainer …):"
        printf "  %s\n" "${files//"$REPO_DIR"\//}"
        exit 1
    fi
    echo "No publisher placeholders."
    exit 0
fi

repo="" maint=""
while [ $# -gt 0 ]; do
    case "$1" in
        --repo) repo="${2:-}"; shift ;;
        --maintainer) maint="${2:-}"; shift ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
    esac
    shift
done
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "--repo <user>/<repo> is required" >&2; exit 2; }
[[ "$maint" =~ ^[^\<\>]+\ \<[^@\<\>\ ]+@[^@\<\>\ ]+\.[^@\<\>\ ]+\>$ ]] || { echo '--maintainer "Name <email>" is required' >&2; exit 2; }
esc_maint="$(printf '%s' "$maint" | sed 's/[&|]/\\&/g')"
while IFS= read -r f; do
    [ -n "$f" ] || continue
    sed -i "s|$URL_PH|https://github.com/$repo|g; s|$MAINT_PH|$esc_maint|g" "$f"
    echo "updated ${f#"$REPO_DIR"/}"
done <<< "$(find_ph)"
echo "Done. Review with: git diff"
