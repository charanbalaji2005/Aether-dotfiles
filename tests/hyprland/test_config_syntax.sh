#!/usr/bin/bash
# Static checks on the Hyprland config: brace balance and that
# hyprland.conf actually sources every module file that exists. This is
# NOT a real Hyprland config parse (that needs Hyprland itself) — it
# catches the class of error a typo or a forgotten `source =` line would
# cause, nothing more.

set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HYPR_DIR="$REPO_DIR/config/hypr"
failed=0

for f in "$HYPR_DIR"/*.conf; do
    open=$(grep -o '{' "$f" | wc -l || true)
    close=$(grep -o '}' "$f" | wc -l || true)
    if [ "$open" -eq "$close" ]; then
        echo "PASS: $(basename "$f") braces balanced ($open/$close)"
    else
        echo "FAIL: $(basename "$f") braces unbalanced ($open open, $close close)"
        failed=1
    fi
done

echo
for f in "$HYPR_DIR"/*.conf; do
    name="$(basename "$f")"
    [ "$name" = "hyprland.conf" ] && continue
    if grep -q "source = ~/.config/hypr/$name" "$HYPR_DIR/hyprland.conf"; then
        echo "PASS: hyprland.conf sources $name"
    else
        echo "FAIL: hyprland.conf does NOT source $name — it will never be loaded"
        failed=1
    fi
done

echo
if [ "$failed" -eq 0 ]; then
    echo "PASS: all Hyprland config checks passed"
else
    echo "FAIL: see above"
    exit 1
fi
