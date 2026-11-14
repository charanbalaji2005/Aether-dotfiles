<div align="center">

# AetherOS Dotfiles

**A macOS-inspired, GPU-aware Hyprland desktop for Fedora**

by **Neelampalli Charan Balaji**

[![License: GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue)](LICENSE)
[![Fedora 41+](https://img.shields.io/badge/Fedora-41%2B-294172?logo=fedora&logoColor=white)](INSTALL.md)
[![Hyprland 0.4x–0.57](https://img.shields.io/badge/Hyprland-0.4x%E2%80%930.57-58e1ff)](docs/HYPRLAND_GUIDE.md)
[![Version 1.0.0](https://img.shields.io/badge/version-1.0.0-b392f0)](CHANGELOG.md)

⭐ **If you like it, please [star the repository](https://github.com/charanbalaji2005/Aether-dotfiles)** — it helps other people find it.

![The AetherOS home look: top bar, Dynamic Island and wallpaper](docs/images/home-look.jpg)

</div>

---

## Contents

1. [Install in one command](#install-in-one-command)
2. [Screenshots](#screenshots)
3. [The installer](#the-installer)
4. [Features](#features)
5. [Components](#components)
6. [Keybindings](#keybindings)
7. [After installing](#after-installing)
8. [Update, restore, uninstall](#update-restore-uninstall)
9. [Hardware and GPUs](#hardware-and-gpus)
10. [Troubleshooting](#troubleshooting)
11. [Project layout](#project-layout)
12. [Documentation — every page](#documentation--every-page)
13. [Status](#status)
14. [Support and contributing](#support-and-contributing)
15. [License](#license)

---

## Install in one command

On **Fedora 41 or newer**, as your normal user (not root):

```sh
sh <(curl -fsSL https://raw.githubusercontent.com/charanbalaji2005/Aether-dotfiles/release-final/auto-install.sh)
```

That downloads AetherOS and opens the installer: pick your components, answer a few questions, and
it does the rest. To install **everything with no questions at all**:

```sh
sh <(curl -fsSL https://raw.githubusercontent.com/charanbalaji2005/Aether-dotfiles/release-final/auto-install.sh) --auto
```

`--auto` installs every recommended component and all their packages, enables the Hyprland COPR,
downloads the icon font, uses AetherOS's `~/.zshrc` (yours is moved aside, never deleted), makes zsh
your login shell, turns Bluetooth on, and installs a login screen (SDDM) only if your machine has
none. sudo asks for your password once.

Prefer to look before you run? Clone it yourself:

```sh
git clone -b release-final https://github.com/charanbalaji2005/Aether-dotfiles ~/Aether-dotfiles
cd ~/Aether-dotfiles
./install.sh --dry-run     # shows every link, move, package and command — changes nothing
./install.sh               # the installer
```

When it finishes: **log out, choose "Hyprland" on the login screen, log in.** `SUPER + H` shows
every keybinding.

> **Fedora 44 doesn't ship Hyprland.** The installer gets Hyprland 0.57, hypridle, hyprlock, the
> portal, polkit agent, hyprsunset, hyprpicker, hyprpaper, swww and nwg-look from the
> [sdegler/hyprland](https://copr.fedorainfracloud.org/coprs/sdegler/hyprland/) COPR — after
> asking you, or automatically with `--auto`.

### How long it takes

Measured on a completely bare Fedora 44: **736 packages, 632 MiB**. A normal Fedora Workstation
already has most of them (GTK, PipeWire, NetworkManager, fonts), so it downloads far less.

| Your internet | Fedora Workstation | Bare / minimal Fedora |
|---|---|---|
| 100 Mbit/s | about 3–4 minutes | about 5 minutes |
| 20 Mbit/s | about 5–6 minutes | about 8 minutes |
| 10 Mbit/s | about 7–9 minutes | about 12 minutes |

Packages download ten at a time. The configuration itself takes under a minute.

### Requirements

| | |
|---|---|
| System | Fedora Workstation (or any DNF edition) 41+, x86_64 or aarch64 — not Atomic (Silverblue, Kinoite) |
| Account | your normal user with sudo |
| Disk | about 1 GiB free (more on a minimal system) |
| Network | needed for packages and the Nerd Font |
| Other distributions | configs only: `./install.sh --install --no-packages` — see [packages/generic/README.md](packages/generic/README.md) |

---

## Screenshots

### The desktop

<table>
<tr>
<td width="50%"><img src="docs/images/home-look.jpg" alt="Home look"><br><b>Home look</b> — a slim top bar with workspaces, clock and status on the left and right, the Dynamic Island in the middle, colours taken from the wallpaper.</td>
<td width="50%"><img src="docs/images/home-island-dock.jpg" alt="Bar, island and dock"><br><b>Bar, island and dock</b> — music playing in the island at the top; the macOS-style dock with app icons and running-app dots at the bottom.</td>
</tr>
<tr>
<td><img src="docs/images/h2-apps.jpg" alt="Tiled windows"><br><b>Working</b> — three tiled terminals with rounded corners and frosted borders; the dock stays out of the way.</td>
<td><img src="docs/images/h2-music.jpg" alt="Island with music"><br><b>Music while working</b> — the island opens into a player with album art, title, artist and controls.</td>
</tr>
</table>

### Dynamic Island

<img src="docs/images/island-states.png" alt="Dynamic Island states">

The island changes with what's happening: **idle** shows the date and time; **music** shows album
art, title, artist and a live waveform (click it for a seekable player); **volume and brightness**
show a level bar for two seconds. It peeks open when the track changes and hides in fullscreen.

### Launchpad, launchers and control centre

<table>
<tr>
<td width="50%"><img src="docs/images/launchpad.jpg" alt="Launchpad"><br><b>Launchpad</b> (<code>SUPER + D</code>) — a full-screen, searchable app grid like macOS.</td>
<td width="50%"><img src="docs/images/launchers.jpg" alt="Launcher styles"><br><b>Four launcher styles</b> — aether, grid, side and strip; every look picks one.</td>
</tr>
<tr>
<td><img src="docs/images/control-centre.png" alt="Control centre"><br><b>Control centre</b> (<code>SUPER + A</code>) — Wi-Fi, Bluetooth, focus mode, now playing, brightness and volume sliders, lock, screenshot and more.</td>
<td><img src="docs/images/control-centre-editor.jpg" alt="Control centre editor"><br><b>Make it yours</b> — add, remove and reorder every control centre tile, with a live preview.</td>
</tr>
</table>

### Looks, lock screens and wallpapers

<table>
<tr>
<td width="50%"><img src="docs/images/looks.jpg" alt="Looks"><br><b>16 one-step looks</b> (<code>SUPER + CTRL + L</code>) — each sets the bar layout, bar style, launcher, palette and spacing at once.</td>
<td width="50%"><img src="docs/images/identity-looks.jpg" alt="Colour identities"><br><b>Colour identities</b> — anime, cyber, glass, emerald, retrowave, devpro and more; every app follows.</td>
</tr>
<tr>
<td><img src="docs/images/lockscreens.jpg" alt="Lock screens"><br><b>10 lock screen designs</b> — signature, stacked, typography, glass, island, focus, retro and others (<code>aether-lock design NAME</code>).</td>
<td><img src="docs/images/wallpaper-gallery.jpg" alt="Wallpaper gallery"><br><b>Wallpaper gallery</b> (<code>SUPER + W</code>) — previews, search, favourites and categories; colours update from the picture.</td>
</tr>
</table>

### Keybindings and settings

<table>
<tr>
<td width="50%"><img src="docs/images/keys.jpg" alt="Keybinding reference"><br><b>Keybinding reference</b> (<code>SUPER + H</code>) — every shortcut, searchable, generated from the real config.</td>
<td width="50%"><img src="docs/images/settings-a.png" alt="Settings: looks, appearance, island, dock"><br><b>Settings</b> (<code>SUPER + CTRL + S</code>) — looks, appearance, island and dock pages.</td>
</tr>
<tr>
<td colspan="2"><img src="docs/images/settings-b.png" alt="Settings: bar, lock screen, wallpaper, keyboard, system"><br><b>More settings</b> — bar, lock screen, wallpaper, keyboard shortcuts and system pages.</td>
</tr>
</table>

---

## The installer

`./install.sh` (and the one-command install) opens an interactive installer. These are real
captures of it running.

<table>
<tr>
<td width="33%"><img src="docs/images/installer/welcome.png" alt="Welcome"><br><b>1. Welcome</b> — logo, version, copyright, and your machine: Fedora version, kernel, CPU, every GPU and the driver it uses, memory, display, desktop, Hyprland/Waybar/Quickshell versions, login manager, free disk, prerequisites.</td>
<td width="33%"><img src="docs/images/installer/support.png" alt="Support"><br><b>2. Support</b> (first run only) — the repository link; open it in your browser, or star it with a signed-in GitHub CLI, only if you choose to.</td>
<td width="33%"><img src="docs/images/installer/menu.png" alt="Main menu"><br><b>3. Main menu</b> — start an installation, update, restore your previous configuration, read the installation information. An interrupted install is detected and resumed.</td>
</tr>
<tr>
<td><img src="docs/images/installer/presets.png" alt="Presets"><br><b>4. Choose components</b> — Recommended, Select all, Custom or Deselect all.</td>
<td><img src="docs/images/installer/components.png" alt="Components"><br><b>5. Custom selection</b> — tick exactly what you want. Anything you leave out keeps your current configuration.</td>
<td><img src="docs/images/installer/ready.png" alt="Summary"><br><b>6. Summary</b> — every question (packages, COPR, ~/.zshrc, font, Bluetooth, login screen) is asked before this, so the installation then runs on its own.</td>
</tr>
<tr>
<td><img src="docs/images/installer/progress.png" alt="Live progress"><br><b>7. Live progress</b> — numbered steps with a spinner and timer; during downloads a bar with percentage, speed and size, plus the latest log lines. A failing component doesn't stop the others.</td>
<td><img src="docs/images/installer/done.png" alt="Finished"><br><b>8. Finished</b> — installed, skipped and failed components, validation results, backup, log and report.</td>
<td><img src="docs/images/installer/final-menu.png" alt="Final menu"><br><b>9. Final menu</b> — restart the Hyprland desktop, reboot (asked — never automatic), view the log or the report.</td>
</tr>
</table>

### What it does, step by step

1. **Preflight** — Fedora release and edition, DNF5/DNF4, sudo, disk and memory, GPUs and drivers,
   SELinux (reported, never changed), your login manager (kept), bars or notification daemons that
   would clash, and every path it would touch that already has something in it.
2. **Dependencies** — the packages of the components you picked, each checked against your enabled
   repositories first. Missing ones come from COPR only after a yes. For a GPU whose driver is
   already working, optional helpers are added — **drivers are never installed or replaced**.
3. **Backup** — everything at the paths it manages is archived to `~/.aetheros-backups/`.
4. **Deploy** — each component's configs are linked from the repository. Anything in the way is
   **moved aside** to `<path>.bak.<time>` and listed for restore, never deleted. From an old
   Hyprland config, your **keybinds** are saved (commented out) in
   `~/.config/aether-shell/hypr/user.conf`, your **scripts** in
   `~/.config/aether-shell/user/hypr-scripts`, and replaced **wallpapers** in `~/Pictures/Wallpapers`.
5. **Final configuration** — settings migration, Hyprland version-specific rules, GPU settings,
   colours for every app, idle timings, shaders compiled for your Qt.
6. **Services** — AetherOS's user services; Bluetooth and SDDM only when you said yes.
7. **Validation** — Hyprland config, Waybar layouts, Rofi themes, Quickshell, SwayNC, required
   programs, broken links, programs started twice. The report goes to
   `~/.local/state/aether/reports/`.

Without menus:

```sh
./install.sh --check                                   # read-only preflight
./install.sh --dry-run                                 # everything it would do
./install.sh --install                                 # the recommended components
./install.sh --install --components hyprland,waybar,rofi,terminal
./install.sh --install --preset minimal
./install.sh --list-components
```

Every option is explained in **[INSTALL.md](INSTALL.md)**.

---

## Features

### Desktop (classic interface — the default)

- **Top bar** (Waybar) — 15 layouts and 15 styles; workspaces, clock, media, network, Bluetooth,
  audio, battery, tray; hide/show with `SUPER + ALT + B`.
- **Dynamic Island** — music with album art, waveform and a seekable player; volume and
  brightness levels; built with Quickshell (falls back to a Waybar island without it).
- **macOS-style dock** — magnification under the pointer, dots for running apps, auto-hide (always,
  smart or off), right-click menu with windows, New Window, Keep in Dock and Quit.
- **Launchpad and menus** (Rofi) — apps, run, window switcher, files, Wi-Fi, Bluetooth, audio
  devices, clipboard history, emoji, calculator, web search, theme, quick settings, keybinding
  reference.
- **Notifications** (SwayNC) — a notification centre, do-not-disturb, themed popups.
- **Power menu, lock screen, idle** — Wlogout, 10 Hyprlock designs, Hypridle dim → lock → suspend.
- **Wallpapers** — 21 bundled, a gallery with favourites and categories, animated transitions (swww),
  random or next with one key.

### Look

- **Colours from your wallpaper** for the bar, launcher, notifications, lock screen, terminal,
  borders and GTK apps — or one of 18 palettes, or your own theme.
- **16 one-step looks**, frosted-glass presets (`aether-glass`), dark/light switch.
- The optional **aether interface**: an original Quickshell shell with its own animation and
  graphics engine — physics springs, five GLSL shaders with fallbacks, five motion profiles.

### GPU-aware

- Detects every GPU and its driver; hybrid laptops stay on the integrated GPU (`aether gpu run`
  sends one program to the discrete GPU).
- NVML telemetry that doesn't wake a sleeping NVIDIA GPU; quality tiers (eco, balanced,
  performance, ultra) chosen from hardware, power and frame pacing — with the reasons shown.
- NVIDIA on nouveau gets a plan only: `aether graphics install-nvidia --dry-run`.

### System

Keyboard (XKB-validated) and touchpad settings, displays with auto-revert, startup apps,
workspaces and session restore, power profiles and automatic power saver, night light, updates,
user services, a security overview.

### Safety

Backups and a moved-aside list for every install, `./restore.sh`, settings snapshots with
checksums, a last-known-good state, a safe-mode shell after crash loops, one-command recovery
(`aether recover`), an audit log, secret redaction, and no command strings taken from settings,
profiles, rules or the assistant.

---

## Components

| ID | Component | Main packages |
|---|---|---|
| `hyprland` | Hyprland configuration — keys, rules, animations, idle and lock | hyprland, hypridle, hyprlock, portal, polkit agent, hyprsunset, grim, slurp |
| `waybar` | Waybar — macOS-inspired top bar | waybar, network-manager-applet |
| `dynamic-island` | Dynamic Island — music player in the bar | quickshell, playerctl, cava |
| `dock` | macOS Dock — magnifying dock with running-app dots | gtk-layer-shell, python3-cairo |
| `rofi` | Rofi Launchpad — apps, Wi-Fi, Bluetooth, clipboard, emoji menus | rofi, qalculate |
| `terminal` | Kitty terminal, themed from your wallpaper, with tmux | kitty, tmux |
| `shell` | Zsh and shell configuration | zsh, autosuggestions, syntax highlighting, eza, bat, fzf, zoxide |
| `themes` | GTK themes and icons | adw-gtk3-theme, papirus-icon-theme, nwg-look, qt5ct, qt6ct, kvantum |
| `wallpapers` | 21 wallpapers; yours are kept | swww |
| `fonts` | JetBrains Mono, Noto, JetBrainsMono Nerd Font | jetbrains-mono-fonts-all, noto fonts |
| `notifications` | SwayNC centre and popups | SwayNotificationCenter |
| `bluetooth` | BlueZ and Blueman | bluez, blueman |
| `audio` | PipeWire, WirePlumber, volume and media keys | pipewire, wireplumber, pavucontrol, pamixer |
| `login-manager` | SDDM theme (SDDM only; GDM is left alone) | — |
| `apps` | power menu, colours, fastfetch, file manager | wlogout, fastfetch, Thunar |
| `aether-shell` | the Quickshell desktop (`--interface aether`) | quickshell, Qt 6 |

Exact lists: [packages/fedora/components.tsv](packages/fedora/components.tsv) (per component),
[packages/fedora/packages.txt](packages/fedora/packages.txt) (always),
[packages/fedora/repos.conf](packages/fedora/repos.conf) (COPR sources).

---

## Keybindings

`SUPER + H` shows all of them. The most used:

| Keys | Action | Keys | Action |
|---|---|---|---|
| `SUPER + Enter` | Terminal | `SUPER + D` | Launchpad / apps |
| `SUPER + Q` | Close window | `SUPER + E` | File manager |
| `SUPER + F` | Fullscreen | `SUPER + V` | Clipboard history |
| `SUPER + 1…0` | Workspace 1–10 | `SUPER + .` | Emoji picker |
| `SUPER + SHIFT + 1…0` | Move window to workspace | `SUPER + A` | Control centre |
| `SUPER + W` | Wallpaper gallery | `SUPER + N` | Notification centre |
| `SUPER + CTRL + L` | Looks | `SUPER + T` | Theme and colours |
| `SUPER + L` | Lock | `SUPER + Esc` | Power menu |
| `Print` / `SHIFT + Print` | Screenshot: screen / area | `SUPER + CTRL + S` | Settings |
| `ALT + Print` | Capture menu | `SUPER + CTRL + R` | Reload the desktop |

Full list: [docs/KEYBINDS.md](docs/KEYBINDS.md). Your own binds go in
`~/.config/aether-shell/hypr/user.conf` (check them with `aether-bindings check`).

---

## After installing

- `aether diagnostics` — a full health report; `aether graphics verify` — GPU checks.
- `aether snapshot mark-good` once everything is the way you like it: `aether recover` can return
  to it later.
- `aether-interface set aether` — try the Quickshell shell; `aether-interface set classic` — back.
- Your desktop runs from the AetherOS folder (`~/.local/share/aether-dotfiles` with the
  one-command install): **don't delete it**.

---

## Update, restore, uninstall

```sh
./update.sh                 # snapshot settings, git pull, re-link your components, validate
./restore.sh                # menu: undo the whole installation, or pick a backup archive
./restore.sh FILE           # restore one archive from ~/.aetheros-backups
./install.sh --rollback     # undo the installation: every original file goes back
./install.sh --uninstall    # remove AetherOS's links and services, keep everything else
```

Rollback lists the packages, COPR repositories and login-screen theme the installer added, with
the exact commands to remove them; it never removes packages by itself.

---

## Hardware and GPUs

| GPU | What AetherOS does |
|---|---|
| Intel / AMD | Mesa; optional Vulkan and video-acceleration helpers |
| NVIDIA with the proprietary driver | kept as is; NVIDIA environment, NVML telemetry, EGL/VA-API helpers |
| NVIDIA on nouveau | nothing installed or replaced; a reviewable plan: `aether graphics install-nvidia --dry-run` |
| Hybrid laptop | desktop on the integrated GPU; `aether gpu run APP` for the discrete one |

Guides: [docs/HARDWARE.md](docs/HARDWARE.md) · [docs/NVIDIA_GUIDE.md](docs/NVIDIA_GUIDE.md) ·
[docs/DRIVER_GUIDE.md](docs/DRIVER_GUIDE.md) · [docs/GPU_OPTIMIZATION.md](docs/GPU_OPTIMIZATION.md)

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Bar, dock or island missing | `SUPER + CTRL + R` (or `aether-classic-start --reload`) |
| Something looks broken | `aether-interface doctor`, then `aether repair` |
| Icons show as boxes | `scripts/install-fonts.sh` (JetBrainsMono Nerd Font) |
| Hyprland won't start | from a TTY (`Ctrl+Alt+F3`): `Hyprland -c ~/.config/hypr/recovery.conf` |
| I want my old setup back | `./restore.sh` |
| What did the installer do? | the report in `~/.local/state/aether/reports/` and the log in `~/.local/state/aether/logs/` |

More: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) · [RECOVERY.md](RECOVERY.md)

---

## Project layout

```
install.sh            the installer (onboarding, --install, --update, --restore, --rollback…)
auto-install.sh       the one-command download-and-install
update.sh restore.sh  shortcuts for updating and restoring
functions/            installer UI (dialogs, live progress), hardware detection, components, validation
install-scripts/      one script per component + dependencies, deployment, services
assets/               logo, SDDM login theme
config/               hypr, waybar, rofi, quickshell, kitty, zsh, swaync, wlogout, wallust, fastfetch, tmux
theme/                GTK settings, wallpapers
scripts/              setup-symlinks, backup, restore, doctor, fonts; bin/ — the aether-* commands
lib/aether/           the Python backend behind the `aether` command (hardware, GPU, settings, themes…)
system/systemd/       user services
packages/             Fedora package lists, COPR sources, other-distro notes
packaging/            RPM spec, Arch PKGBUILD, release tarball
tests/                automated tests (installer, onboarding, configs, QML, Python, packaging)
docs/                 guides and screenshots
```

---

## Documentation — every page

| Page | What it covers |
|---|---|
| [INSTALL.md](INSTALL.md) | Installing: the one-command install, every installer screen and option, packages, update and restore |
| [RECOVERY.md](RECOVERY.md) | Getting back to a working desktop: TTY recovery, safe mode, snapshots, rollback |
| [docs/CLASSIC_INTERFACE.md](docs/CLASSIC_INTERFACE.md) | The classic desktop: bar layouts and styles, looks, launcher, island, dock, lock screens |
| [docs/KEYBINDS.md](docs/KEYBINDS.md) | Every keybinding |
| [docs/SETTINGS.md](docs/SETTINGS.md) | Every settings page and option |
| [docs/CUSTOMIZATION.md](docs/CUSTOMIZATION.md) | Making it yours: themes, palettes, bar, binds, rules |
| [docs/HYPRLAND_GUIDE.md](docs/HYPRLAND_GUIDE.md) | How AetherOS configures Hyprland, version differences (incl. 0.57's Lua config) |
| [docs/HARDWARE.md](docs/HARDWARE.md) | Hardware compatibility and the test checklist |
| [docs/GPU_OPTIMIZATION.md](docs/GPU_OPTIMIZATION.md) | GPU-aware rendering, quality tiers and telemetry |
| [docs/NVIDIA_GUIDE.md](docs/NVIDIA_GUIDE.md) | NVIDIA on Fedora + Hyprland |
| [docs/DRIVER_GUIDE.md](docs/DRIVER_GUIDE.md) | Graphics drivers on Fedora |
| [docs/WIDGETS.md](docs/WIDGETS.md) | Desktop widgets for users and developers |
| [docs/AI_ASSISTANT.md](docs/AI_ASSISTANT.md) | The optional, local-first assistant |
| [docs/AUTOMATION.md](docs/AUTOMATION.md) | Rules and automation |
| [docs/CLI_REFERENCE.md](docs/CLI_REFERENCE.md) | Every `aether` command (generated from the code) |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common problems and fixes |
| [docs/TESTING.md](docs/TESTING.md) | The automated tests and how to run them |
| [ARCHITECTURE.md](ARCHITECTURE.md) | How the pieces fit together |
| [config/quickshell/aether-shell/README.md](config/quickshell/aether-shell/README.md) | The Quickshell shell (aether interface) |
| [theme/wallpapers/README.md](theme/wallpapers/README.md) | Wallpapers and the wallpaper commands |
| [packages/generic/README.md](packages/generic/README.md) | Package names for other distributions |
| [SECURITY.md](SECURITY.md) | Security model and reporting a vulnerability |
| [CHANGELOG.md](CHANGELOG.md) | What changed in each version |
| [TEST_REPORT.md](TEST_REPORT.md) | Test results |
| [PROGRESS.md](PROGRESS.md) | Development progress |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | Community guidelines |
| [THIRD_PARTY.md](THIRD_PARTY.md) | Third-party software and provenance |
| [PUBLISHING.md](PUBLISHING.md) | Release checklist (maintainers) |

---

## Status

**1.0.0.** Covered by automated tests — the installer and onboarding end to end, configs, QML
structure, Quickshell API conformance (0.2.0–0.3.2), Python backend, a real RPM build — and
installed end to end on a bare Fedora 44 (736 packages, every component, 0 failed checks). Used
daily on Fedora 44 with Hyprland 0.57.

Not yet confirmed on other hardware: PAM unlock in the aether shell, the NVIDIA proprietary driver,
suspend/resume and multi-monitor — see the checklist in [docs/HARDWARE.md](docs/HARDWARE.md).
Third-party widgets are off by default and not sandboxed ([SECURITY.md](SECURITY.md)). Keep a TTY
(`Ctrl+Alt+F3`) in mind for your first login.

---

## Support and contributing

- ⭐ **Star the repository**: <https://github.com/charanbalaji2005/Aether-dotfiles>
- 🐞 **Bugs and ideas**: [open an issue](https://github.com/charanbalaji2005/Aether-dotfiles/issues) —
  attach the output of `aether diagnostics` and your installation report.
- 🛠 **Contributing**: read [CONTRIBUTING.md](CONTRIBUTING.md); run `tests/run-all.sh` before a pull
  request.
- 📣 **Share it** with people who love a beautiful desktop.

---

## License

Copyright (C) 2026 **Neelampalli Charan Balaji**.

AetherOS Dotfiles is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License, version 3 or (at your option) any later version — see
[LICENSE](LICENSE). Third-party software it uses is listed in [THIRD_PARTY.md](THIRD_PARTY.md).
