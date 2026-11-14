# Architecture

The shell's internal QML architecture is in
[config/quickshell/aether-shell/ARCHITECTURE.md](config/quickshell/aether-shell/ARCHITECTURE.md).
This document covers the repository as a whole.

## Layers

```
┌──────────────────────────── AetherOS Shell (Quickshell / QML) ────────────────────────────┐
│ shell/       bar · dock · island · overview · launcher · control centre · dashboard ·    │
│              system centre · layouts · notifications · settings (+17 sections) · lock ·  │
│              OSD · wallpaper · gestures · power menu · clipboard · bluetooth            │
│ components/  GlassPanel, Switch, Slider, ChipGroup, BatteryIcon, RadialGauge, MotionCard…│
│ graphics/    shader materials (glass, glow, aurora, transition, depth) · WallpaperStage · │
│              ParticleField · ShaderLibrary          shaders/*.frag → *.frag.qsb         │
│ animation/   SpringValue (physics) · SpringBehavior · Reveal · GestureTracker           │
│ automation/  Rules.js (rule schema shared with Python)                                   │
│ services/    one system concern each — Hyprland, windows, audio, power, network, media, │
│              performance, automation, timers, recording, visualiser, wallpaper, video…  │
│ theme/ core/ tokens (Colors/Palettes, Metrics, Typography, Motion, Materials, Effects) · │
│              Config · EventBus · AnimationCoordinator · Logger · Paths                   │
└───────────────┬──────────────────────────────────────────────┬────────────────────────────┘
                │ Quickshell modules: Hyprland IPC, PipeWire,   │ `aether … --json` (CliService),
                │ UPower, BlueZ, MPRIS, notifications, PAM,     │ `aether telemetry --stream`
                │ session lock; hyprctl, nmcli, wpctl, cava,    │
                │ mpvpaper, wf-recorder (via helpers)           │
                ▼                                               ▼
        Linux / D-Bus / Wayland          ┌──────── aether CLI backend (lib/aether, Python ≥ 3.9, stdlib) ────────┐
                                         │ hw/ graphics/ telemetry nvml render performance capabilities         │
                                         │ config (schema v4+migrations) snapshots profiles palettes themes     │
                                         │ appearance layouts automation sysinfo inputconf displays autostart   │
                                         │ workspaces apps widgets ai/ (providers secrets registry service)     │
                                         │ audit redact · cli + cli_desktop + cli_v1                            │
                                         └───────────────────────────────────────────────────────────────────────┘
┌──────────────────────────── Dotfiles & system layer ──────────────────────────────────────┐
│ install.sh (onboarding · check · dry-run · install · update · restore · rollback)          │
│   functions/  ui (whiptail/plain, live panel) · detect · components · validate · support   │
│   install-scripts/  dependencies · deploy-dotfiles · services · one file per component     │
│   update.sh · restore.sh · assets/ (logo, SDDM theme)                                      │
│ scripts/  lib/common.sh (managed-path list, manifest) · setup-symlinks · backup · restore ·│
│           rollback · uninstall · build-shaders · doctor     bin/ aether · aether-terminal ·│
│           aether-record · aether-screenshot · aether-wallpaper                             │
│ config/hypr (rules.conf / rules-v2.conf, recovery.conf) · kitty · zsh (+ profiles/)       │
│ system/systemd  aether-shell · aether-shell-safe (OnFailure) · aether-clipboard · aether-idle│
│ packages/fedora packages (core) · components.tsv · recommended · optional · advanced ·    │
│                 repos.conf (COPR, consent)                                                 │
└────────────────────────────────────────────────────────────────────────────────────────────┘
```

## 1.0 additions at a glance

| Concern | Backend | Shell |
|---|---|---|
| GPU telemetry | `nvml.py` (ctypes NVML), `telemetry.py` (hybrid-safe) | `SystemMonitorService` (+ detail stream) |
| Rendering policy | `capabilities.py`, `render.py` | `PerformanceService` + `policy/Pressure.js` |
| Assistant | `ai/` (providers, keyring, registry, service), `audit.py`, `redact.py` | `AssistantService`, `KeyringService`, `shell/assistant` |
| Widgets | `widgets.py` (manifest, static scanner, install) | `WidgetService`, `shell/widgets` (`WidgetApi`, `WidgetLayer`) |
| Input / displays | `inputconf.py`, `displays.py` (watchdog) | `SystemSettingsService`, Keyboard/Mouse/Displays sections |
| Workspaces / startup | `workspaces.py`, `apps.py`, `autostart.py` | Workspaces/Startup sections, bar + overview names |
| Themes | `themes.py` + `palettes.py` | `ThemeService.userPalettes` → `Colors` |
| Privacy | `scripts/bin/aether-clip-store` | `PrivacyService`, `ClipboardService` retention, notification rules |

## Principles

* **Real data or nothing.** Every metric, device and window comes from the system; a missing
  provider makes the feature say *unavailable* and why. Nothing is simulated.
* **One source of truth per contract,** checked by tests:
  config schema — `core/Config.qml` → generated `lib/aether/_schema_data.py`;
  palettes — `theme/Palettes.js`, parsed by Python for terminals and Hyprland;
  automation rule tables — `automation/Rules.js` ≡ `lib/aether/automation.py`;
  action ids — `services/ActionService.qml` ≡ `config.ACTIONS`;
  managed paths — `scripts/lib/common.sh` for every install script.
* **Data, never code, crosses trust boundaries.** Imported profiles, settings and automation
  rules are validated against allowlists; there is no setting whose value is a command. Shell
  scripts launched from QML are constants with values passed positionally (`"$1"`); tests
  enforce it.
* **Least privilege.** Nothing runs as root by itself. Package installs are `sudo dnf …` shown
  first; updates open a terminal so you see the transaction; SELinux, firewall, Secure Boot,
  bootloader, kernel and display manager are never modified.
* **Idle costs nothing.** Springs stop when settled; FrameAnimation-driven work, the visualiser,
  thumbnails, process lists and polling exist only while a consumer is visible; telemetry is one
  long-lived process; window data refreshes on Hyprland events, debounced.
* **Graceful degradation.** Each shader effect has a non-shader rendering; a failed shader is
  recorded once and its fallback used for the session; optional QML (thumbnails) loads through
  `Loader.source` so a missing Quickshell type can't break the shell; a crash-looping shell is
  replaced by the safe-mode unit.

## Per-machine state lives outside the repository

`config/` is symlinked into `~/.config`; generated files would otherwise show as repository
changes and be wrong on the next machine. So:

| Path | Written by |
|---|---|
| `~/.config/aether-shell/config.json` (0600) | the shell (live), `aether config/theme/profile` |
| `~/.config/aether-shell/hypr/{hardware,compat,profile,theme,cursor,hypridle}.conf` | `aether graphics configure`, `hyprland compat` (also at login, `--if-stale`), `performance hyprland`, `theme apply`, `theme cursor`, `idle apply` |
| `~/.config/aether-shell/terminal/*` | `aether theme apply` (kitty/foot/alacritty/ghostty themes, kitty settings, zsh profile) |
| `~/.config/aether-shell/{profiles/,layouts.json}` | `aether profile save/import`, `aether layout save` |
| `~/.local/state/aether/` | logs, `manifest.tsv` + `install.state` (installer), `snapshots/`, layout undo |
| `~/.cache/aether-shell/shaders/` | `scripts/build-shaders.sh` (shaders for the installed Qt) |
| `$XDG_RUNTIME_DIR/aether-*` | recorder PID, cava config, lock marker (tmpfs: gone at logout) |

## Version-dependent Hyprland syntax

`compat.conf` is generated for the installed Hyprland: gesture syntax (< 0.51 vs ≥ 0.51) and
which rules file to source (`rules.conf` < 0.53, `rules-v2.conf` ≥ 0.53). It's regenerated at
every login when the version changed (`aether hyprland compat --if-stale`). Tests keep the two
rule files equivalent.

## Testing

`tests/run-all.sh` runs 11 suites (plus generated-file checks in CI) — see [TEST_REPORT.md](TEST_REPORT.md) for what each one
actually proves and what still needs a real session.
