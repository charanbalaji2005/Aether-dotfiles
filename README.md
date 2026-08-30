# AetherOS dotfiles

A complete Hyprland environment: compositor config, the original AetherOS Shell (Quickshell),
terminal, shell rc, theming, and install scripts — everything needed to go from a fresh Fedora
install to a working Hyprland desktop, not just the panel/launcher UI on its own.

```
aetheros-dotfiles/
├── install.sh                    # fresh-machine setup: packages, Quickshell build, symlinks
├── config/
│   ├── hypr/                     # Hyprland: monitors, workspaces, keybinds, rules, env
│   ├── quickshell/aether-shell/  # the shell itself — panel, launcher, dashboard, lock screen, etc.
│   ├── kitty/                    # terminal config, themed to match the shell
│   └── zsh/                      # shell rc: prompt, aliases, completion
├── theme/
│   ├── gtk/                      # GTK app theming (dark mode, fonts, cursor)
│   └── wallpapers/                # bring your own — see theme/wallpapers/README.md
├── scripts/
│   ├── setup-symlinks.sh         # links config/ and theme/ into ~/.config etc.
│   ├── update.sh                 # git pull + re-symlink
│   └── bin/aether                # CLI: reload, lock, screenshot, doctor, ...
├── packages/fedora.txt           # dnf package list
├── docs/
│   ├── KEYBINDS.md
│   └── TROUBLESHOOTING.md
└── THIRD_PARTY.md
```

## Install (Fedora)

```sh
git clone <this-repo> ~/aetheros-dotfiles
cd ~/aetheros-dotfiles
./install.sh
```

This installs packages from `packages/fedora.txt`, builds Quickshell from source (no official
Fedora package exists yet), and symlinks every config into place. **Nothing is deleted** —
existing configs at the target paths get backed up with a timestamp suffix, not overwritten.
Log out and pick Hyprland at your display manager (or start it from a TTY) when it's done.

Already on Hyprland and just want the configs, no package install?
```sh
./scripts/setup-symlinks.sh
```

Clipboard history capture runs as a systemd `--user` service
(`system/systemd/aether-clipboard.service`), not a bare Hyprland `exec-once` — it restarts
automatically if it crashes. `bootstrap.sh` enables it; if you only ran `setup-symlinks.sh`,
enable it yourself:
```sh
systemctl --user enable --now aether-clipboard.service
```

## What's here vs. what's the shell

This repo has two layers:

1. **The dotfiles layer** (this level) — Hyprland config, terminal, shell rc, theming, install
   scripts. Everything in this README.
2. **The shell** (`config/quickshell/aether-shell/`) — the actual desktop UI: panel, launcher,
   notifications, dashboard, lock screen, power menu, clipboard history, screenshots. It has its
   own README, ARCHITECTURE.md, and PROGRESS.md — that's the bigger, actively-developed piece and
   its docs track feature status in detail.

## Status

The dotfiles layer (Hyprland config, kitty, zsh, install/symlink scripts, package list) is
complete for a working single-machine setup, and now includes an original AetherOS GTK
stylesheet (`theme/gtk/*/gtk.css`, not visually verified — see PROGRESS.md). What it doesn't
include yet: a wallpaper engine (bring your own image +
hyprpaper for now), and distro-installer-level tooling (Plymouth/GRUB branding, ISO build) — those
belong to the broader AetherOS distribution project, not this dotfiles repo.

For the shell's own feature-by-feature status (what's built, what's flagged as unverified, what's
not started), see `config/quickshell/aether-shell/PROGRESS.md` — it's the more detailed of the two
and shouldn't be treated as fully covered by this summary.

## License

Copyright (C) 2026 Charan Balaji. All rights reserved.

Licensed under GPL-3.0-or-later — see [LICENSE](./LICENSE). Third-party attributions in [THIRD_PARTY.md](./THIRD_PARTY.md).
