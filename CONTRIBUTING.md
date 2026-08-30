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
