## What and why

## Checklist
- [ ] `bash tests/run-all.sh` passes (with PySide6 + Xvfb it also runs the runtime QML suite)
- [ ] New config keys are declared in `core/Config.qml` and `python3 tools/gen_schema.py` was run
- [ ] CLI changes: `python3 tools/gen_cli_reference.py` was run
- [ ] Shader changes: `.qsb` rebuilt with Qt 6.7's `qsb` (CONTRIBUTING.md)
- [ ] No command strings built from user/config data; no new privileged operations
- [ ] PROGRESS.md / docs updated with an honest status (tested / implemented / needs hardware)
