#!/usr/bin/bash
# Packages install entry points as symlinks (/usr/bin/aetheros-dotfiles-setup
# -> /usr/share/aetheros-dotfiles/scripts/setup-symlinks.sh), and
# setup-symlinks.sh links helpers into ~/.local/bin. Every script must find
# its repository through such a symlink — not resolve paths next to the link.
set -uo pipefail
REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
mkdir -p "$T/bin" "$T/home"
ln -s "$REPO_DIR/scripts/setup-symlinks.sh" "$T/bin/aetheros-dotfiles-setup"
ln -s "$REPO_DIR/scripts/doctor.sh" "$T/bin/aetheros-dotfiles-doctor"
ln -s "$REPO_DIR/scripts/bin/aether" "$T/bin/aether"

out="$(HOME="$T/home" "$T/bin/aetheros-dotfiles-setup" --dry-run 2>&1)" || fail "setup via symlink exited non-zero: $out"
grep -q "$REPO_DIR/config/hypr" <<< "$out" || fail "setup via symlink did not resolve the repository ($out)"
grep -q "$T/config" <<< "$out" && fail "setup via symlink resolved paths next to the link"
echo "PASS: setup-symlinks.sh works through a symlink"

HOME="$T/home" "$T/bin/aether" --version | grep -q '^aether ' || fail "aether via symlink"
echo "PASS: aether works through a symlink"

for s in "$REPO_DIR"/scripts/*.sh "$REPO_DIR"/scripts/bin/* "$REPO_DIR"/install.sh; do
    if grep -q 'BASH_SOURCE\[0\]' "$s" && grep -E 'dirname "\$\{BASH_SOURCE\[0\]\}"' "$s" >/dev/null; then
        fail "$(basename "$s") locates itself without resolving symlinks"
    fi
done
echo "PASS: no script locates itself without resolving symlinks"
