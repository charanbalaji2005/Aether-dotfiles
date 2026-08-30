#!/usr/bin/bash
# Real integration test of the install lifecycle, run in an isolated fake
# $HOME (never touches the real one). Verifies:
#   1. setup-symlinks.sh creates correct symlinks
#   2. re-running it is idempotent (no errors)
#   3. a real file at a target path is backed up, not destroyed
#   4. uninstall.sh removes only symlinks that point into this repo
#   5. uninstall.sh leaves a symlink pointing elsewhere completely alone
#   6. restore.sh recovers backed-up content correctly
#
# This is the same sequence that was run manually during development —
# formalized here so it's actually re-run by CI, not just claimed once.

set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_HOME="$(mktemp -d)"
trap 'rm -rf "$TEST_HOME"' EXIT

fail() { echo "FAIL: $1"; exit 1; }

echo "Using isolated HOME: $TEST_HOME"

# 1. Initial symlink setup
HOME="$TEST_HOME" bash "$REPO_DIR/scripts/setup-symlinks.sh" >/dev/null
[ -L "$TEST_HOME/.config/hypr" ] || fail "hypr symlink not created"
[ "$(readlink "$TEST_HOME/.config/hypr")" = "$REPO_DIR/config/hypr" ] || fail "hypr symlink points to the wrong place"
[ -L "$TEST_HOME/.config/quickshell/aether-shell" ] || fail "aether-shell symlink not created"
[ -L "$TEST_HOME/.config/systemd/user/aether-shell.service" ] || fail "aether-shell.service symlink not created"
[ -L "$TEST_HOME/.local/bin/aether-screenshot" ] || fail "aether-screenshot symlink not created"
[ -L "$TEST_HOME/.local/bin/aether-wallpaper" ] || fail "aether-wallpaper symlink not created"
[ -L "$TEST_HOME/.config/aether-shell/wallpapers" ] || fail "wallpapers directory symlink not created"
echo "PASS: initial symlinks created correctly"

# 2. Idempotency
HOME="$TEST_HOME" bash "$REPO_DIR/scripts/setup-symlinks.sh" >/dev/null \
    || fail "re-running setup-symlinks.sh failed"
[ -L "$TEST_HOME/.config/hypr" ] || fail "hypr symlink lost after re-run"
echo "PASS: setup-symlinks.sh is idempotent"

# 3. Real file preservation
rm "$TEST_HOME/.zshrc"
echo "REAL USER CONTENT $(date +%s)" > "$TEST_HOME/.zshrc"
ORIGINAL_CONTENT="$(cat "$TEST_HOME/.zshrc")"
HOME="$TEST_HOME" bash "$REPO_DIR/scripts/setup-symlinks.sh" >/dev/null
BACKUP_FILE="$(find "$TEST_HOME" -maxdepth 1 -name '.zshrc.bak.*' | head -1)"
[ -n "$BACKUP_FILE" ] || fail "no backup created for pre-existing .zshrc"
[ "$(cat "$BACKUP_FILE")" = "$ORIGINAL_CONTENT" ] || fail "backup content doesn't match original"
echo "PASS: real user file was backed up, not destroyed"

# 4. Pre-existing unrelated symlink preservation during setup-symlinks.sh
rm "$TEST_HOME/.config/kitty"
mkdir -p "$TEST_HOME/external-target"
echo "EXTERNAL DATA" > "$TEST_HOME/external-target/kitty.conf"
ln -s "$TEST_HOME/external-target" "$TEST_HOME/.config/kitty"
HOME="$TEST_HOME" bash "$REPO_DIR/scripts/setup-symlinks.sh" >/dev/null
KITTY_BACKUP="$(find "$TEST_HOME/.config" -maxdepth 1 -name 'kitty.bak.*' | head -1)"
[ -n "$KITTY_BACKUP" ] || fail "no backup created for pre-existing unrelated symlink .config/kitty"
[ -L "$KITTY_BACKUP" ] || fail "unrelated symlink backup is not a symlink"
[ "$(readlink "$KITTY_BACKUP")" = "$TEST_HOME/external-target" ] || fail "unrelated symlink backup target mismatch"
[ -L "$TEST_HOME/.config/kitty" ] || fail "new kitty symlink not created"
[ "$(readlink "$TEST_HOME/.config/kitty")" = "$REPO_DIR/config/kitty" ] || fail "new kitty symlink wrong target"
echo "PASS: pre-existing unrelated symlink was backed up, not destroyed"

# 5. Uninstall respects external symlinks, removes repo symlinks
rm "$TEST_HOME/.config/kitty"
ln -s "$TEST_HOME/external-target" "$TEST_HOME/.config/kitty"
echo "y" | HOME="$TEST_HOME" bash "$REPO_DIR/scripts/uninstall.sh" >/tmp/uninstall_test.log 2>&1
[ "$(readlink "$TEST_HOME/.config/kitty")" = "$TEST_HOME/external-target" ] \
    || fail "uninstall.sh touched a symlink pointing outside the repo"
[ ! -e "$TEST_HOME/.config/hypr" ] || fail "uninstall.sh left a repo symlink in place"
echo "PASS: uninstall.sh only removes symlinks pointing into this repo"

# 6. Restore recovers content
ARCHIVE="$(find "$TEST_HOME/.aetheros-backups" -name 'aetheros-backup-*.tar.gz' | sort | tail -1)"
[ -n "$ARCHIVE" ] || fail "no backup archive produced by uninstall.sh's pre-backup step"
echo "y" | HOME="$TEST_HOME" bash "$REPO_DIR/scripts/restore.sh" "$ARCHIVE" >/tmp/restore_test.log 2>&1
diff -q "$TEST_HOME/.zshrc" "$REPO_DIR/config/zsh/.zshrc" >/dev/null \
    || fail "restored .zshrc doesn't match the repo's version"
echo "PASS: restore.sh recovers backed-up content correctly"

# 7. Restore rejects path-traversal attacks and unauthorized paths
MALICIOUS_DIR="$(mktemp -d)"
mkdir -p "$MALICIOUS_DIR/.ssh"
echo "MALICIOUS" > "$MALICIOUS_DIR/.ssh/id_rsa"
MALICIOUS_ARCHIVE="$(mktemp -d)/malicious.tar.gz"
tar -czf "$MALICIOUS_ARCHIVE" -C "$MALICIOUS_DIR" .
if echo "y" | HOME="$TEST_HOME" bash "$REPO_DIR/scripts/restore.sh" "$MALICIOUS_ARCHIVE" >/tmp/malicious_restore.log 2>&1; then
    fail "restore.sh accepted an unauthorized archive (.ssh/id_rsa)"
else
    echo "PASS: restore.sh correctly rejected archive with unauthorized/traversal paths"
fi
rm -rf "$MALICIOUS_DIR" "$(dirname "$MALICIOUS_ARCHIVE")" /tmp/malicious_restore.log

rm -f /tmp/uninstall_test.log /tmp/restore_test.log
echo
echo "All integration checks passed."
