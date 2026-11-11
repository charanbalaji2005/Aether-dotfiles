# Testing

```sh
bash tests/run-all.sh
```

| Suite | Needs | Proves |
|---|---|---|
| `scripts/test_shellcheck.sh` | shellcheck | every shell script, all severities |
| `scripts/scan_repo_hygiene.sh` | — | no leftover work markers, stubs, machine paths |
| `hyprland/test_config_syntax.sh` | python3 | fragments sourced, version-selected rules, rule files equivalent, no keybind conflicts |
| `shell/test_qml_structure.sh` | python3 | brace/paren balance, imports resolve, every used shell type imported |
| `shell/test_qml_lint.sh` | `pyside6-qmllint` or `qmllint` | Qt's QML linter on every file |
| `shell/test_security_invariants.sh` | python3 | single PAM unlock path; constant `sh -c` scripts; no command actions |
| `shell/runtime/run_runtime_tests.sh` | PySide6 (+ Xvfb without a display) | springs, motion, palettes, pressure policy, every shader, wallpaper stage, components, icon kit — rendered through Qt's OpenGL path with pixel checks |
| `config/test_config_files.sh` | python3 | systemd units, package lists, schema, every IPC call resolves |
| `python/run_python_tests.sh` | python3 ≥ 3.9 | backend against fixture hardware, local HTTP servers, fake NVML |
| `integration/test_symlink_lifecycle.sh` | — | link/backup/restore/uninstall |
| `integration/test_installer.sh` | **non-root** user | `install.sh` check/dry-run/install/reinstall/resume/rollback in a fake home |

```sh
pip install PySide6-Essentials PySide6-Addons     # qmllint + runtime suite
sudo dnf install xorg-x11-server-Xvfb shellcheck
```

Generated files are checked too: `python3 tools/gen_schema.py --check`,
`python3 tools/gen_cli_reference.py --check`.

**What the suites can't prove** — anything needing a live Quickshell + Hyprland session, PAM,
PipeWire, BlueZ, physical GPUs or multiple monitors. Use the checklist in
[HARDWARE.md](HARDWARE.md#validation-checklist-needed-before-calling-a-release-100) and record
results in TEST_REPORT.md.
