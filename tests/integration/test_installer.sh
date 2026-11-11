#!/usr/bin/bash
# The installer's whole lifecycle in an isolated fake $HOME, configs only
# (--no-packages; nothing is installed and sudo is never called):
#   --dry-run changes nothing · --install links and records a manifest ·
#   a second --install is idempotent (no new backups) · an interrupted
#   install resumes · --rollback restores the user's original files and
#   never touches an existing ~/.zshrc it was told to keep.
# Fedora code paths are exercised on any distro via AETHER_TEST_OS_*.
# The installer refuses to run as root, so this test skips as root.

set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ "$(id -u)" -eq 0 ]; then echo "SKIP: install.sh refuses root by design; run this test as a normal user"; exit 0; fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T" XDG_CONFIG_HOME="$T/.config" XDG_STATE_HOME="$T/.local/state" XDG_CACHE_HOME="$T/.cache"
export AETHER_TEST_OS_ID=fedora AETHER_TEST_OS_VERSION=42
fail() { echo "FAIL: $1"; exit 1; }

echo "my own zshrc" > "$HOME/.zshrc"
mkdir -p "$HOME/.config/kitty" && echo "my kitty" > "$HOME/.config/kitty/kitty.conf"

before="$(find "$HOME" | sort)"
"$REPO_DIR/install.sh" --dry-run --no-packages >/dev/null </dev/null || fail "--dry-run exited non-zero"
[ "$(find "$HOME" | sort)" = "$before" ] || fail "--dry-run changed files"
echo "PASS: --dry-run changed nothing"

"$REPO_DIR/install.sh" --check --no-packages >/dev/null </dev/null || fail "--check reported a blocker on a fresh home"
echo "PASS: --check passes"

"$REPO_DIR/install.sh" --install --no-packages >/dev/null </dev/null || fail "--install failed"
[ "$(readlink "$HOME/.config/kitty")" = "$REPO_DIR/config/kitty" ] || fail "kitty not linked"
[ "$(cat "$HOME/.zshrc")" = "my own zshrc" ] || fail ".zshrc was replaced without an interactive yes"
grep -q $'\tbackup\t'"$HOME/.config/kitty" "$XDG_STATE_HOME/aether/manifest.tsv" || fail "moved-aside kitty config not in the manifest"
for f in hardware compat profile theme cursor; do [ -f "$HOME/.config/aether-shell/hypr/$f.conf" ] || fail "fragment $f.conf missing"; done
[ -s "$HOME/.config/aether-shell/terminal/kitty-theme.conf" ] || fail "kitty theme not generated"
echo "PASS: --install links, records, generates fragments and keeps ~/.zshrc"

n1="$(find "$HOME/.config" -maxdepth 1 -name 'kitty.bak.*' | wc -l)"
"$REPO_DIR/install.sh" --install --no-packages >/dev/null </dev/null || fail "second --install failed"
n2="$(find "$HOME/.config" -maxdepth 1 -name 'kitty.bak.*' | wc -l)"
[ "$n1" -eq "$n2" ] || fail "re-install created new backups ($n1 -> $n2)"
echo "PASS: re-install is idempotent"

printf 'done=packages\ndone=quickshell\ndone=backup\n' > "$XDG_STATE_HOME/aether/install.state"
out="$("$REPO_DIR/install.sh" --install --no-packages </dev/null 2>&1)"
grep -q "backup (already done" <<< "$out" || fail "interrupted install did not resume"
echo "PASS: interrupted install resumes from saved progress"

"$REPO_DIR/install.sh" --rollback --yes >/dev/null </dev/null || fail "--rollback failed"
[ -d "$HOME/.config/kitty" ] && [ ! -L "$HOME/.config/kitty" ] || fail "kitty config not restored as a real directory"
[ "$(cat "$HOME/.config/kitty/kitty.conf")" = "my kitty" ] || fail "restored kitty.conf content differs"
[ "$(cat "$HOME/.zshrc")" = "my own zshrc" ] || fail "rollback touched ~/.zshrc"
[ ! -e "$HOME/.config/hypr" ] || fail "repo symlink left after rollback"
[ -f "$HOME/.config/aether-shell/hypr/profile.conf" ] || fail "rollback deleted user settings it should keep"
echo "PASS: --rollback restores originals and keeps settings"

out="$("$REPO_DIR/install.sh" --install --mode bogus 2>&1 </dev/null || true)"
grep -q "must be minimal, recommended or complete" <<< "$out" || fail "bad --mode accepted"
echo "PASS: invalid options are rejected"
echo
echo "All installer checks passed."
