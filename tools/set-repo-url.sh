#!/usr/bin/bash
# Point every repository link at your fork before publishing.
#
#   tools/set-repo-url.sh <github-user>/<repo>      e.g. tools/set-repo-url.sh charan/aetheros-dotfiles
#
# Replaces the placeholder https://github.com/OWNER/aetheros-dotfiles in the
# README, docs, packaging, systemd units and issue templates. Run it once,
# review `git diff`, commit.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${1:-}"
if ! [[ "$target" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "usage: $0 <github-user>/<repo>" >&2
    exit 2
fi
placeholder="https://github.com/OWNER/aetheros-dotfiles"
mapfile -t files < <(grep -rl --exclude-dir=.git --exclude=set-repo-url.sh -F "$placeholder" "$REPO_DIR" || true)
if [ "${#files[@]}" -eq 0 ]; then
    echo "No placeholder found — already set?"
    exit 0
fi
for f in "${files[@]}"; do
    sed -i "s#$placeholder#https://github.com/$target#g" "$f"
    echo "updated ${f#"$REPO_DIR"/}"
done
echo "Done. Review with: git diff"
