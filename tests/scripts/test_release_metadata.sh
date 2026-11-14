#!/usr/bin/bash
# Release metadata:
#  * one version everywhere: lib/aether __version__, the RPM spec, the
#    PKGBUILD and the top CHANGELOG heading;
#  * every relative link in the Markdown docs points at a file that exists;
#  * publisher placeholders (repo URL, maintainer) — reported always, and a
#    failure with --strict (the release workflow uses --strict).
set -uo pipefail
REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
strict=0
[ "${1:-}" = "--strict" ] && strict=1
failed=0
fail() { echo "FAIL: $1"; failed=1; }

ver="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import aether; print(aether.__version__)' "$REPO_DIR/lib")"
spec_ver="$(sed -n 's/^%global upstream_version //p' "$REPO_DIR/packaging/rpm/aetheros-dotfiles.spec")"
pkg_ver="$(sed -n 's/^_upstreamver=//p' "$REPO_DIR/packaging/arch/PKGBUILD")"
pkg_pkgver="$(sed -n 's/^pkgver=//p' "$REPO_DIR/packaging/arch/PKGBUILD")"
log_ver="$(grep -m1 -oE '^## [0-9][^ ]*' "$REPO_DIR/CHANGELOG.md" | cut -c4-)"
for pair in "spec:$spec_ver" "PKGBUILD:$pkg_ver" "CHANGELOG:$log_ver"; do
    [ "${pair#*:}" = "$ver" ] || fail "${pair%%:*} version ${pair#*:} != $ver"
done
# Arch pkgver can't contain '-': 1.0.0-rc.2 -> 1.0.0rc2
[ "$pkg_pkgver" = "$(sed -E 's/-rc\.([0-9]+)$/rc\1/' <<< "$ver")" ] || fail "PKGBUILD pkgver $pkg_pkgver doesn't match $ver"
[ "$failed" -eq 0 ] && echo "PASS: version $ver is consistent (lib, RPM spec, PKGBUILD, CHANGELOG)"

broken="$(python3 - "$REPO_DIR" <<'PY'
import os, re, sys
root = sys.argv[1]
bad = []
for base, dirs, files in os.walk(root):
    dirs[:] = [d for d in dirs if d not in (".git", "dist", "node_modules")]
    for f in files:
        if not f.endswith(".md"):
            continue
        path = os.path.join(base, f)
        text = open(path, encoding="utf-8").read()
        text = re.sub(r"```.*?```", "", text, flags=re.S)
        for target in re.findall(r"\]\(([^)\s]+)\)", text):
            if re.match(r"^(https?:|mailto:|#)", target):
                continue
            t = target.split("#", 1)[0]
            if t and not os.path.exists(os.path.normpath(os.path.join(base, t))):
                bad.append("%s -> %s" % (os.path.relpath(path, root), target))
print("\n".join(bad))
PY
)"
if [ -n "$broken" ]; then
    printf '%s\n' "$broken" | sed 's/^/FAIL: broken link /'
    failed=1
else
    echo "PASS: every relative documentation link resolves"
fi

# Every file with a shebang is executable; no executable lacks one.
perm="$(cd "$REPO_DIR" && find . \( -path ./.git -o -path ./dist \) -prune -o -type f -print | while IFS= read -r f; do
    if head -c2 "$f" | grep -q '#!'; then [ -x "$f" ] || echo "shebang but not executable: $f"
    elif [ -x "$f" ]; then case "$f" in *.png|*.jpg|*.webp|*.gif) ;; *) echo "executable without a shebang: $f" ;; esac
    fi
done)"
if [ -n "$perm" ]; then printf 'FAIL: %s\n' "$perm"; failed=1; else echo "PASS: script permissions match their shebangs"; fi

if ! out="$(bash "$REPO_DIR/tools/set-publisher.sh" --check 2>&1)"; then
    if [ "$strict" -eq 1 ]; then
        echo "$out"
        fail "publisher placeholders remain (a release can't ship them)"
    else
        echo "NOTE: publisher placeholders remain — set them before tagging: tools/set-publisher.sh --repo <user>/<repo> --maintainer \"Name <email>\""
    fi
else
    echo "PASS: no publisher placeholders"
fi
exit "$failed"
