# ULTRON RECOVERY

**ADVANCED LINUX RECOVERY SYSTEM · FEDORA HYPRLAND EDITION**

Developed by **NEELAMPALLI CHARAN BALAJI**

*Your desktop. Your control. Every failure has a recovery.*

ULTRON RECOVERY diagnoses, backs up, repairs and rolls back a Fedora Hyprland
desktop built from the AetherOS dotfiles. It is plain Bash and runs from a
bare TTY: no Hyprland, Waybar, Rofi or Quickshell needed.

## Install

```bash
cd ultron-recovery
./install.sh            # for your user, no root
./install.sh --system   # also /usr/local/bin/ultron-recovery (sudo), for any TTY PATH
```

The app is **copied** to `~/.local/share/ultron-recovery/app`, so it keeps
working if the dotfiles repository or the desktop breaks. `update.sh`
reinstalls from the checkout it came from (`--pull` updates that first);
`uninstall.sh` removes the app and keeps your backups (`--purge` deletes them
too, after asking).

| Purpose | Location |
| --- | --- |
| Application | `~/.local/share/ultron-recovery/app/` |
| Configuration | `~/.config/ultron-recovery/recovery.conf` |
| Backups | `~/.local/share/ultron-recovery/backups/` |
| Logs | `~/.local/share/ultron-recovery/logs/` |
| Reports | `~/.local/share/ultron-recovery/reports/` |

## Use

```text
ultron-recovery                      interactive menu
ultron-recovery --diagnose           full diagnostics + report (exit 1 if problems)
ultron-recovery --repair waybar      repair one component (or: all)
ultron-recovery --dry-run --repair all   preview every change
ultron-recovery --safe               read-only: checks and recommendations only
ultron-recovery --full --repair hyprland  also restore changed configs from the release
ultron-recovery --backup [COMP…]     backup (default: everything)
ultron-recovery --restore [ID [COMP…]]   restore (no ID: pick from a list)
ultron-recovery --rollback           undo the last recovery
ultron-recovery --list-backups | --preview ID | --verify ID
ultron-recovery --deps | --info | --logs | --emergency | --version | --help
```

Components: `hyprland waybar rofi quickshell island kitty shell themes fonts`
(aliases: `dock`, `dynamic-island`, `zsh`, `gtk`, `wallpapers`, …).

### Menu

1 Full System Diagnostics · 2 Full Dotfiles Recovery · 3 Restore Previous
Configuration · 4–12 Repair Hyprland / Waybar / Rofi / Quickshell Dock /
Dynamic Island / Kitty / Shell / GTK Themes and Icons / Fonts and Wallpapers ·
13 Dependency Manager · 14 Backup Manager · 15 System Information · 16 Recovery
Logs · 17 Emergency TTY Recovery · 18 Exit. `m` cycles the mode, `d` toggles
dry run.

## Modes

| Mode | What it does |
| --- | --- |
| **SAFE** | Read-only. Diagnostics and recommendations; never writes. |
| **STANDARD** (default) | Repairs missing files and links, permissions, broken references; restores selected backups. |
| **FULL** | Standard, plus restores changed or invalid configs from the known-good release (the dotfiles repo at `git HEAD`) or the newest backup. |
| **DRY RUN** | With any mode: shows every change, makes none. |

## What it checks and repairs

| Component | Checks | Repairs |
| --- | --- | --- |
| Hyprland | Hyprland's own `--verify-config` (Lua entry on 0.57+), sourced files, monitors, autostart programs, duplicate autostart entries, keybindings defined in two files, links, permissions | relink, restore deleted tracked files, copy missing files, placeholder for missing generated fragments, perms |
| Waybar | JSONC, CSS, modules used by layouts, script syntax, links, perms, duplicate processes | relink/copy, perms, stop duplicates, restart |
| Rofi | `config.rasi`, RASI syntax, `@import`/`@theme` targets | relink/copy, perms |
| Quickshell & dock | installed, `shell.qml`, QML syntax (whole tree), startup wiring, dock running | relink, start dock |
| Dynamic Island | playerctl, MPRIS players, ImageMagick, inotify, the island config and scripts, artwork cache, running when enabled | relink, `+x`, clear corrupt art, restart |
| Kitty | `kitty.conf`, includes, configured font | relink, placeholder includes |
| Shell | zsh/bash/tmux syntax, links, login shell valid | relink, restore `~/.bashrc` from `/etc/skel` |
| GTK | settings.ini, theme / icon / cursor / font installed, GNOME settings | create defaults, point broken names at installed ones |
| Fonts & wallpapers | required fonts, wallpaper file present, wallpaper program | install JetBrainsMono Nerd Font (checksum-verified), font cache, pick a wallpaper that exists |

Duplicate autostart entries and keybinding clashes are reported, not edited:
they can be intentional.

## Safety

* **Backup first.** Every repair or restore takes an automatic `pre-…` backup of
  exactly what it will touch; nothing changes if that backup fails.
* **Confirm first.** Every change is listed and confirmed (`--yes` for scripts).
* **Verified backups.** Each backup has a manifest and SHA-256 checksums; a
  damaged backup is refused, never restored.
* **Rollback.** `--rollback` restores the last automatic backup; a second
  rollback undoes the first.
* **Interrupted runs.** A journal marks an unfinished recovery; the next start
  offers the rollback.
* **Nothing destroyed.** Only paths inside `$HOME` are written. A directory in
  the way of a link is moved aside (`*.ultron-moved-<time>`), never deleted.
  Linked configs (e.g. `~/.config/hypr → dotfiles`) are recorded as links and
  restored as links. No disks, partitions, bootloader, reboots or `sudo`
  (except the Dependency Manager's `dnf` command, which asks).
* **Logged.** Every run writes `~/.local/share/ultron-recovery/logs/ultron-*.log`.

## Recovery from a TTY

1. Press `Ctrl+Alt+F3` and log in.
2. `ultron-recovery --diagnose`
3. `ultron-recovery` → **17 Emergency TTY Recovery**: quick check, restore
   Hyprland from the newest backup, roll back, stop stuck parts, or start a
   **minimal safe Hyprland session** (no autostart, no effects, a terminal with
   ULTRON inside).
4. Return to the desktop: `Ctrl+Alt+F2` (or `F1`).

## Tests

```bash
bash tests/test-backup.sh
bash tests/test-restore.sh
bash tests/test-validation.sh
```

They run in a throwaway `$HOME` with a fake dotfiles repo and never look at or
signal your real desktop processes (`UR_NO_PROCESS=1`).

## Layout

```text
recovery.sh            entry point: CLI and menus
install.sh uninstall.sh update.sh
core/   ui logging detection diagnostics backup restore validation rollback recovery-engine
modules/ hyprland waybar rofi quickshell dynamic-island kitty shell themes
assets/ultron-logo.txt  config/recovery.conf  tests/
```

ULTRON v1.0 · Bash · Fedora Linux · Hyprland
