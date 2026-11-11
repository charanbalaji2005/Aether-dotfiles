# AetherOS

**A complete, GPU-aware Hyprland desktop for Fedora.** An original shell built on
Quickshell/QML with its own animation and graphics engine, a hardware-aware backend, an
optional local-first assistant, and an installer that can check, preview, install, update,
uninstall and roll back.

> **Status: 1.0.0-rc.2 — ready for private testing.** Implemented and covered by automated
> tests (incl. Quickshell API conformance against 0.2.0–0.3.2 and a real RPM build). **Not yet
> runtime- or hardware-verified**: PAM unlock, NVIDIA/RTX 4050 behaviour, suspend/resume and
> multi-monitor need the checklist in [docs/HARDWARE.md](docs/HARDWARE.md). Third-party widgets
> are off by default and are not sandboxed ([SECURITY.md](SECURITY.md)). Keep a TTY
> (Ctrl+Alt+F3) handy for the first login and read [RECOVERY.md](RECOVERY.md).

## Install (Fedora 41+)

```sh
git clone https://github.com/OWNER/aetheros-dotfiles ~/aetheros-dotfiles && cd ~/aetheros-dotfiles
./install.sh --check      # read-only preflight
./install.sh --dry-run    # everything it would do
./install.sh              # install (asks before packages; never replaces ~/.zshrc without a yes)
```

Undo at any time with `./install.sh --rollback`. Details: [INSTALLATION.md](INSTALLATION.md).

## What you get

| | |
|---|---|
| **Shell** | panel, dock (magnification, previews), Dynamic Island, overview/exposé, launcher (apps, settings, files, commands), control centre, dashboard, system centre, notification centre, window layouts, assistant, desktop widgets, lock screen (PAM) |
| **Look** | 18 palettes + your own themes (shared with kitty/foot/alacritty/ghostty and Hyprland borders), glass presets, five original GLSL shaders with fallbacks, physics springs, 5 motion profiles, wallpaper engine (transitions, depth parallax, particles, aurora, gradients, video, schedules, per workspace) |
| **GPU** | NVML telemetry without waking a sleeping hybrid dGPU, quality tiers (eco/performance/balanced/ultra) chosen from hardware, power, frame pacing and GPU/VRAM pressure — with the reasons shown |
| **System** | keyboard (XKB-validated), mouse/touchpad, displays with auto-revert, startup apps, workspaces and session restore, power profiles and auto power-saver, idle dim/lock/suspend, updates, user services, security posture |
| **Safety** | snapshots with checksums, last-known-good, safe-mode shell on crash loops, one-command recovery, audit log, secret redaction, no command strings from settings, profiles, rules or the assistant |

28 Settings sections, searchable — [docs/SETTINGS.md](docs/SETTINGS.md). Keys —
[docs/KEYBINDS.md](docs/KEYBINDS.md). CLI — [docs/CLI_REFERENCE.md](docs/CLI_REFERENCE.md) (34 commands, generated from the code).

## Documentation

[INSTALLATION](INSTALLATION.md) · [RECOVERY](RECOVERY.md) · [HARDWARE](docs/HARDWARE.md) ·
[GPU optimisation](docs/GPU_OPTIMIZATION.md) · [Settings](docs/SETTINGS.md) ·
[Customization](docs/CUSTOMIZATION.md) · [Assistant](docs/AI_ASSISTANT.md) ·
[Automation](docs/AUTOMATION.md) · [Widgets](docs/WIDGETS.md) · [CLI](docs/CLI_REFERENCE.md) ·
[Keybinds](docs/KEYBINDS.md) · [Troubleshooting](docs/TROUBLESHOOTING.md) ·
[NVIDIA](docs/NVIDIA_GUIDE.md) · [Drivers](docs/DRIVER_GUIDE.md) · [Hyprland](docs/HYPRLAND_GUIDE.md) ·
[Architecture](ARCHITECTURE.md) · [Testing](docs/TESTING.md) · [Test report](TEST_REPORT.md) ·
[Progress](PROGRESS.md) · [Changelog](CHANGELOG.md) · [Security](SECURITY.md) ·
[Contributing](CONTRIBUTING.md) · [Code of conduct](CODE_OF_CONDUCT.md)

## License

Copyright (C) 2026 Charan Balaji. GPL-3.0-or-later — see [LICENSE](./LICENSE). Third-party
attributions in [THIRD_PARTY.md](./THIRD_PARTY.md).
