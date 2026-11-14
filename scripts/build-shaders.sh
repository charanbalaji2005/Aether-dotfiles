#!/usr/bin/bash
# Compiles the shell's GLSL shaders (.frag) to Qt's .qsb format with the
# *installed* Qt's shader compiler.
#
# Why locally: a .qsb file is only guaranteed to load in the Qt version that
# produced it or newer. The repository ships prebuilt .qsb files as a
# convenience, but if your Qt is older than the one they were built with
# they won't load — so the installer rebuilds them here. Output goes to
# ~/.cache/aether-shell/shaders (never into the repository). If neither
# works, every effect falls back to its non-shader rendering.
#
# Needs `qsb` (Fedora: qt6-qtshadertools). Exits 1 if it's missing.

set -euo pipefail
REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
SRC="$REPO_DIR/config/quickshell/aether-shell/graphics/shaders"
OUT="${AETHER_SHADER_OUT:-${XDG_CACHE_HOME:-$HOME/.cache}/aether-shell/shaders}"

QSB="${QSB:-}"
if [ -z "$QSB" ]; then
    for cand in qsb qsb-qt6 /usr/lib64/qt6/bin/qsb /usr/lib/qt6/bin/qsb pyside6-qsb; do
        if command -v "$cand" >/dev/null 2>&1; then QSB="$cand"; break; fi
    done
fi
if [ -z "$QSB" ]; then
    echo "qsb not found (sudo dnf install qt6-qtshadertools). Shaders were not compiled."
    exit 1
fi

mkdir -p "$OUT"
failed=0; built=0
for frag in "$SRC"/*.frag; do
    [ -f "$frag" ] || continue
    name="$(basename "$frag")"
    # GLSL ES 3.00 + desktop 1.50 cover OpenGL (the default RHI backend on
    # Linux); SPIR-V for Vulkan is always embedded.
    if "$QSB" --glsl "300 es,150" -o "$OUT/$name.qsb.tmp" "$frag" 2>"$OUT/$name.log"; then
        mv "$OUT/$name.qsb.tmp" "$OUT/$name.qsb"
        rm -f "$OUT/$name.log"
        built=$((built + 1))
    else
        echo "FAIL: $name"
        sed 's/^/    /' "$OUT/$name.log"
        rm -f "$OUT/$name.qsb.tmp"
        failed=1
    fi
done
echo "Compiled $built shader(s) with $QSB into $OUT"
exit "$failed"
