#!/usr/bin/env python3
"""Runs the shell's Quickshell-independent QML (theme/, animation/,
graphics/, parts of core/ and components/) in a real Qt Quick scene and
checks behaviour and rendered pixels.

What this proves: the spring engine integrates, settles and stops; motion
settings are honoured; palettes resolve; every shader compiles *and draws
the expected pixels* through Qt's OpenGL RHI (Mesa llvmpipe under Xvfb in
CI); materials fall back when shaders are disabled.

What it does not prove: anything needing Quickshell itself (layer-shell
windows, Hyprland IPC, PipeWire, PAM). Those need a live session.

Usage: harness.py [test-file ...]   (default: every tst_*.qml here)
Environment: needs PySide6 (pip install PySide6-Essentials PySide6-Addons)
and a display — run under `xvfb-run -a` with QT_QPA_PLATFORM=xcb.
Exit codes: 0 pass, 1 failures, 77 skipped (no PySide6/display).
"""

import glob
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
SHELL = os.path.join(REPO, "config", "quickshell", "aether-shell")

# Directories copied into the scratch tree, and which files of each are
# loadable without Quickshell (anything importing Quickshell.Io/Wayland/...
# is left out of the qmldir and therefore unavailable to the tests).
EXPOSE = {
    "theme": None,          # None = every .qml file
    "animation": None,
    "graphics": None,
    "core": ["AnimationCoordinator", "Logger"],
    "policy": [],
    "components": ["Switch", "Slider", "BatteryIcon", "RadialGauge", "GlassPanel", "AetherIcon", "LiquidToggle",
                   "MotionCard", "SectionLabel", "FocusRing", "IconButton"],
}

STUB_SINGLETON = """import QtQml
// Test stub for Quickshell's Singleton: a QObject that can own children.
QtObject { default property list<QtObject> data }
"""


def build_tree(dst):
    for d, allow in EXPOSE.items():
        src = os.path.join(SHELL, d)
        shutil.copytree(src, os.path.join(dst, d))
        lines = []
        for f in sorted(os.listdir(src)):
            if not f.endswith(".qml"):
                continue
            name = f[:-4]
            if allow is not None and name not in allow:
                continue
            with open(os.path.join(src, f), encoding="utf-8") as fh:
                singleton = "pragma Singleton" in fh.read()
            lines.append(("singleton %s %s" % (name, f)) if singleton else ("%s %s" % (name, f)))
        with open(os.path.join(dst, d, "qmldir"), "w") as fh:
            fh.write("\n".join(lines) + "\n")
    stub = os.path.join(dst, "stubs", "Quickshell")
    os.makedirs(stub)
    with open(os.path.join(stub, "Singleton.qml"), "w") as fh:
        fh.write(STUB_SINGLETON)
    with open(os.path.join(stub, "qmldir"), "w") as fh:
        fh.write("module Quickshell\nSingleton 1.0 Singleton.qml\n")
    os.makedirs(os.path.join(dst, "tests"))
    for f in glob.glob(os.path.join(HERE, "tst_*.qml")) + glob.glob(os.path.join(HERE, "*.js")):
        shutil.copy(f, os.path.join(dst, "tests"))


RUNNER = r'''
import sys
from PySide6.QtCore import QTimer, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
app = QGuiApplication(sys.argv[:1])
eng = QQmlApplicationEngine()
eng.addImportPath(sys.argv[2])
eng.warnings.connect(lambda ws: [print("QMLWARN " + w.toString()) for w in ws])
eng.quit.connect(app.quit)
eng.exit.connect(app.exit)
eng.load(QUrl.fromLocalFile(sys.argv[1]))
if not eng.rootObjects():
    print("FAIL: test file did not load")
    sys.exit(3)
QTimer.singleShot(int(sys.argv[3]), lambda: (print("FAIL: timed out"), app.exit(4)))
sys.exit(app.exec())
'''


def check_pixels(lines):
    """Evaluate pixel assertions printed by a test:
        SHOT <png path>
        PIX name|x|y|r|g|b|tol        colour within tol per channel
        PIXMIN name|x|y|ch|min         channel (r/g/b) at least min
        PIXMAX name|x|y|ch|max         channel at most max
        PIXDIFF name|x1|y1|x2|y2|min   sum of channel differences at least min
    Each becomes a PASS/FAIL line."""
    from PySide6.QtGui import QImage
    img = None
    out = []
    for line in lines:
        if line.startswith("SHOT "):
            img = QImage(line[5:].strip())
            out.append(("PASS" if img.width() > 0 else "FAIL") + " frame captured (%dx%d)" % (img.width(), img.height()))
            continue
        kind = line.split(" ", 1)[0]
        if kind == "INK":
            # INK name|x|y|w|h|min — at least min pixels in the box are non-black.
            f = line.split(" ", 1)[1].split("|")
            if img is None or img.width() == 0:
                out.append("FAIL %s (no frame)" % f[0])
                continue
            x0, y0, w, h, need = (int(v) for v in f[1:])
            ink = sum(1 for yy in range(y0, y0 + h) for xx in range(x0, x0 + w) if img.pixelColor(xx, yy).value() > 60)
            out.append("%s %s (%d lit pixels)" % ("PASS" if ink >= need else "FAIL", f[0], ink))
            continue
        if kind not in ("PIX", "PIXMIN", "PIXMAX", "PIXDIFF"):
            out.append(line)
            continue
        f = line.split(" ", 1)[1].split("|")
        name = f[0]
        if img is None or img.width() == 0:
            out.append("FAIL %s (no frame)" % name)
            continue
        def at(x, y):
            c = img.pixelColor(int(x), int(y))
            return {"r": c.red(), "g": c.green(), "b": c.blue()}
        if kind == "PIX":
            c = at(f[1], f[2])
            want = (int(f[3]), int(f[4]), int(f[5]))
            good = all(abs(c[k] - w) <= int(f[6]) for k, w in zip("rgb", want))
            detail = "got %d,%d,%d want %s" % (c["r"], c["g"], c["b"], ",".join(map(str, want)))
        elif kind in ("PIXMIN", "PIXMAX"):
            v = at(f[1], f[2])[f[3]]
            good = v >= int(f[4]) if kind == "PIXMIN" else v <= int(f[4])
            detail = "%s=%d, %s %s" % (f[3], v, ">=" if kind == "PIXMIN" else "<=", f[4])
        else:
            a, b = at(f[1], f[2]), at(f[3], f[4])
            d = sum(abs(a[k] - b[k]) for k in "rgb")
            good, detail = d >= int(f[5]), "difference %d >= %s" % (d, f[5])
        out.append("%s %s (%s)" % ("PASS" if good else "FAIL", name, detail))
    return out


def main(argv):
    try:
        import PySide6  # noqa: F401
    except ImportError:
        print("SKIP: PySide6 not installed (pip install PySide6-Essentials PySide6-Addons)")
        return 77
    if not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
        print("SKIP: no display (run under: xvfb-run -a env QT_QPA_PLATFORM=xcb ...)")
        return 77
    tests = argv or sorted(glob.glob(os.path.join(HERE, "tst_*.qml")))
    failed = 0
    with tempfile.TemporaryDirectory(prefix="aether-qml-") as tmp:
        build_tree(tmp)
        runner = os.path.join(tmp, "runner.py")
        with open(runner, "w") as fh:
            fh.write(RUNNER)
        env = dict(os.environ, QT_QUICK_BACKEND="", QSG_RHI_BACKEND=os.environ.get("QSG_RHI_BACKEND", "opengl"),
                   QML_IMPORT_TRACE="", LC_ALL="C.UTF-8")
        for t in tests:
            path = os.path.join(tmp, "tests", os.path.basename(t))
            proc = subprocess.run([sys.executable, runner, path, os.path.join(tmp, "stubs"), "60000"],
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env, timeout=120)
            out = proc.stdout
            lines = [l.split("qml: ", 1)[1] if "qml: " in l else l for l in out.splitlines()]
            lines = check_pixels(lines)
            checks = [l for l in lines if l.startswith(("PASS", "FAIL"))]
            errors = [l for l in lines if l.startswith("QMLWARN") or ("Error" in l or "error" in l or "is not a type" in l or "TypeError" in l
                                           or "ReferenceError" in l) and not l.startswith("PASS")]
            bad = proc.returncode != 0 or any(c.startswith("FAIL") for c in checks) or not checks or errors
            print("%s %s (%d checks)" % ("FAIL" if bad else "PASS", os.path.basename(t), len(checks)))
            for c in checks:
                if c.startswith("FAIL") or bad:
                    print("    " + c)
            for e in errors[:15]:
                print("    ! " + e)
            if bad:
                failed += 1
    print("%d test file(s), %d failed" % (len(tests), failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
