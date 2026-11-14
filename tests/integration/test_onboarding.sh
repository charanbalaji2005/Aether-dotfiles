#!/usr/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# The onboarding installer, end to end, on a pseudo-terminal with numbered
# prompts (AETHER_UI=plain), in an isolated $HOME, without packages:
#   welcome screen (logo, system summary, copyright) → first-run support screen
#   with the repository link → main menu → Recommended → live progress →
#   final summary → final menu → Exit; the support screen is shown only once.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
# Never touch the desktop this runs from: with Hyprland, Wayland and the
# session bus in reach, an install in a temporary HOME restarts the real
# Waybar from that HOME (which is then deleted, and the bar dies).
unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY DISPLAY
XDG_RUNTIME_DIR="$(mktemp -d)"
export XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/no-bus"
if [ "$(id -u)" -eq 0 ]; then echo "SKIP: install.sh refuses root by design"; exit 0; fi
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
run() {
    env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/home/.local/state" XDG_CACHE_HOME="$T/home/.cache" \
        AETHER_TEST_OS_ID=fedora AETHER_TEST_OS_VERSION=42 AETHER_UI=plain LANG=C.UTF-8 TERM=xterm-256color \
        python3 -I "$REPO_DIR/tests/integration/onboarding_driver.py" "$1" "$REPO_DIR/install.sh" --no-packages
}
mkdir -p "$T/home"
run "$T/first.out" > "$T/first.res" || fail "onboarding did not complete: $(cat "$T/first.res")"
text="$(sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' "$T/first.out" | tr -d '\r')"
grep -q "Neelampalli Charan Balaji" <<< "$text" || fail "copyright owner not shown"
grep -q "https://github.com/charanbalaji2005/Aether-dotfiles" <<< "$text" || fail "repository link not shown"
grep -q "Star the repository" <<< "$text" || fail "first-run support screen not shown"
grep -q "Kernel" <<< "$text" && grep -q "Memory" <<< "$text" || fail "system summary not shown"
grep -q "\[1/[0-9]*\] Downloading and installing dependencies" <<< "$text" || fail "numbered progress steps not shown"
grep -q "AetherOS install completed successfully" <<< "$text" || fail "completion screen missing"
grep -q "Skipped:    login-manager" <<< "$text" || fail "skipped components not listed"
[ "$(readlink "$T/home/.config/waybar")" = "$REPO_DIR/config/waybar" ] || fail "the onboarding didn't deploy the configs"
ls "$T/home/.local/state/aether/reports/"install-*.txt >/dev/null || fail "no report"
echo "PASS: onboarding installs end to end and shows the welcome, support and completion screens"

# Second run: the support screen is not shown again (the driver cancels the
# main menu's first prompt, so stop after the welcome).
out="$(env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/home/.local/state" XDG_CACHE_HOME="$T/home/.cache" \
    AETHER_UI=plain LANG=C.UTF-8 TERM=xterm-256color python3 -I -c '
import os, pty, sys, select, time
pid, fd = pty.fork()
if pid == 0: os.execv(sys.argv[1], sys.argv[1:])
buf = b""; t = time.time()
while time.time() - t < 60:
    if select.select([fd], [], [], 0.3)[0]:
        try: d = os.read(fd, 65536)
        except OSError: break
        if not d: break
        buf += d
    if b"Press Enter to continue" in buf and b"SENT" not in buf: os.write(fd, b"\n"); buf += b"SENT"
    if buf.count(b"(q to cancel)") >= 1 and b"SENT" in buf: os.write(fd, b"q\n"); break
os.waitpid(pid, 0); sys.stdout.write(buf.decode("utf-8", "replace"))' "$REPO_DIR/install.sh" 2>&1)"
grep -q "Star the repository" <<< "$out" && fail "support screen shown twice"
grep -q "Start installation" <<< "$out" || fail "main menu not shown on the second run"
echo "PASS: the support screen is shown only on the first run"
