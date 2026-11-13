# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# install-scripts/waybar.sh — Waybar, the macOS-inspired top bar.
# Sourced by install.sh (see functions/components.sh for the contract).

comp_waybar_validate() {
    v_need waybar waybar waybar
    v_link waybar "$HOME/.config/waybar"
    local bad
    bad="$(python3 -I - "$HOME/.config/waybar" <<'PY' 2>&1
import json, os, re, sys
root = sys.argv[1]
bad = []
for d in ("", "layouts"):
    p = os.path.join(root, d)
    for f in sorted(os.listdir(p)) if os.path.isdir(p) else []:
        if f.endswith((".jsonc", ".json")) or f == "config":
            t = open(os.path.join(p, f), encoding="utf-8").read()
            t = re.sub(r"(?m)^\s*//.*$", "", t)
            t = re.sub(r",(\s*[}\]])", r"\1", t)
            try:
                json.loads(t)
            except ValueError as e:
                bad.append("%s: %s" % (os.path.join(d, f), e))
print("\n".join(bad))
PY
)"
    [ -z "$bad" ] && v_pass waybar "every bar layout parses" || v_fail waybar "invalid layout(s): $bad"
}
