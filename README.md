# AetherOS

A complete, hardware-aware Hyprland desktop for Fedora: compositor configuration, the original
AetherOS Shell (Quickshell/QML) — panel, launcher, control centre, system dashboard,
notifications, settings, lock screen — a hardware/graphics CLI with a Fedora NVIDIA driver
installer, theming, and safe install/backup/restore tooling.

Works on NVIDIA, AMD and Intel GPUs (including hybrid laptops) and on Intel and AMD CPUs.
Hardware is **detected**, never assumed.

```
aetheros-dotfiles/
├── install.sh                     # fresh-machine setup → scripts/bootstrap.sh
├── config/
│   ├── hypr/                      # Hyprland (+ recovery.conf)
│   ├── quickshell/aether-shell/   # the desktop shell (QML)
│   ├── kitty/  zsh/
├── lib/aether/                    # aether CLI backend (Python, stdlib only)
│   ├── hw/                        #   system · cpu · gpu detection
│   ├── graphics/                  #   Mesa/Vulkan/VA-API · NVIDIA · reports · Hyprland GPU config
│   └── telemetry · performance · theme · cli
├── scripts/                       # bootstrap · setup-symlinks · backup · restore · update · doctor
│   └── bin/aether                 # the CLI entry point
├── system/systemd/                # aether-shell / aether-clipboard user services
├── packages/fedora/               # packages.txt (required) · optional.txt
├── theme/                         # GTK theme, wallpapers
├── docs/                          # guides (below)
└── tests/                         # shellcheck, qmllint, config, Python unit, integration
```

## Install

```sh
git clone <this-repo> ~/aetheros-dotfiles && cd ~/aetheros-dotfiles
./install.sh
```

Asks before installing anything, backs up existing configs, never deletes them. Full details,
dependencies and recovery: **[INSTALLATION.md](INSTALLATION.md)**.

## The desktop

| Surface | Open with | What it does |
|---|---|---|
| **Panel** | always | launcher button, workspaces, window title, centred clock, CPU/RAM/GPU usage + temperatures, network speed, tray, media, Bluetooth, network, volume, microphone, battery, notifications, control centre. Styles: *floating* island (default), *full* width, centred *dock*; top or bottom; adjustable height |
| **Launcher** | `SUPER+D` | fuzzy search over names/keywords/descriptions, favourites, recent apps, categories, keyboard-driven |
| **Control centre** | `SUPER+A` | Wi-Fi (network list, passwords), Bluetooth, DND, night light, dark mode, microphone, battery saver, performance mode, volume / mic / brightness sliders, output & input device selection, media, displays, wallpaper, power |
| **Dashboard** | `SUPER+N` | CPU/RAM/GPU/network graphs, CPU & GPU temperatures, VRAM, disk, per-thread load, top processes, uptime, hardware, calendar |
| **Notifications** | `SUPER+,` | grouped history, per-item/per-app clear, Do Not Disturb, animated toasts with actions |
| **Settings** | `SUPER+I` | theme (dark/light/auto), accent (presets, hex, or from wallpaper), transparency, blur, animation speed, reduced motion, bar, notifications, wallpaper, performance |

Design: glass surfaces (compositor blur + tint + hairline sheen), one token-based design system
for dark and light themes, consistent motion with speed control and reduced-motion support,
original vector icon set. Metrics the hardware can't provide are shown as *Unavailable* with the
reason — never as invented numbers.

## The `aether` CLI

```sh
aether system | hardware | cpu [--watch] | gpu [--watch]
aether gpu run <command>                  # run on the discrete GPU (hybrid laptops)
aether graphics detect | drivers | verify | install-nvidia | configure
aether performance [set <power-profile> | hyprland <quality|balanced|low-latency|battery>]
aether diagnostics | repair | hyprland [compat] | update
aether theme accent <image> | mode <dark|light|auto>
```

Every command reads the live system, supports `--json`, needs no root (privileged steps run as
`sudo <shown command>` after confirmation) and logs to `~/.local/state/aether/aether.log`.

## Guides

- [INSTALLATION.md](INSTALLATION.md) — install, dependencies, update, backup/rollback, recovery
- [docs/DRIVER_GUIDE.md](docs/DRIVER_GUIDE.md) — GPU detection, AMD, Intel, hybrid, CPU
- [docs/NVIDIA_GUIDE.md](docs/NVIDIA_GUIDE.md) — driver branches, RPM Fusion, akmods, Secure Boot, rollback
- [docs/HYPRLAND_GUIDE.md](docs/HYPRLAND_GUIDE.md) — config layout, version compatibility, profiles, multi-monitor
- [docs/KEYBINDS.md](docs/KEYBINDS.md) · [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
- [ARCHITECTURE.md](ARCHITECTURE.md) · [CHANGELOG.md](CHANGELOG.md) · [TEST_REPORT.md](TEST_REPORT.md)
- Shell internals: [config/quickshell/aether-shell/ARCHITECTURE.md](config/quickshell/aether-shell/ARCHITECTURE.md)

## Status

What has and hasn't been verified is tracked honestly in [PROGRESS.md](PROGRESS.md) and
[TEST_REPORT.md](TEST_REPORT.md). In short: scripts, configs and the Python backend are tested
(shellcheck, Qt qmllint, ~85 unit tests against fixture hardware). The QML shell passes
syntax/structure/schema checks but has not been run in a live Quickshell session as part of
this upgrade, and no physical-GPU testing was performed.

## License

Copyright (C) 2026 Charan Balaji. GPL-3.0-or-later — see [LICENSE](./LICENSE). Third-party
attributions in [THIRD_PARTY.md](./THIRD_PARTY.md).
