#!/usr/bin/bash
# Static structural checks on every .qml file: brace/parenthesis balance,
# and that every relative import ("../foo") actually resolves to a real
# directory. This is the same check that was run manually after writing
# every QML file during development — formalized so it's re-checked
# automatically instead of relying on memory.
#
# This does NOT validate QML semantics, type usage, or whether the file
# would actually load in Quickshell — that needs qmllint and a live Qt6/
# Quickshell installation, neither of which exists in this environment.
# See tests/services/README.md for why that gap can't be closed here.

set -uo pipefail  # deliberately not -e — see note below
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHELL_DIR="$REPO_DIR/config/quickshell/aether-shell"
failed=0

mapfile -t QML_FILES < <(find "$SHELL_DIR" -name "*.qml")
echo "Checking ${#QML_FILES[@]} QML files..."
echo

for f in "${QML_FILES[@]}"; do
    rel="${f#"$SHELL_DIR"/}"
    open_brace=$(grep -o '{' "$f" | wc -l); open_brace=${open_brace:-0}
    close_brace=$(grep -o '}' "$f" | wc -l); close_brace=${close_brace:-0}
    open_paren=$(grep -o '(' "$f" | wc -l); open_paren=${open_paren:-0}
    close_paren=$(grep -o ')' "$f" | wc -l); close_paren=${close_paren:-0}

    ok=1
    if [ "$open_brace" -ne "$close_brace" ]; then
        echo "FAIL: $rel — brace mismatch ($open_brace open, $close_brace close)"
        ok=0
    fi
    if [ "$open_paren" -ne "$close_paren" ]; then
        echo "FAIL: $rel — paren mismatch ($open_paren open, $close_paren close)"
        ok=0
    fi

    # Every `import "../something"` should resolve to a real directory
    # relative to this file's own location.
    while IFS= read -r imp; do
        target_dir="$(cd "$(dirname "$f")/$imp" 2>/dev/null && pwd)"
        if [ -z "$target_dir" ]; then
            echo "FAIL: $rel — import \"$imp\" does not resolve to a real directory"
            ok=0
        fi
    done < <(grep -oE 'import "\.\./[^"]*"' "$f" | sed -E 's/import "(.*)"/\1/')

    [ "$ok" -eq 1 ] && [ "${VERBOSE:-0}" = "1" ] && echo "PASS: $rel"
    [ "$ok" -eq 0 ] && failed=1
done

echo
if [ "$failed" -eq 0 ]; then
    echo "PASS: all ${#QML_FILES[@]} QML files structurally sound"
else
    echo "FAIL: see above"
    exit 1
fi
