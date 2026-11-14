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
# Never touch the desktop this runs from: with Hyprland, Wayland and the
# session bus in reach, an install in a temporary HOME restarts the real
# Waybar from that HOME (which is then deleted, and the bar dies).
unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY DISPLAY
XDG_RUNTIME_DIR="$(mktemp -d)"
export XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/no-bus"
if [ "$(id -u)" -eq 0 ]; then echo "SKIP: install.sh refuses root by design; run this test as a normal user"; exit 0; fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T" XDG_CONFIG_HOME="$T/.config" XDG_STATE_HOME="$T/.local/state" XDG_CACHE_HOME="$T/.cache"
export AETHER_TEST_OS_ID=fedora AETHER_TEST_OS_VERSION=42
fail() { echo "FAIL: $1"; exit 1; }

echo "my own zshrc" > "$HOME/.zshrc"
mkdir -p "$HOME/.config/kitty" && echo "my kitty" > "$HOME/.config/kitty/kitty.conf"
# An existing Waybar setup (e.g. from another dotfiles project) must survive.
mkdir -p "$HOME/.config/waybar" && echo '{"my": "bar"}' > "$HOME/.config/waybar/config"

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
[ "$(readlink "$HOME/.config/waybar")" = "$REPO_DIR/config/waybar" ] || fail "waybar not linked"
grep -q $'\tbackup\t'"$HOME/.config/waybar" "$XDG_STATE_HOME/aether/manifest.tsv" || fail "existing waybar config not moved aside"
grep -q "interfaces/classic.conf" "$HOME/.config/aether-shell/hypr/interface.conf" || fail "classic interface not selected by default"
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
[ "$(cat "$HOME/.config/waybar/config" 2>/dev/null)" = '{"my": "bar"}' ] || fail "rollback didn't restore the original waybar config"
[ ! -e "$HOME/.config/hypr" ] || fail "repo symlink left after rollback"
[ -f "$HOME/.config/aether-shell/hypr/profile.conf" ] || fail "rollback deleted user settings it should keep"
echo "PASS: --rollback restores originals and keeps settings"

# Package planning with alternatives ("rofi-wayland|rofi"), against fake
# rpm/dnf/sudo: nothing installed; the repositories offer "rofi" but not
# "rofi-wayland", and no "wlogout".
mkdir -p "$T/fakebin"
printf '#!/bin/sh\nexit 1\n' > "$T/fakebin/rpm"
printf '#!/bin/sh\nexit 0\n' > "$T/fakebin/sudo"
cat > "$T/fakebin/dnf5" <<'FAKE'
#!/bin/bash
[ "$1" = --version ] && { echo "dnf5 5.2"; exit 0; }
for a in "$@"; do case "$a" in -q|repoquery|--available|--qf|'%{name}\n') ;; rofi-wayland|wlogout) ;; *) echo "$a" ;; esac; done
FAKE
chmod +x "$T/fakebin/"*
out="$(PATH="$T/fakebin:$PATH" "$REPO_DIR/install.sh" --check --interface classic 2>&1 </dev/null || true)"
grep -q "To install.* rofi " <<< "$out" || fail "the alternative 'rofi' was not chosen when rofi-wayland is unavailable"
grep -q "To install.*rofi-wayland" <<< "$out" && fail "an unavailable alternative was planned"
grep -q "wlogout is not available" <<< "$out" || fail "a missing package was not reported"
# The Dynamic Island may use the quickshell package, but the classic
# interface never needs the toolchain that builds the Quickshell shell.
grep -q "qt6-qtdeclarative-devel" <<< "$(grep 'To install' <<< "$out")" && fail "classic interface planned the Quickshell build toolchain"
out="$(PATH="$T/fakebin:$PATH" "$REPO_DIR/install.sh" --check --components hyprland,terminal 2>&1 </dev/null || true)"
grep -q "To install.* waybar" <<< "$out" && fail "a component that wasn't selected had its packages planned"
grep -q "To install.* kitty" <<< "$out" || fail "a selected component's packages were not planned"
out="$(PATH="$T/fakebin:$PATH" "$REPO_DIR/install.sh" --check --interface aether 2>&1 </dev/null || true)"
grep -q "To install.* waybar" <<< "$out" && fail "aether interface planned Waybar"
echo "PASS: package plan picks available alternatives and follows the interface"

out="$("$REPO_DIR/install.sh" --install --components hyprland,unicorn 2>&1 </dev/null || true)"
grep -q "Unknown component(s): unicorn" <<< "$out" || fail "an unknown component was accepted"
out="$("$REPO_DIR/install.sh" --install --interface aether --components waybar 2>&1 </dev/null || true)"
grep -q "not for the aether interface" <<< "$out" || fail "a classic-only component was accepted for the aether interface"
out="$("$REPO_DIR/install.sh" --install --interface rainbow 2>&1 </dev/null || true)"
grep -q "must be classic or aether" <<< "$out" || fail "bad --interface accepted"
out="$("$REPO_DIR/install.sh" --install --mode bogus 2>&1 </dev/null || true)"
grep -q "must be minimal, recommended or complete" <<< "$out" || fail "bad --mode accepted"
echo "PASS: invalid options are rejected"
# A partial install deploys only what was chosen, and an update keeps that choice.
P="$(mktemp -d)"
mkdir -p "$P/.config/waybar" && echo '{"mine": 1}' > "$P/.config/waybar/config"
HOME="$P" XDG_CONFIG_HOME="$P/.config" XDG_STATE_HOME="$P/.local/state" XDG_CACHE_HOME="$P/.cache" \
    "$REPO_DIR/install.sh" --install --no-packages --components hyprland,terminal >/dev/null </dev/null || fail "partial --install failed"
[ "$(readlink "$P/.config/kitty")" = "$REPO_DIR/config/kitty" ] || fail "selected component (terminal) not deployed"
[ "$(readlink "$P/.config/hypr")" = "$REPO_DIR/config/hypr" ] || fail "selected component (hyprland) not deployed"
[ "$(cat "$P/.config/waybar/config")" = '{"mine": 1}' ] && [ ! -L "$P/.config/waybar" ] || fail "an unselected component's config was replaced"
[ -x "$P/.local/bin/aether" ] || fail "AetherOS commands not deployed with a partial install"
[ "$(cat "$P/.config/aether-shell/components")" = "hyprland terminal" ] || fail "component selection not saved"
[ -f "$P/.config/aether-shell/hypr/user.conf" ] || fail "user.conf (sourced by hyprland.conf) not created"
ls "$P/.local/state/aether/reports/"install-*.txt >/dev/null 2>&1 || fail "no installation report written"
rm -rf "$P"
echo "PASS: partial install deploys only the chosen components and writes a report"

# Keybinds and scripts of a replaced Hyprland config are kept for the user.
P="$(mktemp -d)"
mkdir -p "$P/.config/hypr/scripts"
printf 'bind = SUPER, Q, exec, my-terminal\n' > "$P/.config/hypr/hyprland.conf"
echo 'echo mine' > "$P/.config/hypr/scripts/mine.sh"
HOME="$P" XDG_CONFIG_HOME="$P/.config" XDG_STATE_HOME="$P/.local/state" XDG_CACHE_HOME="$P/.cache" \
    "$REPO_DIR/install.sh" --install --no-packages --components hyprland >/dev/null </dev/null || fail "install over an existing Hyprland config failed"
grep -q '^# bind = SUPER, Q, exec, my-terminal$' "$P/.config/aether-shell/hypr/user.conf" || fail "the user's keybinds were not imported (commented) into user.conf"
[ -f "$P/.config/aether-shell/user/hypr-scripts/mine.sh" ] || fail "the user's Hyprland scripts were not kept"
rm -rf "$P"
echo "PASS: an existing Hyprland config's keybinds and scripts are preserved"
echo
echo "All installer checks passed."
