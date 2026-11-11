# Contributing

## Before you start

Check `config/quickshell/aether-shell/PROGRESS.md` and the top-level `PROGRESS.md` first — they
track exactly what's implemented, what's flagged as unverified, and what's not started. Don't
assume a feature works because a file exists for it; the status tables are kept honest on
purpose.

## Making changes

1. **Scripts** — run `shellcheck` on anything under `scripts/` or `tests/` before opening a PR.
   `tests/scripts/test_shellcheck.sh` does this for the whole repo; run it locally.
2. **Hyprland config** — run `tests/hyprland/test_config_syntax.sh` after touching anything in
   `config/hypr/`.
3. **QML** — run `tests/shell/test_qml_structure.sh` after touching anything in
   `config/quickshell/aether-shell/`. If you have a real Quickshell environment, please also
   actually run the shell and confirm your change works — most of this codebase's QML has only
   been verified against documentation, not a live runtime (see the shell's PROGRESS.md).
4. **Scripts that touch the filesystem** (install/backup/restore/uninstall) — test them against
   an isolated `$HOME`, the way `tests/integration/test_symlink_lifecycle.sh` does. Never test
   destructive operations against your real home directory.

Run everything at once with `tests/run-all.sh`.

## Pull requests

- Update `PROGRESS.md` (top-level or the shell's, whichever applies) if you're changing a
  feature's status. Don't mark something `TESTED` or `VERIFIED` unless you actually ran it —
  see the status definitions at the top of `PROGRESS.md`.
- If you're adding a new external dependency (a binary, a library, a font, an icon set),
  document it in the relevant `THIRD_PARTY.md` with its license.
- Keep the layering rules in `ARCHITECTURE.md` (both the top-level one and the shell's) —
  UI components don't talk to the system directly; that goes through a service.

## Reporting issues

Include the output of `scripts/doctor.sh` — most "X doesn't work" reports turn out to be a
missing optional dependency it would have caught.

## 0.3 rules of the road

* **Run `bash tests/run-all.sh` before every PR.** With PySide6 + Xvfb installed it also runs the
  runtime QML suite; new pure-Qt components should get a `tests/shell/runtime/tst_*.qml`.
* **Layering:** theme/, core/, components/, animation/ and graphics/ must not import services/
  (shell.qml bridges them). That's what keeps them runtime-testable.
* **Config keys** are declared once in `core/Config.qml` (type, default, enum choices in the
  trailing comment); then run `python3 tools/gen_schema.py`. CI fails if you forget.
* **Shaders:** edit `.frag`, then rebuild the `.qsb` with **Qt 6.7's** `qsb`
  (`pip install "PySide6-Essentials==6.7.3" "PySide6-Addons==6.7.3"`;
  `qsb --glsl "300 es,150" -o x.frag.qsb x.frag`) so it loads on Fedora 41+. CI compares them.
  Never name a uniform after an `Item` property (`focus`, `x`, `scale`, …).
* **Palettes** live only in `theme/Palettes.js` (strict JSON between the markers).
* **CLI changes:** run `python3 tools/gen_cli_reference.py` (CI checks docs/CLI_REFERENCE.md).
* **Settings sections:** add the id to `Settings.qml`, `SettingsIndex.js` and the assistant's
  `SETTINGS_SECTIONS` — a test keeps the three in step.
* **New shell types:** import their directory; `tests/shell/qml_imports.py` catches misses.
* **Widgets:** see docs/WIDGETS.md; built-in widgets must pass the same scanner as third-party ones.
* **Security:** no setting, profile or rule may carry a command; launch processes with argv
  lists; for `sh -c` use a constant script and pass values positionally. The invariant test
  enforces it. Never add a second unlock path to the lock screen.
* **Honesty:** if something isn't wired to a real provider, it doesn't ship as if it were.
  Update PROGRESS.md with the right status tier.

