#!/usr/bin/bash
# Runtime tests of the shell's Qt-only QML (animation engine, shaders,
# wallpaper stage, components) in a real Qt Quick scene with the OpenGL
# RHI. Needs PySide6 and a display; uses xvfb-run when there's no display.
# Skips (exit 0, says so) when either is unavailable.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! python3 -c "import PySide6" 2>/dev/null; then
    echo "SKIP: PySide6 not installed (pip install PySide6-Essentials PySide6-Addons)"; exit 0
fi
if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    if command -v xvfb-run >/dev/null 2>&1; then
        exec env QT_QPA_PLATFORM=xcb xvfb-run -a -s "-screen 0 1280x800x24" python3 "$HERE/harness.py" "$@"
    fi
    echo "SKIP: no display and no xvfb-run"; exit 0
fi
python3 "$HERE/harness.py" "$@"
rc=$?
[ "$rc" -eq 77 ] && exit 0
exit "$rc"
