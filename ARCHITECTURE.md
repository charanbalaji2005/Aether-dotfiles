# Architecture

This covers the repository as a whole. The shell's internal QML architecture (layering rules,
service pattern) is in `config/quickshell/aether-shell/ARCHITECTURE.md`.

## Layers

```
┌────────────────────────── Desktop shell (Quickshell / QML) ──────────────────────────┐
│ shell/        bar · launcher · control centre · dashboard · notifications · OSD ·   │
│               settings · lock · power menu · wallpaper · clipboard · bluetooth      │
│ components/   PopupPanel, GlassPanel, ToggleTile, StatTile, Sparkline, AetherIcon…  │
│ services/     one system concern each (Audio, Network, SystemMonitor, Theme, …)     │
│ theme/ core/  design tokens · config · event bus · shared UI state                  │
└───────────────┬────────────────────────────────────────────┬──────────────────────────┘
                │ Quickshell modules (Hyprland, PipeWire,     │ `aether telemetry --stream`,
                │ UPower, BlueZ, MPRIS, notifications)        │ `aether hardware --json`,
                │ + nmcli, wpctl, brightnessctl, hyprsunset,  │ `aether theme accent`,
                │   powerprofilesctl, hyprctl, cliphist, grim │ `aether performance hyprland`
                ▼                                             ▼
        Linux / D-Bus / Wayland             ┌──── AetherOS CLI backend (lib/aether, Python) ────┐
                                            │ hw/        system · cpu · gpu (PCI sysfs)         │
                                            │ graphics/  stack (Mesa/GL/Vulkan/VA-API) ·        │
                                            │            nvidia (branch, akmods, Secure Boot) · │
                                            │            report (detect/drivers/verify) ·       │
                                            │            hyprconf (hardware/compat fragments)   │
                                            │ telemetry · performance · theme · cli · util      │
                                            └────────────────────────────────────────────────────┘
┌────────────────────────── Dotfiles layer ─────────────────────────────────────────────┐
│ config/hypr (Hyprland) · config/kitty · config/zsh · theme/gtk · theme/wallpapers     │
│ scripts/  bootstrap · setup-symlinks · backup · restore · uninstall · update · doctor │
│ scripts/bin/  aether (CLI entry) · aether-screenshot · aether-wallpaper              │
│ system/systemd/  aether-shell.service · aether-clipboard.service                     │
│ packages/  fedora (required + optional) · arch · generic                             │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

## Why a Python backend

The shell previously forked `cat`/`df` every two seconds and had no way to read GPUs, sensors
or driver state. Hardware detection needs parsing (PCI uevent, hwmon, `nvidia-smi`, `vainfo`,
`vulkaninfo`, `mokutil`, `dnf`) that is fragile in QML JavaScript and in bash, and it needs
tests. So:

* **Standard library only, Python ≥ 3.9.** Fedora always ships python3 (dnf depends on it);
  nothing is pip-installed.
* **One entry point.** `scripts/bin/aether` keeps its bash session commands and dispatches
  `system|hardware|cpu|gpu|graphics|performance|diagnostics|repair|hyprland|theme|telemetry`
  to `python3 -I` (isolated mode: no PYTHONPATH, no user site, no CWD imports).
* **Testable by construction.** Every read of `/sys`, `/proc`, `/etc` and every subprocess goes
  through `util.Context`. Tests point it at fixture trees (`AETHER_SYSROOT`) and canned command
  output (`AETHER_COMMAND_FIXTURES`); real use reads the live system. Commands always run as
  argv lists — never through a shell.
* **One telemetry process.** The shell runs a single long-lived `aether telemetry --stream`
  (JSON line per interval) instead of forking per metric. Sensors are discovered once. A
  runtime-suspended dGPU is never queried (that would wake it). NVIDIA desktops use one
  `nvidia-smi -lms` child. Unavailable values are `null` with a reason. If the backend can't
  run, `SystemMonitorService` falls back to the original `/proc` polling.

## Per-machine state lives outside the repo

`config/` is symlinked into `~/.config`, so anything generated inside it would show as
uncommitted changes and would be wrong on the next machine. Machine-specific files therefore
live in `~/.config/aether-shell/`:

| File | Written by |
|---|---|
| `config.json` | the shell's Settings (FileView/JsonAdapter, live reload); `aether theme` edits it atomically |
| `hypr/hardware.conf` | `aether graphics configure` |
| `hypr/compat.conf` | `aether hyprland compat` |
| `hypr/profile.conf` | `aether performance hyprland <profile>` |

`setup-symlinks.sh` creates the three fragments (comments only) so Hyprland's `source =`
lines never fail; generators back up the previous version (`*.bak-<ts>`, last 5 kept) and show a
diff before replacing a hand-edited file.

## Safety rules (enforced in code and tests)

* No command runs as root by itself; privileged steps are `sudo <exact command>`, printed first.
* Confirmation defaults to *no* when stdin is not a terminal.
* Driver installation is a plan → typed confirmation (`install`) → execution with a JSON record
  and rollback instructions. Unknown GPUs are never auto-installed. Secure Boot is never
  disabled (tests assert no such command can appear in a plan).
* Hybrid laptops never get NVIDIA forced globally (tested).
* Shell → helper calls pass values as positional arguments (`Paths.helper()`); the previous
  wallpaper path interpolation into `bash -c` was a command-injection bug and is fixed.
* `restore.sh` only restores allowlisted paths and rejects traversal.

## Scripts

Unchanged responsibilities, extended:

- `install.sh` → `scripts/bootstrap.sh`: packages (asks), Quickshell build (asks), backup, links,
  hardware detection, fragments, optional NVIDIA plan, services, validation.
- `scripts/setup-symlinks.sh`: links only + creates missing fragments. No sudo.
- `scripts/backup.sh` / `restore.sh` / `uninstall.sh`: the safety net (now also backs up
  `config.json` and the fragments).
- `scripts/doctor.sh`: dependency/session checks; `aether diagnostics` runs it plus config,
  graphics, power and sensor checks.
- `scripts/update.sh`: pull, re-link, validate with `aether hyprland`.

Symlink targets remain an explicit list (adding a directory is a deliberate one-line change).

## Testing philosophy

Unchanged: every test runs a real tool or real code with real assertions; gaps are documented,
not papered over. See `tests/run-all.sh` and [TEST_REPORT.md](TEST_REPORT.md):

| Suite | What it really runs |
|---|---|
| `tests/scripts/test_shellcheck.sh` | shellcheck on every script |
| `tests/scripts/scan_repo_hygiene.sh` | leftover-marker / stub / hard-coded-path scan |
| `tests/hyprland/test_config_syntax.sh` | brace balance, source wiring, fragment ordering, no obsolete NVIDIA hacks, layer namespaces exist in QML |
| `tests/shell/test_qml_structure.sh` | brace/paren balance, import resolution |
| `tests/shell/test_qml_lint.sh` | Qt's `qmllint` — fails on real QML syntax errors |
| `tests/config/test_config_files.sh` | systemd units, package lists, JSON, every `Config.x.y` key declared, every IPC target exists |
| `tests/python/run_python_tests.sh` | ~85 unit tests: CPU/GPU detection, driver-branch selection, install-plan safety, hybrid rules, Secure Boot, telemetry, CLI end-to-end |
| `tests/integration/test_symlink_lifecycle.sh` | install/backup/restore/uninstall in a fake `$HOME` |
